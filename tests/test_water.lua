-- Water automation ladder (GDD §5.3, §7.4): water table, well and hand pump, solar pump, cistern,
-- drip irrigation.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Water = require("src.sim.systems.water")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24
local COST = tun.water.dripUnitsPerWatering

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
  end
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local SUMMER = 8

--- Place an object on the nearest free tile to `near` (default the spawn) where it fits.
local function place(world, id, near)
  local grid = world.state.grid
  local nx, ny = Grid.coords(grid, near or Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - nx) ^ 2 + (y - ny) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  T.truthy(best, "a spot for " .. id)
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

local function clearPanels(world)
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "folding_panel" then
      Grid.removeObject(world, anchor)
    end
  end
end

local function with(changes, fn)
  local saved = {}
  for _, c in ipairs(changes) do
    saved[#saved + 1] = { c[1], c[2], c[1][c[2]] }
    c[1][c[2]] = c[3]
  end
  local ok, err = pcall(fn)
  for _, s in ipairs(saved) do
    s[1][s[2]] = s[3]
  end
  if not ok then
    error(err, 0)
  end
end

--- Free grass tiles near `near`, nearest first.
local function freeTiles(world, near, count)
  local grid = world.state.grid
  local nx, ny = Grid.coords(grid, near)
  local list = {}
  for i = 1, #grid.terrain do
    if Grid.terrain(world, i).tillable and not world.occupancy[i] and not Crops.tileInUse(world, i) then
      local x, y = Grid.coords(grid, i)
      list[#list + 1] = { i = i, d = (x - nx) ^ 2 + (y - ny) ^ 2 }
    end
  end
  table.sort(list, function(a, b)
    return a.d < b.d or (a.d == b.d and a.i < b.i)
  end)
  local tiles = {}
  for n = 1, count do
    tiles[n] = list[n].i
  end
  return tiles
end

--- A thirsty young crop on tile i (as if planted and not yet watered).
local function plantThirsty(world, i)
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = "radish"
  world.state.crops[i] = { id = "radish", growth = 0.1, moisture = 0 }
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

-- A pump, cistern and solar array on seed `seed`, at midday in summer.
local function pumpingWorld(seed)
  local world = newWorld(seed)
  clearPanels(world)
  place(world, "solar_array")
  place(world, "cistern")
  local pump = place(world, "dc_pump")
  setTime(world, SUMMER, 10)
  return world, pump
end

-- Content ---------------------------------------------------------------------------------------

T.test("water content: every rung has art, a price and a journal node", function()
  local sprites = require("assets.manifest").sprites
  for _, id in ipairs({ "well", "hand_pump", "cistern", "dc_pump", "drip_line" }) do
    local def = reg:get("objects", id)
    T.truthy(sprites[id], id .. " sprite")
    T.truthy(sprites["icon_" .. id], id .. " icon")
    T.truthy(def.placeable, id .. " placeable")
    local item = reg:get("catalog", id)
    T.eq(item.object, id)
    T.truthy(item.price > 0 and item.needs and #item.needs > 0, id .. " priced and gated by notes")
    T.eq(item.page, "water_soil")
  end
  T.truthy(reg:get("objects", "dc_pump").pump.rate > 0)
  T.eq(reg:get("objects", "dc_pump").sink.tier, "pumps")
  T.truthy(reg:get("objects", "drip_line").drip.radius >= 1)
  T.truthy(reg:get("objects", "cistern").storage.water > 0)
  T.eq(reg:get("objects", "well").placeOn, "waterTable")
  T.eq(reg:get("objects", "hand_pump").placeOn, "waterTable")
  T.eq(reg:get("objects", "dc_pump").placeOn, "waterTable")
end)

-- Water table -----------------------------------------------------------------------------------

T.test("water table: seeded, in range, high at the creek and not everywhere", function()
  local a, b = newWorld(11), newWorld(11)
  T.eq(serialize.encode(a.state.grid.waterTable), serialize.encode(b.state.grid.waterTable))
  local other = newWorld(12)
  T.truthy(serialize.encode(a.state.grid.waterTable) ~= serialize.encode(other.state.grid.waterTable))
  local grid = a.state.grid
  local high, total = 0, 0
  for i = 1, #grid.terrain do
    local v = grid.waterTable[i]
    T.truthy(v >= 0 and v <= 1)
    if Grid.terrain(a, i).tillable then
      total = total + 1
      if Land.hasWaterTable(a, i) then
        high = high + 1
      end
    end
  end
  T.truthy(high > total * 0.1 and high < total * 0.7, "a real choice of spots: " .. high .. " of " .. total)
end)

T.test("water table: generating it leaves the plot itself alone", function()
  local world = newWorld(5)
  local before = serialize.encode({ world.state.grid.terrain, world.state.grid.soil, world.state.grid.objects })
  world.state.grid.waterTable = nil
  local Landgen = require("src.sim.landgen")
  Landgen.waterTable(world)
  T.eq(serialize.encode({ world.state.grid.terrain, world.state.grid.soil, world.state.grid.objects }), before)
end)

T.test("placement: wells and pumps need a high water table, cisterns and drip lines do not", function()
  for seed = 1, 8 do
    local world = newWorld(seed * 31)
    local grid = world.state.grid
    local dry, wet
    for i = 1, #grid.terrain do
      if Grid.terrain(world, i).tillable and not world.occupancy[i] then
        if Land.hasWaterTable(world, i) then
          wet = wet or i
        else
          dry = dry or i
        end
      end
    end
    T.truthy(wet and dry, "seed " .. seed .. " has both kinds of ground")
    for _, id in ipairs({ "well", "hand_pump", "dc_pump" }) do
      T.truthy(Inventory.canPlace(world, id, wet), id .. " fits on a high table")
      T.falsy(Inventory.canPlace(world, id, dry), id .. " refused on a low table")
    end
    T.truthy(Inventory.canPlace(world, "drip_line", dry), "drip lines go anywhere")
    T.eq(reg:get("objects", "cistern").placeOn, nil, "cisterns go anywhere")
  end
end)

T.test("placement: a well can be sunk within reach of the start on every seed", function()
  for seed = 1, 12 do
    local world = newWorld(seed * 977)
    local sx, sy = Grid.coords(world.state.grid, Land.spawn(world))
    local found
    for i = 1, #world.state.grid.terrain do
      local x, y = Grid.coords(world.state.grid, i)
      if math.max(math.abs(x - sx), math.abs(y - sy)) <= 12 and Inventory.canPlace(world, "well", i) then
        found = true
        break
      end
    end
    T.truthy(found, "seed " .. seed)
  end
end)

-- Wells and the hand pump -------------------------------------------------------------------------

T.test("well and hand pump: the bucket fills there, faster than the creek, and a note is written", function()
  local world = newWorld(4)
  local hs = Actors.homesteader(world)
  local well = place(world, "well")
  local pump = place(world, "hand_pump", well)
  local seen = collect(world, "water.drawn")
  plantThirsty(world, freeTiles(world, well, 1)[1])
  T.eq(Actors.order(world, hs, well).id, "fetch_water")
  run(world, 8)
  T.eq(hs.bucket, Water.bucketCapacity(world))
  T.eq(seen[1].source, "well")
  T.truthy(Journal.hasNote(world, "well_water"))
  hs.bucket = 0
  T.eq(Actors.order(world, hs, pump).id, "fetch_water")
  run(world, 8)
  T.eq(hs.bucket, Water.bucketCapacity(world))
  T.eq(seen[2].source, "hand_pump")
  T.truthy(reg:get("objects", "hand_pump").waterSource.fillTime < reg:get("objects", "well").waterSource.fillTime)
  T.truthy(reg:get("objects", "well").waterSource.fillTime <= tun.farming.fetchWaterTime * 1.5)
end)

T.test("well: with a well placed the routine still hauls and waters the crops", function()
  local world = newWorld(21)
  place(world, "hand_pump")
  world.control = "idle"
  local tiles = freeTiles(world, Land.spawn(world), 4)
  for _, i in ipairs(tiles) do
    Crops.setPlan(world, i, "radish")
  end
  local fetched, watered = 0, 0
  world.events:on("task.completed", function(e)
    if e.task == "fetch_water" then
      fetched = fetched + 1
    elseif e.task == "water_crop" then
      watered = watered + 1
    end
  end)
  run(world, tun.time.dayLength * 3)
  T.truthy(fetched > 0 and watered > 0, "hauled " .. fetched .. " times, watered " .. watered)
  T.eq(Water.stats(world).hand, watered)
end)

-- The solar pump and cistern ---------------------------------------------------------------------

T.test("pump: powered, it fills the cistern at its rate", function()
  local world, pump = pumpingWorld(3)
  local pumped = collect(world, "water.pumped")
  T.eq(Ledger.get(world, "water"), 0)
  run(world, HOUR * 2)
  local def = reg:get("objects", "dc_pump")
  T.eq(Water.pumpState(world, pump), "pumping")
  T.near(Ledger.get(world, "water"), def.pump.rate * 2, def.pump.rate * 0.3)
  T.eq(#pumped, 1, "announced once a day")
  T.truthy(Journal.hasNote(world, "tank_filled"))
  T.near(Water.stats(world).pumped, Ledger.get(world, "water"), 1e-6)
end)

T.test("pump: with no power it does nothing", function()
  local world = newWorld(3)
  clearPanels(world)
  place(world, "cistern")
  local pump = place(world, "dc_pump")
  setTime(world, SUMMER, 10)
  run(world, HOUR * 3)
  T.eq(Ledger.get(world, "water"), 0)
  T.eq(Water.pumpState(world, pump), "nopower")
  T.eq(Power.sinkRatio(world, pump), 0)
end)

T.test("pump: at night, with no battery, it waits for the sun", function()
  local world, pump = pumpingWorld(3)
  setTime(world, SUMMER, 23)
  run(world, HOUR * 2)
  T.eq(Ledger.get(world, "water"), 0)
  T.eq(Water.pumpState(world, pump), "nopower")
end)

T.test("pump: a poorly powered pump is throttled by its satisfaction", function()
  local full = pumpingWorld(3)
  run(full, HOUR * 2)
  local throttled
  with({ { reg:get("objects", "dc_pump").sink, "draw", 12 } }, function()
    throttled = pumpingWorld(3)
    run(throttled, HOUR * 2)
  end)
  local a, b = Ledger.get(full, "water"), Ledger.get(throttled, "water")
  T.truthy(b > 0 and b < a * 0.6, "throttled " .. b .. " vs full " .. a)
end)

T.test("pump: switched off in the power panel, or with nowhere to put water, it idles", function()
  local world, pump = pumpingWorld(3)
  Power.setEnabled(world, pump, false)
  run(world, HOUR)
  T.eq(Ledger.get(world, "water"), 0)
  T.eq(Water.pumpState(world, pump), "off")
  Power.setEnabled(world, pump, true)

  local bare = newWorld(3)
  clearPanels(bare)
  place(bare, "solar_array")
  local p2 = place(bare, "dc_pump")
  setTime(bare, SUMMER, 10)
  run(bare, HOUR)
  T.eq(Ledger.get(bare, "water"), 0)
  T.eq(Water.pumpState(bare, p2), "nocistern")
  T.eq(Power.sinkState(bare, p2), "idle", "no draw while there is no room")
end)

T.test("cistern: fills to capacity and no further, then the pump stops drawing power", function()
  local world, pump = pumpingWorld(3)
  local capacity = select(2, Water.stored(world))
  T.eq(capacity, reg:get("objects", "cistern").storage.water)
  Ledger.add(world, "water", capacity - 1)
  run(world, HOUR * 2)
  T.eq(Ledger.get(world, "water"), capacity)
  T.eq(Water.pumpState(world, pump), "full")
  T.eq(Power.sinkState(world, pump), "idle")
  T.near(Water.fraction(world), 1, 1e-9)
end)

T.test("cistern: a bucket drains it, and an empty cistern is not a place to fill", function()
  local world = newWorld(6)
  local hs = Actors.homesteader(world)
  local cistern = place(world, "cistern")
  Ledger.add(world, "water", 10)
  plantThirsty(world, freeTiles(world, cistern, 1)[1])
  T.eq(Actors.order(world, hs, cistern).id, "fetch_water")
  run(world, 6)
  T.eq(hs.bucket, Water.bucketCapacity(world))
  T.eq(Ledger.get(world, "water"), 10 - Water.bucketCapacity(world))
  -- Not enough for a full bucket: it gives what is left.
  hs.bucket = 0
  Ledger.remove(world, "water", Ledger.get(world, "water") - 2)
  Actors.order(world, hs, cistern)
  run(world, 6)
  T.eq(hs.bucket, 2)
  T.eq(Ledger.get(world, "water"), 0)
  -- Empty: the task no longer applies (the creek is the fallback).
  hs.bucket = 0
  local task = Actors.order(world, hs, cistern)
  T.truthy(task == nil or task.id ~= "fetch_water")
end)

T.test("cistern: the routine fetches from the nearest source, cistern included", function()
  local world = newWorld(8)
  local cistern = place(world, "cistern")
  Ledger.add(world, "water", 30)
  world.control = "idle"
  local tiles = freeTiles(world, cistern, 3)
  for _, i in ipairs(tiles) do
    plantThirsty(world, i)
  end
  local sources = {}
  world.events:on("water.drawn", function(e)
    sources[#sources + 1] = e.source
  end)
  run(world, tun.time.dayLength)
  T.truthy(#sources > 0 and sources[1] == "cistern", "hauled from the cistern")
end)

-- Drip irrigation --------------------------------------------------------------------------------

local function dripWorld(seed, stock)
  local world = newWorld(seed)
  local cistern = place(world, "cistern")
  Ledger.add(world, "water", stock)
  local drip = place(world, "drip_line", cistern)
  return world, drip
end

T.test("drip: waters thirsty crops in range without any actor, and not those out of range", function()
  local world, drip = dripWorld(9, 20)
  world.control = "active"
  local covered = {}
  for _, i in ipairs(Water.dripTiles(world, drip)) do
    covered[i] = true
  end
  local inside, outside
  for _, i in ipairs(freeTiles(world, drip, 80)) do
    if covered[i] then
      inside = inside or i
    elseif not outside and Grid.distance(world.state.grid, i, drip) > reg:get("objects", "drip_line").drip.radius + 1 then
      outside = i
    end
  end
  plantThirsty(world, inside)
  plantThirsty(world, outside)
  local seen = collect(world, "water.dripped")
  run(world, 0.5)
  T.truthy(world.state.crops[inside].moisture > 0.9)
  T.eq(world.state.crops[outside].moisture, 0)
  T.eq(#seen, 1)
  T.near(Ledger.get(world, "water"), 20 - COST, 1e-9)
  T.eq(Water.stats(world).drip, 1)
  T.eq(Water.stats(world).hand, 0)
  T.eq(Water.dripState(world, drip), "ok")
end)

T.test("drip: two overlapping lines water a crop once", function()
  local world, drip = dripWorld(9, 20)
  local second = place(world, "drip_line", drip)
  T.truthy(second ~= drip)
  local tile
  local mine = {}
  for _, i in ipairs(Water.dripTiles(world, drip)) do
    mine[i] = true
  end
  for _, i in ipairs(Water.dripTiles(world, second)) do
    if mine[i] and not world.occupancy[i] and Grid.terrain(world, i).tillable then
      tile = i
      break
    end
  end
  T.truthy(tile, "a tile both cover")
  plantThirsty(world, tile)
  run(world, 1)
  T.near(Ledger.get(world, "water"), 20 - COST, 1e-9, "one watering paid for once")
  T.eq(Water.stats(world).drip, 1)
end)

T.test("drip: a dry cistern leaves the zone dry, announces it once, and hand watering still works", function()
  local world, drip = dripWorld(9, 0)
  local hs = Actors.homesteader(world)
  local tile = freeTiles(world, drip, 1)[1]
  plantThirsty(world, tile)
  local dry, restored = collect(world, "water.dry"), collect(world, "water.restored")
  run(world, 2)
  T.eq(world.state.crops[tile].moisture, 0)
  T.eq(Water.dripState(world, drip), "dry")
  T.eq(Water.dripThirsty(world, drip), 1)
  T.eq(#dry, 1, "announced once, not every tick")
  -- The actor can still water it by hand.
  hs.bucket = 2
  Actors.order(world, hs, tile)
  run(world, 6)
  T.truthy(world.state.crops[tile].moisture > 0.9)
  T.eq(Water.stats(world).hand, 1)
  -- Water comes back: the next thirsty crop is dripped and the zone is announced restored.
  Ledger.add(world, "water", 5)
  local other = freeTiles(world, drip, 3)[3]
  plantThirsty(world, other)
  run(world, 0.5)
  T.truthy(world.state.crops[other].moisture > 0.9)
  T.eq(#restored, 1)
  T.eq(Water.dripState(world, drip), "ok")
end)

T.test("drip: the routine does not haul water for crops a stocked drip line covers", function()
  local world, drip = dripWorld(14, 40)
  world.control = "idle"
  for _, i in ipairs(freeTiles(world, drip, 4)) do
    Crops.setPlan(world, i, "radish")
  end
  local fetched = 0
  world.events:on("task.completed", function(e)
    if e.task == "fetch_water" then
      fetched = fetched + 1
    end
  end)
  run(world, tun.time.dayLength * 3)
  T.eq(fetched, 0, "no bucket trips")
  local crops = 0
  for _, crop in pairs(world.state.crops) do
    crops = crops + 1
    T.truthy(crop.growth > 0, "growing")
  end
  T.truthy(crops > 0, "planted")
  T.truthy(Water.stats(world).drip > 0)
  T.eq(Water.stats(world).hand, 0)
end)

T.test("drip: nothing is watered while the ground is frozen", function()
  local world, drip = dripWorld(9, 20)
  setTime(world, 22, 12)
  local tile = freeTiles(world, drip, 1)[1]
  plantThirsty(world, tile)
  run(world, 1)
  T.eq(Water.dripState(world, drip), "frozen")
  T.eq(Ledger.get(world, "water"), 20)
end)

-- Sprinklers (D118) -----------------------------------------------------------------------------

local SPRINKLER_COST = tun.water.sprinklerUnitsPerWatering

local function sprinklerWorld(seed, stock)
  local world = newWorld(seed)
  local cistern = place(world, "cistern")
  Ledger.add(world, "water", stock)
  local sprinkler = place(world, "sprinkler", cistern)
  return world, sprinkler
end

T.test("sprinkler: content, gate and cost (a full bucket slot, twice the drip line)", function()
  local def, item = reg:get("objects", "sprinkler"), reg:get("catalog", "sprinkler")
  T.eq(def.sprinkler.radius, reg:get("objects", "drip_line").drip.radius, "same 5x5 patch")
  T.eq(SPRINKLER_COST, 1)
  T.eq(SPRINKLER_COST, 2 * COST)
  T.eq(#item.needs, 1)
  T.eq(item.needs[1], "well_water")
  T.eq(item.page, "water_soil")
  T.eq(item.studyNights, 1)
  T.falsy(item.unique, "repeatable (D114)")
  T.falsy(def.replaces, "no upgrade chain with the drip line")
  T.eq(reg:get("catalog", "drip_line").needs[1], "tank_filled", "the drip line keeps its own gate")
  T.eq(Water.irrigationKind(def), "sprinkler")
  T.eq(Water.irrigationKind(reg:get("objects", "drip_line")), "drip")
  T.eq(Water.irrigationKind(reg:get("objects", "cistern")), nil)
end)

T.test("sprinkler: spends a full unit per crop, counted apart from drip lines", function()
  local world, sprinkler = sprinklerWorld(9, 20)
  local tile = freeTiles(world, sprinkler, 1)[1]
  plantThirsty(world, tile)
  local seen = collect(world, "water.dripped")
  run(world, 0.5)
  T.truthy(world.state.crops[tile].moisture > 0.9)
  T.near(Ledger.get(world, "water"), 20 - SPRINKLER_COST, 1e-9)
  T.eq(Water.stats(world).sprinkler, 1)
  T.eq(Water.stats(world).drip, 0)
  T.eq(#seen, 1)
  T.eq(seen[1].kind, "sprinkler")
  T.eq(Water.unitsPerWatering(world, sprinkler), 1)
  T.eq(Water.dripState(world, sprinkler), "ok")
end)

T.test("sprinkler: only reaches its 5x5 patch", function()
  local world, sprinkler = sprinklerWorld(9, 20)
  T.eq(#Water.dripTiles(world, sprinkler) <= 25, true)
  local outside
  for _, i in ipairs(freeTiles(world, sprinkler, 80)) do
    if not outside and Grid.distance(world.state.grid, i, sprinkler) > 3 then
      outside = i
    end
  end
  plantThirsty(world, outside)
  run(world, 0.5)
  T.eq(world.state.crops[outside].moisture, 0)
  T.eq(Water.stats(world).sprinkler, 0)
end)

-- A tile both `a` and `b` cover that can hold a crop.
local function sharedTile(world, a, b)
  local mine = {}
  for _, i in ipairs(Water.dripTiles(world, a)) do
    mine[i] = true
  end
  for _, i in ipairs(Water.dripTiles(world, b)) do
    if mine[i] and not world.occupancy[i] and Grid.terrain(world, i).tillable then
      return i
    end
  end
end

T.test("sprinkler: overlapping sprinklers, or a sprinkler and a drip line, water a crop once", function()
  for _, other in ipairs({ "sprinkler", "drip_line" }) do
    local world, sprinkler = sprinklerWorld(9, 20)
    local second = place(world, other, sprinkler)
    local tile = sharedTile(world, sprinkler, second)
    T.truthy(tile, "a tile both cover")
    plantThirsty(world, tile)
    run(world, 1)
    local firstAnchor = math.min(sprinkler, second)
    local paid = Water.unitsPerWatering(world, firstAnchor)
    T.near(20 - Ledger.get(world, "water"), paid, 1e-9, "paid once, by the first anchor (" .. other .. ")")
    local s = Water.stats(world)
    T.eq(s.sprinkler + s.drip, 1)
  end
end)

T.test("sprinkler: a stock under one unit is dry for it, but not for a drip line", function()
  local world, sprinkler = sprinklerWorld(9, 0.7)
  local drip = place(world, "drip_line", sprinkler)
  T.eq(Water.dripState(world, sprinkler), "dry", "0.7 is under a full unit")
  T.eq(Water.dripState(world, drip), "ok", "but over the drip line's half unit")
  local tile = freeTiles(world, sprinkler, 1)[1]
  plantThirsty(world, tile)
  local dry, restored = collect(world, "water.dry"), collect(world, "water.restored")
  -- Only the sprinkler covers this crop? Both do (they stand together), so the drip line, which comes later
  -- or earlier by anchor, may water it. Move the drip line out of the picture to test the sprinkler alone.
  Grid.removeObject(world, drip)
  run(world, 2)
  T.eq(world.state.crops[tile].moisture, 0)
  T.eq(Water.dripThirsty(world, sprinkler), 1)
  T.eq(#dry, 1, "announced once")
  T.eq(dry[1].kind, "sprinkler")
  T.near(Ledger.get(world, "water"), 0.7, 1e-9, "nothing spent")
  Ledger.add(world, "water", 5)
  run(world, 0.5)
  T.truthy(world.state.crops[tile].moisture > 0.9)
  local other = freeTiles(world, sprinkler, 3)[3]
  plantThirsty(world, other)
  run(world, 0.5)
  T.eq(#restored, 1)
  T.eq(restored[1].kind, "sprinkler")
  T.eq(Water.dripState(world, sprinkler), "ok")
end)

T.test("sprinkler: nothing is sprayed while the ground is frozen", function()
  local world, sprinkler = sprinklerWorld(9, 20)
  setTime(world, 22, 12)
  plantThirsty(world, freeTiles(world, sprinkler, 1)[1])
  run(world, 1)
  T.eq(Water.dripState(world, sprinkler), "frozen")
  T.eq(Ledger.get(world, "water"), 20)
end)

T.test("sprinkler: can be picked up and put back (D98)", function()
  local Placement = require("src.sim.systems.placement")
  local world, sprinkler = sprinklerWorld(9, 20)
  T.truthy(Placement.pickUp(world, sprinkler))
  T.falsy(Grid.object(world, sprinkler))
  T.eq(Inventory.objectCount(world, "sprinkler"), 1)
  T.truthy(Inventory.canPlace(world, "sprinkler", sprinkler))
  T.truthy(Inventory.place(world, "sprinkler", sprinkler))
  T.eq(Water.irrigationKind(Grid.object(world, sprinkler)), "sprinkler")
end)

-- Whole ladder -----------------------------------------------------------------------------------

-- A world with the whole ladder built a few tiles from the start (so the homesteader is not boxed
-- in) and a planned field under the drip line, the routine in charge, at dawn in summer.
local function ladderWorld(seed)
  local world = newWorld(seed)
  clearPanels(world)
  local sx, sy = Grid.coords(world.state.grid, Land.spawn(world))
  local site = Grid.index(world.state.grid, math.min(world.state.grid.w - 2, sx + 7), sy)
  place(world, "solar_array", site)
  local cistern = place(world, "cistern", site)
  place(world, "dc_pump", site)
  local drip = place(world, "drip_line", cistern)
  setTime(world, SUMMER, 6)
  world.control = "idle"
  world.state.threats.years[1] = {} -- no drought or hail in the way (threats are tested in test_threats.lua)
  for _, i in ipairs(freeTiles(world, drip, 5)) do
    Crops.setPlan(world, i, "radish")
  end
  return world
end

T.test("ladder: pump, cistern and drip keep a field watered through days with no hauling", function()
  local world = ladderWorld(5)
  local fetched = 0
  world.events:on("task.completed", function(e)
    if e.task == "fetch_water" then
      fetched = fetched + 1
    end
  end)
  run(world, tun.time.dayLength * 4)
  T.eq(fetched, 0)
  T.truthy(Water.stats(world).drip > 0)
  T.truthy(Water.stats(world).pumped > 0)
end)

-- Determinism and saves ---------------------------------------------------------------------------

T.test("water: the same seed gives the same run", function()
  local a, b = ladderWorld(17), ladderWorld(17)
  run(a, tun.time.dayLength * 2)
  run(b, tun.time.dayLength * 2)
  T.eq(serialize.encode(a.state.water), serialize.encode(b.state.water))
  T.eq(serialize.encode(a.state.ledger), serialize.encode(b.state.ledger))
  T.eq(serialize.encode(a.state.crops), serialize.encode(b.state.crops))
end)

T.test("water: save and load mid-run carries on identically", function()
  local a = ladderWorld(17)
  run(a, tun.time.dayLength * 1.2)
  local b = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  b.control = a.control -- who is in charge is session state, not saved
  T.eq(serialize.encode(b.state.water), serialize.encode(a.state.water))
  T.eq(Water.fraction(b), Water.fraction(a))
  run(a, tun.time.dayLength)
  run(b, tun.time.dayLength)
  T.eq(serialize.encode(a.state.water), serialize.encode(b.state.water))
  T.eq(serialize.encode(a.state.ledger), serialize.encode(b.state.ledger))
  T.eq(serialize.encode(a.state.grid.waterTable), serialize.encode(b.state.grid.waterTable))
end)

T.test("water: a save from before the water ladder still loads and gets the same water table", function()
  local a = newWorld(23)
  local original = serialize.encode(a.state.grid.waterTable)
  local state = serialize.decode(serialize.encode(a.state))
  state.water = nil
  state.grid.waterTable = nil
  state.rng.watertable = nil -- an old save never used that stream
  local b = World.new({ registry = reg, tuning = tun }, state)
  T.eq(serialize.encode(b.state.grid.waterTable), original)
  T.eq(Water.stats(b).hand, 0)
  T.eq(Water.stats(b).drip, 0)
  place(b, "well")
  run(b, 1)
end)

T.test("water: a half-filled save from the first version of the state loads", function()
  local a = newWorld(23)
  local state = serialize.decode(serialize.encode(a.state))
  state.water = { hand = 3 } -- an older shape with fewer fields
  local b = World.new({ registry = reg, tuning = tun }, state)
  T.eq(Water.stats(b).hand, 3)
  T.eq(Water.stats(b).drip, 0)
  place(b, "cistern")
  run(b, 1)
end)
