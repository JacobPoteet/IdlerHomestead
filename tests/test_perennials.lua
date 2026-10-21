-- Perennials (PLAN_DEPTH 8.5, D183, issue #369): berries and an apple tree are planted once, give a small first crop in
-- their fruiting season after the one they were planted in and a full crop after one winter, want pruning and (young)
-- wrapping, and are drawn to deer and bears while young. Tested across year boundaries through the real clock.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Gridpack = require("src.core.gridpack")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Quality = require("src.sim.systems.quality")
local Save = require("src.core.save")
local Soil = require("src.sim.systems.soil")
local Tasks = require("src.sim.systems.tasks")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.perennials
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SPRING, SUMMER, AUTUMN, WINTER = 1, 2, 3, 4

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active"
  return world
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- Jump the clock into the next season (or the named one) so its date events fire, then back to its first morning, so
--- a fruit has the whole season to ripen in.
local function toSeason(world, seasonIndex, hour)
  Calendar.skipTo(world, hour or 9, seasonIndex)
  world:tick(STEP)
  world:tick(STEP)
  local now = Calendar.now(world)
  setTime(world, now.day - now.dayOfSeason + 1, 7)
end

local function freeTile(world, skip)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 12 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and i ~= skip
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and not Crops.tileInUse(world, i)
          and i ~= world.state.land.spawn
        then
          return i
        end
      end
    end
  end
end

--- Plant `cropId` on a fresh tilled tile through the real plant task (a seed is spent).
local function plant(world, cropId, skip)
  local i = freeTile(world, skip)
  local def = reg:get("crops", cropId)
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = cropId
  Ledger.add(world, def.seed, 1, "test")
  Tasks.get(world, "plant").complete(world, Actors.homesteader(world), i, nil)
  T.truthy(world.state.crops[i], "planted")
  return i
end

--- Keep the crop watered while the sim runs `days` days.
local function growFor(world, i, days)
  for _ = 1, days * 4 do
    if world.state.crops[i] then
      world.state.crops[i].moisture = 1
    end
    run(world, tun.time.dayLength / 4)
  end
end

local function harvest(world, i)
  local seen
  local off = world.events:on("crop.harvested", function(e)
    seen = e
  end)
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
  off()
  return seen
end

local function noteList(world, cropId)
  return world.registry:get("catalog", cropId .. "_seeds")
end

-- The data ---------------------------------------------------------------------------------------------------------

T.test("perennials: berries and an apple tree are data, planted from dear seed and never returned", function()
  local seasons = tun.time.seasons
  local priciest = 0
  for _, c in ipairs(reg:all("catalog")) do
    if c.page == "seeds" and c.id ~= "berries_seeds" and c.id ~= "apple_seeds" then
      priciest = math.max(priciest, c.price)
    end
  end
  for _, id in ipairs({ "berries", "apple" }) do
    local def = reg:get("crops", id)
    T.truthy(def.perennial, id .. " is a perennial")
    T.truthy(
      seasons[1] == def.perennial.fruitSeason
        or seasons[2] == def.perennial.fruitSeason
        or seasons[3] == def.perennial.fruitSeason,
      id .. " fruits in a thawed season"
    )
    T.truthy(#def.perennial.vulnerable > 0, id .. " names what draws on it while young")
    T.eq(def.frost, "hardy", id .. " sits the winter out")
    T.eq(def.seedReturn[2], 0)
    T.falsy(
      Crops.inWindow(newWorld(), def, "autumn"),
      id .. " is never planted in autumn: its first crop would skip a season"
    )
    T.truthy(noteList(newWorld(), id).price > priciest * 3, id .. " costs far more to start than any seed")
  end
  T.truthy(reg:get("crops", "apple").perennial.fruitSeason ~= reg:get("crops", "berries").perennial.fruitSeason)
  T.truthy(reg:get("resources", "apple").keepsForWinter, "apples keep")
  T.truthy(
    reg:get("crops", "apple").yield > reg:get("crops", "berries").yield,
    "the tree pays more a year than the canes"
  )
end)

-- Stages across the seasons ------------------------------------------------------------------------------------------

T.test(
  "perennials: planted in spring, berries bear a small crop that summer and a full one after the winter",
  function()
    local world = newWorld()
    setTime(world, 2) -- spring, year 1
    local i = plant(world, "berries")
    local crop = world.state.crops[i]
    T.eq(crop.stage, "sapling")
    T.truthy(crop.rest, "a sapling has nothing to ripen")
    T.falsy(Crops.needsWaterAt(world, i), "and needs no water")
    T.truthy(Crops.isYoung(crop))
    run(world, 600)
    T.eq(crop.growth, 0, "it does not grow in the season it was planted in")

    toSeason(world, SUMMER)
    T.eq(crop.stage, "first")
    T.falsy(crop.rest, "its fruiting season has begun")
    crop.moisture = 0
    T.truthy(Crops.needsWaterAt(world, i), "now it is thirsty")
    growFor(world, i, 5)
    T.truthy(Crops.isRipeAt(world, i), "ripe within the season")
    T.near(Crops.yieldShare(world, crop), cfg.firstYieldShare, 1e-9, "a young plant gives the first-year share")
    local first = harvest(world, i)
    T.eq(first.stage, "first")
    T.truthy(
      first.amount <= math.ceil(reg:get("crops", "berries").yield * tun.farming.soilYieldMax * cfg.firstYieldShare) + 1
    )
    T.truthy(world.state.crops[i], "the plant stays after the harvest")
    T.truthy(crop.rest and crop.fruited and crop.pruneDue, "resting, picked and wanting pruning")
    T.eq(crop.growth, 0)
    growFor(world, i, 3)
    T.falsy(Crops.isRipeAt(world, i), "one crop a year: it does not ripen again this summer")

    toSeason(world, AUTUMN)
    T.eq(crop.stage, "first", "still young: no winter yet")
    crop.wrapped = true -- the player wrapped it before the freeze
    toSeason(world, WINTER)
    T.truthy(world.state.crops[i] == crop, "it came through the winter")
    toSeason(world, SPRING) -- year 2
    T.falsy(crop.wrapped, "unwrapped with the thaw")
    T.eq(crop.stage, "mature", "through one winter")
    T.eq(crop.winters, 1)
    T.eq(Calendar.now(world).year, 2)
    toSeason(world, SUMMER)
    T.falsy(crop.rest)
    T.near(
      Crops.yieldShare(world, crop),
      1 - cfg.unprunedCut,
      1e-9,
      "never pruned after the first picking: the crop is cut"
    )
    crop.pruneDue = nil -- pruned in time
    crop.unpruned = nil
    growFor(world, i, 5)
    T.truthy(Crops.isRipeAt(world, i))
    T.eq(Crops.yieldShare(world, crop), 1)
    local full = harvest(world, i)
    T.eq(full.stage, "mature")
  end
)

T.test(
  "perennials: an apple tree planted in summer fruits that autumn, small, and the first fruit year is the year after planting",
  function()
    local world = newWorld()
    toSeason(world, SUMMER)
    local i = plant(world, "apple")
    local crop = world.state.crops[i]
    growFor(world, i, 3)
    T.eq(crop.growth, 0, "nothing in the planting season")
    toSeason(world, AUTUMN)
    T.eq(crop.stage, "first")
    growFor(world, i, 6)
    T.truthy(Crops.isRipeAt(world, i))
    T.near(Crops.yieldShare(world, crop), cfg.firstYieldShare, 1e-9)
    harvest(world, i)
  end
)

T.test("perennials: three years on, the same plant has borne three crops", function()
  local world = newWorld()
  setTime(world, 2)
  local i = plant(world, "berries")
  local crop = world.state.crops[i]
  local crops, spoiled = {}, 0
  world.events:on("crop.harvested", function(e)
    crops[#crops + 1] = e
  end)
  world.events:on("crop.lost", function() -- a summer threat (hail, locusts) may strip a year's fruit: the plant stays
    spoiled = spoiled + 1
  end)
  for _ = 1, 3 do
    toSeason(world, SUMMER)
    growFor(world, i, 5)
    if crop.pruneDue then
      Tasks.get(world, "prune").complete(world, Actors.homesteader(world), i)
    end
    if Crops.isRipeAt(world, i) then
      Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
    end
    toSeason(world, AUTUMN)
    if Crops.isYoung(crop) then
      crop.wrapped = true
    end
    toSeason(world, WINTER)
    toSeason(world, SPRING)
  end
  T.eq(Calendar.now(world).year, 4)
  T.eq(#crops + spoiled, 3, "a crop each of the three summers, less any a threat took")
  T.truthy(#crops >= 2, "at least two were picked")
  T.eq(crops[1].stage, "first")
  T.eq(crops[2].stage, "mature")
  T.truthy(world.state.crops[i], "and it is still there")
end)

-- Upkeep: pruning and wrapping --------------------------------------------------------------------------------------

T.test("perennials: pruning is Upkeep, the routine's, and clears the plant for a full crop", function()
  local world = newWorld()
  setTime(world, 2)
  local i = plant(world, "berries")
  local crop = world.state.crops[i]
  local prune, hs = Tasks.get(world, "prune"), Actors.homesteader(world)
  T.eq(prune.category, "maintenance")
  T.falsy(prune.canDo(world, hs, i, {}), "nothing to prune before the first picking")
  crop.pruneDue = true
  local offered = {}
  prune.candidates(world, hs, function(t)
    offered[#offered + 1] = t
  end)
  T.same(offered, { i })
  T.truthy(prune.canDo(world, hs, i, nil), "the routine prunes")
  local seen
  world.events:on("crop.pruned", function(e)
    seen = e
  end)
  prune.complete(world, hs, i)
  T.falsy(crop.pruneDue)
  T.eq(seen.tile, i)
  T.falsy(prune.canDo(world, hs, i, {}), "pruned")
  -- the next fruiting season starts: pruned in time means no cut, left unpruned means the cut
  crop.winters, crop.seasons, crop.stage = 1, 4, "mature"
  toSeason(world, SUMMER)
  T.falsy(crop.unpruned)
  T.eq(Crops.yieldShare(world, crop), 1)
  crop.pruneDue, crop.fruited = true, true
  toSeason(world, AUTUMN)
  toSeason(world, WINTER)
  toSeason(world, SPRING)
  toSeason(world, SUMMER)
  T.truthy(crop.unpruned, "it went into the season unpruned")
end)

T.test("perennials: the idle routine prunes a picked plant on its own", function()
  local world = newWorld()
  world.control = "idle"
  setTime(world, 12, 8)
  local i = plant(world, "berries")
  world.state.crops[i].pruneDue = true
  run(world, 120)
  T.falsy(world.state.crops[i].pruneDue, "pruned by the routine")
end)

T.test("perennials: a young plant is wrapped from wrapLead days before the freeze, by the routine or a tap", function()
  local world = newWorld()
  setTime(world, 2)
  local i = plant(world, "berries")
  local crop = world.state.crops[i]
  local wrap, hs = Tasks.get(world, "wrap"), Actors.homesteader(world)
  T.eq(wrap.category, "maintenance")
  local function offered()
    local list = {}
    wrap.candidates(world, hs, function(t)
      list[#list + 1] = t
    end)
    return #list
  end
  T.eq(offered(), 0, "far from the freeze the routine leaves it")
  T.truthy(wrap.canDo(world, hs, i, {}), "a tap wraps it any time before the freeze")
  T.falsy(wrap.canDo(world, hs, i, nil))
  setTime(world, AUTUMN * 0 + 2 * DPS + (DPS - cfg.wrapLead + 1), 9) -- wrapLead days from the last autumn day
  T.truthy(Calendar.now(world).season == "autumn")
  T.eq(offered(), 1, "in the lead the routine goes to it")
  local wrapped
  world.events:on("crop.wrapped", function(e)
    wrapped = e
  end)
  wrap.complete(world, hs, i)
  T.truthy(crop.wrapped)
  T.eq(wrapped.tile, i)
  T.eq(offered(), 0, "once")
  crop.wrapped = nil
  crop.stage, crop.winters = "mature", 1
  T.eq(offered(), 0, "an established plant needs no wrapping")
  T.falsy(wrap.canDo(world, hs, i, {}))
end)

T.test("perennials: at the freeze an unwrapped young plant may die, a wrapped one and an old one never do", function()
  local function winter(seed, wrapped, stage)
    local world = newWorld(seed)
    world.tuning.perennials.youngFrostKill = 1 -- certain, so the test reads the rule not the dice
    setTime(world, 2)
    local i = plant(world, "berries")
    local crop = world.state.crops[i]
    crop.stage, crop.winters = stage, stage == "mature" and 1 or 0
    crop.wrapped = wrapped or nil
    toSeason(world, SUMMER)
    toSeason(world, AUTUMN)
    toSeason(world, WINTER)
    tun.perennials.youngFrostKill = cfg.youngFrostKill
    return world.state.crops[i] ~= nil
  end
  local original = cfg.youngFrostKill
  T.falsy(winter(4, false, "first"), "unwrapped and young: dead at a certain freeze")
  T.truthy(winter(4, true, "first"), "wrapped: safe")
  T.truthy(winter(4, false, "mature"), "established: safe")
  tun.perennials.youngFrostKill = original
end)

T.test("perennials: the freeze roll uses its own stream, drawn whatever the wrapping", function()
  local function run1(wrapped)
    local world = newWorld(8)
    setTime(world, 2)
    local tiles = {}
    for n = 1, 4 do
      tiles[n] = plant(world, "berries", tiles[n - 1])
      world.state.crops[tiles[n]].wrapped = wrapped or nil
    end
    local before = serialize.encode(world.state.rng.orchard or {})
    Crops.frost(world)
    return serialize.encode(world.state.rng.orchard), before
  end
  local a, none = run1(true)
  local b = run1(false)
  T.eq(a, b, "wrapped or not, the same draws")
  T.truthy(a ~= none, "the stream moved")
  T.truthy(newWorld(8).state.rng.orchard == nil, "and it is its own: nothing else made it")
end)

T.test("perennials: frost cloth turns part of the freeze aside, as it does for tender crops", function()
  local world = newWorld(4)
  world.tuning.perennials.youngFrostKill = 1
  setTime(world, 2)
  local Inventory = require("src.sim.systems.inventory")
  Inventory.addEquipment(world, "frost_cloth")
  local survived = 0
  local n = 12
  local tiles = {}
  for k = 1, n do
    tiles[k] = plant(world, "berries", tiles[k - 1])
  end
  Crops.frost(world)
  for _, i in ipairs(tiles) do
    survived = survived + (world.state.crops[i] and 1 or 0)
  end
  T.truthy(survived > 0 and survived < n, "some of a dozen are saved by the cloth, not all")
  tun.perennials.youngFrostKill = cfg.youngFrostKill
end)

-- The animals ------------------------------------------------------------------------------------------------------------

T.test(
  "perennials: a young plant is drawn to what its definition names, an old one is not (a hook for phase C)",
  function()
    local world = newWorld()
    setTime(world, 2)
    local tree = plant(world, "apple")
    local canes = plant(world, "berries", tree)
    T.truthy(Crops.vulnerableTo(world, tree, "bear"))
    T.truthy(Crops.vulnerableTo(world, tree, "deer"))
    T.truthy(Crops.vulnerableTo(world, canes, "deer"))
    T.falsy(Crops.vulnerableTo(world, canes, "bear"), "berries do not draw a bear here")
    T.falsy(Crops.vulnerableTo(world, tree, "fox"))
    world.state.crops[tree].stage = "mature"
    T.falsy(Crops.vulnerableTo(world, tree, "bear"), "through a winter it is safe")
    T.falsy(Crops.vulnerableTo(world, canes + 5000, "deer"), "no plant, no draw")
  end
)

-- Losses and the rest ------------------------------------------------------------------------------------------------------

T.test("perennials: a threat strips an established plant's fruit but a young plant is lost", function()
  local world = newWorld()
  setTime(world, 2)
  local a = plant(world, "apple")
  local b = plant(world, "apple", a)
  world.state.crops[b].stage, world.state.crops[b].winters = "mature", 1
  world.state.crops[b].growth = 0.7
  local lost = {}
  world.events:on("crop.lost", function(e)
    lost[#lost + 1] = e.tile
  end)
  T.truthy(Crops.destroy(world, a, "hail"))
  T.truthy(Crops.destroy(world, b, "hail"))
  T.falsy(world.state.crops[a], "the sapling is gone")
  T.truthy(world.state.crops[b], "the tree stands")
  T.eq(world.state.crops[b].growth, 0, "without its fruit")
  T.eq(#lost, 2)
end)

T.test(
  "perennials: a harvest draws fertility but never builds pest pressure, and the family is not remembered",
  function()
    local world = newWorld()
    setTime(world, 2)
    local i = plant(world, "berries")
    local crop = world.state.crops[i]
    world.state.grid.fertility[i] = 0.9
    for _ = 1, 3 do
      crop.growth, crop.rest, crop.fruited = 1, false, nil
      harvest(world, i)
    end
    T.eq(Soil.pressure(world, i), 0)
    T.eq(Soil.lastFamily(world, i), nil)
    T.truthy(Soil.fertility(world, i) < 0.9, "it still draws")
  end
)

T.test("perennials: an unripe crop is lost when its season ends, and the plant waits for next year", function()
  local world = newWorld()
  setTime(world, 2)
  local i = plant(world, "berries")
  local crop = world.state.crops[i]
  toSeason(world, SUMMER)
  crop.moisture = 1
  run(world, 600)
  T.truthy(crop.growth > 0 and crop.growth < 1, "part ripe")
  toSeason(world, AUTUMN)
  T.eq(crop.growth, 0)
  T.truthy(crop.rest)
  T.falsy(Crops.needsWaterAt(world, i))
end)

T.test("perennials: the idle routine plants, waters, prunes and harvests them, planned like any crop", function()
  local world = newWorld(6)
  world.control = "idle"
  setTime(world, 3, 7)
  local i = freeTile(world)
  world.state.fields.plan[i] = "berries"
  world.state.fields.tilled[i] = true
  Ledger.add(world, "seed_berries", 1, "test")
  run(world, 240)
  T.truthy(world.state.crops[i], "the routine planted the berries")
  T.eq(Ledger.get(world, "seed_berries"), 0)
end)

-- Quality and prices ----------------------------------------------------------------------------------------------------------

T.test("perennials: fruit is graded like any harvest and sells for its price", function()
  local world = newWorld()
  setTime(world, 2)
  local i = plant(world, "apple")
  local crop = world.state.crops[i]
  world.state.grid.fertility[i] = 1
  crop.stage, crop.winters, crop.growth, crop.rest, crop.tends = "mature", 1, 1, false, 1
  local e = harvest(world, i)
  T.eq(e.quality, "excellent")
  T.eq(Quality.counts(world, "apple").excellent, e.amount)
  T.truthy(Market.tierPrice(world, "apple", "excellent") > Market.sellPrice(world, "apple"))
end)

-- Save --------------------------------------------------------------------------------------------------------------------------

T.test("perennials: their stage and flags survive a save and the plant carries on", function()
  local world = newWorld()
  setTime(world, 2)
  local i = plant(world, "apple")
  toSeason(world, SUMMER)
  local crop = world.state.crops[i]
  crop.wrapped, crop.pruneDue, crop.unpruned = true, true, true
  local data = Save.newSlotData("Orchard")
  data.run = world.state
  local disk = serialize.decode(serialize.encode(Save.forDisk(data)))
  Gridpack.unpack(disk.run.grid)
  local back = World.new({ registry = reg, tuning = tun }, disk.run)
  local c = back.state.crops[i]
  T.eq(c.stage, "first")
  T.eq(c.seasons, 1)
  T.eq(c.winters, 0)
  T.truthy(c.wrapped and c.pruneDue and c.unpruned)
  T.truthy(c.rest, "an apple is resting in summer")
  toSeason(back, AUTUMN)
  T.falsy(back.state.crops[i].rest, "and ripens in autumn after the load")
end)
