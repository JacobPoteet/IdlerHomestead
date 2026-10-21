-- Compost and the manure loop (PLAN_DEPTH 8.4, D181, D185, issue #367): hens and goats make muck, the Tend chores rake
-- it into the ledger as manure, a bin draws it from the ledger on its own (no haul task), residue and spoiled food feed
-- the bin too, the bin makes compost on a timer, and the Fertilize task spreads it on the worst worn tile.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Animals = require("src.sim.systems.animals")
local Compost = require("src.sim.systems.compost")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Gridpack = require("src.core.gridpack")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Placement = require("src.sim.systems.placement")
local Save = require("src.core.save")
local Soil = require("src.sim.systems.soil")
local Spoilage = require("src.sim.systems.spoilage")
local Tasks = require("src.sim.systems.tasks")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.compost
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SUMMER = DPS + 1

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function newDay(world)
  world.events:emit("calendar.newDay", { day = 1, season = "summer", year = 1 })
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

--- The free tile for `id` nearest the truck.
local function spotFor(world, id, skip)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, require("src.sim.systems.land").spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and i ~= skip and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  return best
end

local function place(world, id, skip)
  local spot = spotFor(world, id, skip)
  T.truthy(spot, "a spot for " .. id)
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, spot))
  return spot
end

--- A world with a bin placed (summer, clear). Returns world, bin anchor.
local function binWorld(seed)
  local world = newWorld(seed)
  setTime(world, SUMMER + 3)
  return world, place(world, "compost_bin")
end

--- A free tilled tile near the spawn, other than the given ones.
local function fieldTile(world, ...)
  local avoid = {}
  for _, i in ipairs({ ... }) do
    avoid[i] = true
  end
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 12 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and not avoid[i]
          and i ~= world.state.land.spawn
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and not Crops.tileInUse(world, i)
        then
          world.state.fields.tilled[i] = true
          return i
        end
      end
    end
  end
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

local function hoursToSeconds(hours)
  return hours * tun.time.dayLength / 24
end

-- Content ---------------------------------------------------------------------------------------------

T.test("compost content: bin, resources, catalog item and art line up", function()
  local sprites = require("assets.manifest").sprites
  local bin = reg:get("objects", "compost_bin")
  T.truthy(bin.placeable and bin.compost and bin.compost.raw > 0)
  for _, id in ipairs({ "manure", "compost" }) do
    local res = reg:get("resources", id)
    T.eq(res.category, "supply")
    T.truthy(res.capacity and res.capacity > 0)
    T.truthy(sprites["icon_" .. id], id .. " has an icon")
  end
  T.truthy(sprites.compost_bin and sprites.icon_compost_bin)
  local item = reg:get("catalog", "compost_bin")
  T.eq(item.object, "compost_bin")
  T.same(item.needs, { "produce_spoils" }, "learned from the first rotten vegetable")
  T.falsy(item.unique, "more than one bin is fine")
  T.truthy(Tasks and reg:get("task_categories", "maintenance"))
end)

-- Muck and raking --------------------------------------------------------------------------------------

T.test("compost: animals make muck by the day, capped, and a house with none makes none", function()
  local world = newWorld()
  newDay(world)
  T.eq(Compost.muck(world, "hens"), 0)
  T.eq(Compost.muck(world, "goats"), 0)
  Ledger.add(world, "hen", 0) -- the stores exist
  world.state.ledger.capacity.hen = 10
  world.state.ledger.capacity.goat = 10
  Ledger.add(world, "hen", 5, "test")
  Ledger.add(world, "goat", 2, "test")
  newDay(world)
  T.near(Compost.muck(world, "hens"), 5 * cfg.henMuck, 1e-9)
  T.near(Compost.muck(world, "goats"), 2 * cfg.goatMuck, 1e-9)
  for _ = 1, 30 do
    newDay(world)
  end
  T.eq(Compost.muck(world, "hens"), cfg.muckCap, "capped")
  T.eq(Compost.muck(world, "goats"), cfg.muckCap, "capped")
end)

T.test("compost: the Tend chores rake whole units into the ledger, only while a bin exists", function()
  local world = newWorld()
  place(world, "chicken_coop")
  Ledger.add(world, "hen", 6, "test")
  setTime(world, SUMMER + 3)
  for _ = 1, 3 do
    newDay(world)
  end
  local muck = Compost.muck(world, "hens")
  T.near(muck, 3 * 6 * cfg.henMuck, 1e-9)
  Animals.tend(world)
  T.eq(Ledger.get(world, "manure"), 0, "no bin, no raking")
  T.near(Compost.muck(world, "hens"), muck, 1e-9, "the muck waits")
  place(world, "compost_bin")
  local tended = collect(world, "animals.tended")
  Animals.tend(world)
  T.eq(Ledger.get(world, "manure"), math.floor(muck), "whole units only")
  T.near(Compost.muck(world, "hens"), muck - math.floor(muck), 1e-9, "the fraction stays in the house")
  T.eq(tended[1].manure, math.floor(muck))
end)

T.test("compost: raking stops at the ledger's room for manure", function()
  local world, _ = binWorld()
  place(world, "chicken_coop")
  world.state.compost.muck.hens = cfg.muckCap
  Ledger.add(world, "manure", reg:get("resources", "manure").capacity - 2, "test")
  T.eq(Compost.rake(world, "hens"), 2)
  T.eq(Ledger.room(world, "manure"), 0)
  T.eq(Compost.rake(world, "hens"), 0, "full: nothing more is raked")
end)

-- Drawing manure ----------------------------------------------------------------------------------------

T.test("compost: there is no haul task, and a bin draws the ledger's manure on its own", function()
  local world, bin = binWorld()
  T.errors(function()
    Tasks.get(world, "haul_manure")
  end)
  T.errors(function()
    return cfg.haulAt
  end)
  Ledger.add(world, "manure", 5, "test")
  local fed = collect(world, "compost.fed")
  run(world, STEP * 2)
  T.eq(Ledger.get(world, "manure"), 0)
  T.truthy(Compost.batch(world, bin), "five raw units start a batch")
  T.eq(fed[1].cause, "manure")
  T.eq(fed[1].amount, 5)
end)

T.test("compost: a bin draws manure only as far as its room, and with no bin the manure stays", function()
  local world, bin = binWorld()
  local cap = reg:get("objects", "compost_bin").compost.raw
  Ledger.add(world, "manure", 20, "test")
  world.state.compost.bins[bin] = { raw = cap - 3, batch = { count = 1, remaining = 1e9 } } -- busy, so it takes no batch
  run(world, STEP)
  T.eq(Compost.raw(world, bin), cap, "never more than the bin has room for")
  T.eq(Ledger.get(world, "manure"), 17, "the rest waits in the ledger")
  local bare = newWorld()
  Ledger.add(bare, "manure", 4, "test")
  run(bare, STEP * 3)
  T.eq(Ledger.get(bare, "manure"), 4)
end)

-- Feeding the bin --------------------------------------------------------------------------------------

T.test("compost: a harvest adds its residue to a bin, and with no bin nothing happens", function()
  local world, bin = binWorld()
  local i = fieldTile(world)
  world.state.crops[i] = { id = "radish", growth = 1, moisture = 1 }
  Ledger.add(world, "radish", 0)
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
  T.eq(Compost.raw(world, bin), cfg.residuePerHarvest)
  local bare = newWorld()
  local j = fieldTile(bare)
  bare.state.crops[j] = { id = "radish", growth = 1, moisture = 1 }
  Ledger.add(bare, "radish", 0)
  Tasks.get(bare, "harvest").complete(bare, Actors.homesteader(bare), j)
  T.eq(next(bare.state.compost.bins), nil, "no bin to feed")
end)

T.test(
  "compost: spoiled food is partly recovered into the bin (a share, not all, and not when there is no bin)",
  function()
    local world, bin = binWorld()
    Ledger.add(world, "radish", 10, "test")
    Spoilage.ageStock(world, "radish", 20)
    local lost = collect(world, "food.spoilReport")
    Spoilage.daily(world)
    T.truthy(#lost == 1 and lost[1].total > 0, "the radishes rotted")
    T.near(Compost.raw(world, bin), lost[1].total * cfg.spoilShare, 1e-6)
    T.truthy(Compost.raw(world, bin) < lost[1].total, "only part of the loss comes back")
    local bare = newWorld()
    Ledger.add(bare, "radish", 10, "test")
    Spoilage.ageStock(bare, "radish", 20)
    Spoilage.daily(bare)
    T.eq(next(bare.state.compost.bins), nil, "no bin, pure loss as before")
  end
)

T.test("compost: a full bin turns the rest away, the fullest-room bin first", function()
  local world, a = binWorld()
  local b = place(world, "compost_bin", a)
  local cap = reg:get("objects", "compost_bin").compost.raw
  world.state.compost.bins[a] = { raw = cap - 1 }
  T.eq(Compost.feed(world, 5, "residue"), 5)
  T.eq(Compost.raw(world, b), 5, "the bin with more room takes it")
  local room = Compost.totalRoom(world)
  T.eq(Compost.feed(world, 2 * cap, "residue"), room, "only what fits goes in; the rest is lost")
  T.eq(Compost.totalRoom(world), 0)
end)

-- The bin's timer --------------------------------------------------------------------------------------

T.test("compost: a bin starts a batch from startAt raw units and delivers compost after its hours", function()
  local world, bin = binWorld()
  local started, done = collect(world, "compost.started"), collect(world, "compost.done")
  Compost.feed(world, cfg.startAt - 1, "residue")
  run(world, 1)
  T.eq(Compost.batch(world, bin), nil, "too little to start")
  Compost.feed(world, 1, "residue")
  run(world, STEP * 2)
  local batch = Compost.batch(world, bin)
  T.truthy(batch, "a batch is running")
  T.eq(started[1].raw, cfg.startAt)
  T.eq(batch.count, math.max(1, math.floor(cfg.startAt * cfg.yield)))
  T.eq(Compost.raw(world, bin), 0, "the raw went into the batch")
  run(world, hoursToSeconds(cfg.hours) - 1)
  T.eq(Ledger.get(world, "compost"), 0, "not done yet")
  run(world, 2)
  T.eq(Ledger.get(world, "compost"), math.max(1, math.floor(cfg.startAt * cfg.yield)))
  T.eq(Compost.batch(world, bin), nil)
  T.eq(done[1].count, math.max(1, math.floor(cfg.startAt * cfg.yield)))
end)

T.test("compost: a batch takes at most batchRaw, and a second batch follows from what is left", function()
  local world, bin = binWorld()
  Compost.feed(world, cfg.batchRaw + cfg.startAt, "residue")
  run(world, STEP * 2)
  T.eq(Compost.batch(world, bin).count, math.floor(cfg.batchRaw * cfg.yield))
  T.eq(Compost.raw(world, bin), cfg.startAt)
  run(world, hoursToSeconds(cfg.hours) + 1)
  T.eq(Ledger.get(world, "compost"), math.floor(cfg.batchRaw * cfg.yield))
  run(world, STEP * 2)
  T.truthy(Compost.batch(world, bin), "the next batch started")
end)

T.test("compost: a batch the ledger has no room for waits in the bin, then delivers", function()
  local world, bin = binWorld()
  local cap = reg:get("resources", "compost").capacity
  Ledger.add(world, "compost", cap, "test")
  local blocked = collect(world, "compost.blocked")
  Compost.feed(world, cfg.startAt, "residue")
  run(world, hoursToSeconds(cfg.hours) + 1)
  T.eq(#blocked, 1, "told once")
  T.truthy(Compost.batch(world, bin).blocked)
  T.eq(Ledger.get(world, "compost"), cap)
  Ledger.remove(world, "compost", cap, "test")
  run(world, 1)
  T.eq(Compost.batch(world, bin), nil)
  T.truthy(Ledger.get(world, "compost") > 0, "delivered once there was room")
  T.eq(world.state.compost.made, Ledger.get(world, "compost"))
end)

T.test("compost: picking up or destroying a bin loses its contents, moving it keeps them", function()
  local world, bin = binWorld()
  Compost.feed(world, 7, "residue")
  local to = spotFor(world, "compost_bin", bin)
  Compost.relocate(world, bin, to)
  T.eq(Compost.raw(world, to), 7)
  T.eq(Compost.raw(world, bin), 0)
  Compost.scrap(world, to)
  T.eq(Compost.raw(world, to), 0)
  local fresh, anchor = binWorld()
  Compost.feed(fresh, 5, "residue")
  T.truthy(Placement.destroy(fresh, anchor))
  T.eq(fresh.state.compost.bins[anchor], nil, "destroyed with the bin")
end)

-- Fertilizing -----------------------------------------------------------------------------------------

T.test("compost: Fertilize spreads one unit on a worn field tile, raising its fertility", function()
  local world = newWorld()
  setTime(world, SUMMER + 3)
  local i = fieldTile(world)
  local j = fieldTile(world, i)
  local fertilize = Tasks.get(world, "fertilize")
  local hs = Actors.homesteader(world)
  T.eq(fertilize.category, "maintenance")
  world.state.grid.fertility[i] = 0.3
  Soil.add(world, i, -0.1, "test") -- 0.2, and in the worked set
  world.state.grid.fertility[j] = 0.7
  Soil.add(world, j, -0.1, "test") -- 0.6
  T.falsy(fertilize.canDo(world, hs, i, nil), "no compost, no job")
  Ledger.add(world, "compost", 3, "test")
  local offered = {}
  fertilize.candidates(world, hs, function(t)
    offered[#offered + 1] = t
  end)
  T.same(offered, { i }, "the routine goes to a tile under fertilizeBelow")
  T.truthy(fertilize.canDo(world, hs, i, nil))
  T.falsy(fertilize.canDo(world, hs, j, nil), "the routine leaves a middling tile")
  T.truthy(fertilize.canDo(world, hs, j, {}), "a tap spreads on any tile under fertilizeMax")
  local spread = collect(world, "compost.spread")
  fertilize.complete(world, hs, i)
  T.near(Soil.fertility(world, i), 0.2 + cfg.compostFertility, 0.001)
  T.eq(Ledger.get(world, "compost"), 2)
  T.near(spread[1].from, 0.2, 0.001)
  world.state.grid.fertility[i] = cfg.fertilizeMax
  T.falsy(fertilize.canDo(world, hs, i, {}), "a full tile gains nothing")
  local grass = spotFor(world, "compost_bin") -- open ground, not part of the farm
  T.falsy(fertilize.canDo(world, hs, grass, {}), "only farmland takes it")
end)

T.test("compost: the routine is offered only the lowest-fertility worn tile, ties to the lower index", function()
  local world = newWorld()
  setTime(world, SUMMER + 3)
  local a = fieldTile(world)
  local b = fieldTile(world, a)
  local c = fieldTile(world, a, b)
  for _, i in ipairs({ a, b, c }) do
    world.state.grid.fertility[i] = 0.5
  end
  Soil.add(world, a, -0.2, "test") -- 0.3
  Soil.add(world, b, -0.4, "test") -- 0.1
  Soil.add(world, c, -0.4, "test") -- 0.1
  Ledger.add(world, "compost", 5, "test")
  local fertilize = Tasks.get(world, "fertilize")
  local hs = Actors.homesteader(world)
  local offered = {}
  fertilize.candidates(world, hs, function(t)
    offered[#offered + 1] = t
  end)
  T.same(offered, { math.min(b, c) }, "one candidate: the worst tile, the lower index on a tie")
  T.truthy(fertilize.canDo(world, hs, a, {}), "a tap still spreads on any tile under fertilizeMax")
end)

T.test("compost: the idle routine walks over, spreads the compost and the fertility rises", function()
  local world = newWorld(3)
  world.control = "idle"
  setTime(world, SUMMER + 3, 7)
  local i = fieldTile(world)
  world.state.fields.plan[i] = "radish" -- planned, so the routine does not untill it as a leftover
  Ledger.remove(world, "seed_radish", Ledger.get(world, "seed_radish"), "test") -- and has nothing to plant
  world.state.grid.fertility[i] = 0.5
  Soil.add(world, i, -0.3, "test")
  Ledger.add(world, "compost", 2, "test")
  local before = Soil.fertility(world, i)
  run(world, 40)
  T.truthy(Soil.fertility(world, i) >= before + cfg.compostFertility - 0.001, "the routine fertilized it")
  T.truthy(Ledger.get(world, "compost") < 2)
end)

-- The whole loop ---------------------------------------------------------------------------------------

T.test("compost: hens to manure to bin to compost to a worn field, through the real tasks", function()
  local world = newWorld(2)
  setTime(world, SUMMER + 3)
  local coop = place(world, "chicken_coop")
  local bin = place(world, "compost_bin")
  Ledger.add(world, "hen", 6, "test")
  local hs = Actors.homesteader(world)
  for _ = 1, 8 do
    newDay(world)
  end
  Tasks.get(world, "tend_coop").complete(world, hs, coop)
  local manure = Ledger.get(world, "manure")
  T.truthy(manure >= cfg.startAt, "a week of hens is enough for a batch")
  run(world, STEP * 2) -- the bin draws it by itself
  T.eq(Ledger.get(world, "manure"), 0)
  T.truthy(Compost.raw(world, bin) + (Compost.batch(world, bin) and 1 or 0) > 0)
  T.truthy(Compost.batch(world, bin), "the bin is cooking")
  run(world, hoursToSeconds(cfg.hours) + 1)
  local made = Ledger.get(world, "compost")
  T.truthy(made >= 1)
  local tile = fieldTile(world)
  world.state.grid.fertility[tile] = 0.5
  Soil.add(world, tile, -0.3, "test")
  Tasks.get(world, "fertilize").complete(world, hs, tile)
  T.near(Soil.fertility(world, tile), 0.2 + cfg.compostFertility, 0.001)
  T.eq(Ledger.get(world, "compost"), made - 1)
  T.eq(world.state.compost.spread, 1)
end)

-- Saving ----------------------------------------------------------------------------------------------

T.test("compost: muck, bins and the counters survive a save", function()
  local world, bin = binWorld()
  Compost.feed(world, cfg.startAt + 0.5, "residue")
  run(world, STEP * 2)
  world.state.compost.muck.hens = 3.5
  local data = Save.newSlotData("Compost")
  data.run = world.state
  local disk = serialize.decode(serialize.encode(Save.forDisk(data)))
  Gridpack.unpack(disk.run.grid)
  local loaded = World.new({ registry = reg, tuning = tun }, disk.run)
  T.eq(Compost.muck(loaded, "hens"), 3.5)
  T.near(Compost.raw(loaded, bin), 0.5, 1e-9)
  T.truthy(Compost.batch(loaded, bin))
end)
