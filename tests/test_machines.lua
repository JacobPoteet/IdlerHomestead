-- Machines (GDD §7.4, D14, D65): stationary actors with a capability set and an area, claiming
-- through the task board's reservations, drawing power as "demand" sinks. First machine: the
-- auto-harvester.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Machines = require("src.sim.systems.machines")
local Power = require("src.sim.systems.power")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24
local DAY = 1 -- the first day: jumping the calendar further would skip the weather queue (it rolls day by day)
local HARVESTER = "auto_harvester"
local DEF = reg:get("objects", HARVESTER)

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function run(world, seconds, each)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
    if each then
      each()
    end
  end
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
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

--- Free tillable tiles with Chebyshev distance in [minD, maxD] of `center`, nearest first.
local function tilesAround(world, center, minD, maxD, count)
  local grid = world.state.grid
  local list = {}
  for i = 1, #grid.terrain do
    local d = Grid.distance(grid, center, i)
    if
      d >= minD
      and d <= maxD
      and Grid.terrain(world, i).tillable
      and not world.occupancy[i]
      and not Crops.tileInUse(world, i)
    then
      list[#list + 1] = { i = i, d = d }
    end
  end
  table.sort(list, function(a, b)
    return a.d < b.d or (a.d == b.d and a.i < b.i)
  end)
  local tiles = {}
  for n = 1, math.min(count, #list) do
    tiles[n] = list[n].i
  end
  return tiles
end

local function plantRipe(world, i)
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = "radish"
  world.state.crops[i] = { id = "radish", growth = 1, moisture = 0 }
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

local function ripeCount(world, tiles)
  local n = 0
  for _, i in ipairs(tiles) do
    local crop = world.state.crops[i]
    if crop and Crops.isMature(crop) then
      n = n + 1
    end
  end
  return n
end

-- A harvester (and, unless `unpowered`, a solar array) at midday in summer with `count` ripe radishes
-- in reach. Returns world, harvester anchor, the ripe tiles.
local function harvestWorld(seed, count, unpowered)
  local world = newWorld(seed)
  clearPanels(world)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  if not unpowered then
    -- Out of the way, so the homesteader is not walled in beside the truck.
    place(world, "solar_array", Grid.index(grid, sx + 10, sy + 3))
  end
  local anchor = place(world, HARVESTER, Grid.index(grid, sx + 5, sy + 3))
  local tiles = tilesAround(world, anchor, 1, DEF.machine.radius, count or 6)
  for _, i in ipairs(tiles) do
    plantRipe(world, i)
  end
  setTime(world, DAY, 10)
  return world, anchor, tiles
end

-- Content ----------------------------------------------------------------------------------------

T.test("machines content: the auto-harvester has art, a sink in the machines tier and a mid-game price", function()
  local sprites = require("assets.manifest").sprites
  T.truthy(sprites[HARVESTER] and sprites["icon_" .. HARVESTER], "sprite and icon")
  T.truthy(DEF.placeable and DEF.blocks)
  T.eq(DEF.sink.tier, "machines")
  T.eq(DEF.sink.schedule, "demand")
  T.truthy(DEF.machine.radius >= 1 and DEF.machine.workSpeed > 0)
  for _, category in ipairs(DEF.machine.categories) do
    T.truthy(reg:get("task_categories", category), category)
  end
  local item = reg:get("catalog", HARVESTER)
  T.eq(item.object, HARVESTER)
  T.eq(item.page, "machines")
  -- A clear mid-game goal: dearer than the first power items, in the range of the big ones.
  T.truthy(item.price > reg:get("catalog", "solar_array").price, "price above the array")
  T.truthy(item.price <= reg:get("catalog", "micro_hydro").price, "price not above micro-hydro")
  for _, note in ipairs(item.needs) do
    T.truthy(reg:get("notes", note), note)
  end
  T.truthy(item.studyNights >= 2)
end)

T.test("tasks: a capability set allows only its categories and, if listed, its task ids", function()
  local world = newWorld(1)
  local harvest, water = Tasks.get(world, "harvest"), Tasks.get(world, "water_crop")
  T.truthy(Tasks.allows(nil, harvest) and Tasks.allows(nil, water), "no caps: everything")
  local caps = { categories = { "harvest" } }
  T.truthy(Tasks.allows(caps, harvest))
  T.falsy(Tasks.allows(caps, water))
  T.falsy(Tasks.allows(caps, Tasks.get(world, "move")), "player-only tasks have no category")
  T.falsy(Tasks.allows({ categories = { "harvest" }, tasks = { "nope" } }, harvest))
  T.truthy(Tasks.allows({ categories = { "harvest" }, tasks = { "harvest" } }, harvest))
end)

-- Work, capability and area -------------------------------------------------------------------------

T.test("harvester: picks every ripe crop in reach, nearest first, at its work speed", function()
  local world, anchor, tiles = harvestWorld(3, 6)
  local done = collect(world, "task.completed")
  local harvested = collect(world, "crop.harvested")
  run(world, HOUR * 2)
  T.eq(ripeCount(world, tiles), 0, "all picked")
  T.eq(#harvested, #tiles)
  T.eq(Machines.done(world), #tiles)
  T.eq(done[1].actor, Machines.at(world, anchor).id)
  T.eq(done[1].machine, HARVESTER)
  local grid = world.state.grid
  for n = 2, #harvested do
    T.truthy(
      Grid.distance(grid, anchor, harvested[n - 1].tile) <= Grid.distance(grid, anchor, harvested[n].tile),
      "nearest first"
    )
  end
  T.truthy(Ledger.get(world, "radish") > 0, "produce reached the ledger")
  T.eq(Machines.at(world, anchor).status, "idle")
  -- Speed: one crop takes harvestTime / workSpeed seconds of full power (plus a tick to ask for power).
  local world2 = harvestWorld(3, 1)
  local per = tun.farming.harvestTime / DEF.machine.workSpeed
  run(world2, per * 0.9)
  T.eq(Machines.done(world2), 0, "not before its work time")
  run(world2, per * 0.2 + STEP * 3)
  T.eq(Machines.done(world2), 1, "done at its work time")
end)

T.test("harvester: leaves crops outside its radius and work outside its capability", function()
  local world, anchor = harvestWorld(3, 0)
  local far = tilesAround(world, anchor, DEF.machine.radius + 1, DEF.machine.radius + 3, 3)
  for _, i in ipairs(far) do
    plantRipe(world, i)
  end
  local near = tilesAround(world, anchor, 1, 1, 1)[1]
  world.state.fields.tilled[near] = true
  world.state.fields.plan[near] = "radish"
  world.state.crops[near] = { id = "radish", growth = 0.2, moisture = 0 } -- thirsty, not ripe
  local unplanted = tilesAround(world, anchor, 1, 2, 1)[1]
  world.state.fields.plan[unplanted] = "radish" -- planned, untilled
  Tasks.setPriorityEnabled(world, "plant", false) -- the homesteader tills planned tiles itself (D92); only the machine is tested here
  run(world, HOUR * 2)
  T.eq(ripeCount(world, far), #far, "out of reach")
  T.eq(world.state.crops[near].moisture, 0, "never waters")
  T.falsy(world.state.fields.tilled[unplanted], "never tills")
  T.eq(Machines.done(world), 0)
  T.eq(Machines.at(world, anchor).status, "idle")
end)

-- Power ------------------------------------------------------------------------------------------------

T.test("power: draws its kW in the machines tier only while it has work", function()
  local world, anchor = harvestWorld(3, 0)
  run(world, HOUR * 0.5)
  T.eq(Power.flow(world).tiers.machines.demand, 0, "idle draws nothing")
  T.eq(Power.sinkState(world, anchor), "idle")
  local tiles = tilesAround(world, anchor, 1, DEF.machine.radius, 8)
  for _, i in ipairs(tiles) do
    plantRipe(world, i)
  end
  run(world, tun.machines.recheckInterval + STEP * 3) -- an idle machine looks again within its recheck interval
  T.near(Power.flow(world).tiers.machines.demand, DEF.sink.draw, 1e-9, "draws while working")
  T.truthy(Power.flow(world).tiers.machines.served > 0)
  run(world, HOUR * 3)
  T.eq(ripeCount(world, tiles), 0)
  run(world, tun.machines.recheckInterval + STEP * 3)
  T.eq(Power.flow(world).tiers.machines.demand, 0, "stops drawing when done")
end)

T.test("power: with no power it stops, says so once a day, and leaves the crops to the homesteader", function()
  local world, anchor, tiles = harvestWorld(3, 4, true)
  local warned = collect(world, "machine.unpowered")
  run(world, HOUR)
  local unit = Machines.at(world, anchor)
  T.eq(unit.status, "unpowered")
  T.eq(ripeCount(world, tiles), #tiles, "nothing picked")
  T.eq(unit.job, nil, "holds no claim")
  T.eq(#warned, 1, "announced once")
  T.truthy(Power.requested(world, anchor), "keeps asking for power")
  -- The idle homesteader is free to take every one of them.
  world.control = "idle"
  run(world, HOUR * 3)
  T.eq(ripeCount(world, tiles), 0, "the homesteader harvested them")
  T.eq(Machines.done(world), 0)
  T.eq(#warned, 1)
end)

T.test("power: a low share stops it, a middling share slows it", function()
  local fullWorld = harvestWorld(3, 8)
  run(fullWorld, HOUR)
  local full = Machines.done(fullWorld)
  -- An array's output split over a much bigger draw: under minPowerRatio, so it stops.
  with({ { DEF.sink, "draw", 100 } }, function()
    local world, anchor = harvestWorld(3, 8)
    run(world, HOUR)
    T.eq(Machines.at(world, anchor).status, "unpowered")
    T.truthy(Power.sinkRatio(world, anchor) < tun.machines.minPowerRatio)
    T.eq(Machines.done(world), 0)
  end)
  -- Between the floor and full power it works, slower.
  local sun
  do
    local probe = harvestWorld(3, 0)
    run(probe, STEP)
    sun = Power.output(probe)
  end
  with({ { DEF.sink, "draw", sun / 0.5 } }, function()
    local world, anchor = harvestWorld(3, 8)
    run(world, HOUR)
    local unit = Machines.at(world, anchor)
    T.truthy(unit.status == "slow" or unit.status == "idle", "status " .. unit.status)
    T.truthy(Machines.done(world) > 0 and Machines.done(world) < full, Machines.done(world) .. " vs " .. full)
  end)
end)

T.test("power: switched off in the power panel it idles and draws nothing", function()
  local world, anchor, tiles = harvestWorld(3, 4)
  Power.setEnabled(world, anchor, false)
  run(world, HOUR)
  T.eq(Machines.at(world, anchor).status, "off")
  T.eq(ripeCount(world, tiles), #tiles)
  T.eq(Power.flow(world).tiers.machines.demand, 0)
  Power.setEnabled(world, anchor, true)
  run(world, HOUR * 2)
  T.eq(ripeCount(world, tiles), 0)
end)

-- Claims ------------------------------------------------------------------------------------------

T.test("claims: the harvester and the idle homesteader never work the same crop", function()
  local world, anchor = harvestWorld(5, 0)
  local tiles = tilesAround(world, anchor, 1, DEF.machine.radius, 20)
  for _, i in ipairs(tiles) do
    plantRipe(world, i)
  end
  world.control = "idle"
  local hs = Actors.homesteader(world)
  local byTile, clash = {}, 0
  world.events:on("crop.harvested", function(e)
    byTile[e.tile] = (byTile[e.tile] or 0) + 1
  end)
  local byWhom = {}
  world.events:on("task.completed", function(e)
    if e.task == "harvest" then
      byWhom[e.actor] = (byWhom[e.actor] or 0) + 1
    end
  end)
  run(world, HOUR * 4, function()
    local unit = Machines.at(world, anchor)
    if unit.job and hs.job and hs.job.task == "harvest" and hs.job.target == unit.job.target then
      clash = clash + 1
    end
  end)
  T.eq(clash, 0, "never the same target")
  T.eq(ripeCount(world, tiles), 0)
  for i, n in pairs(byTile) do
    T.eq(n, 1, "tile " .. i .. " harvested once")
  end
  T.truthy((byWhom[1] or 0) > 0 and (byWhom[Machines.at(world, anchor).id] or 0) > 0, "both did some of the work")
end)

T.test("claims: a player order takes a crop the machine is working; one harvest, no stolen claim", function()
  local world, anchor = harvestWorld(3, 1)
  run(world, STEP * 4)
  local unit = Machines.at(world, anchor)
  T.truthy(unit.job, "the machine is working")
  local target = unit.job.target
  local harvested = collect(world, "crop.harvested")
  local hs = Actors.homesteader(world)
  local ordered, full = Actors.order(world, hs, target, {})
  T.truthy(ordered, "the order is accepted")
  T.eq(full, nil)
  run(world, STEP)
  T.eq(Tasks.holder(world, "harvest", target), hs.id, "the homesteader holds it")
  T.eq(unit.job, nil, "the machine let go")
  run(world, HOUR)
  T.eq(#harvested, 1)
  T.eq(Machines.done(world), 0)
end)

-- Storage, crate ------------------------------------------------------------------------------------

T.test("storage: a full store holds the crops in the ground and the machine reports it", function()
  local world, anchor, tiles = harvestWorld(3, 4)
  Ledger.setCapacity(world, "radish", Ledger.get(world, "radish"))
  run(world, HOUR)
  local unit = Machines.at(world, anchor)
  T.eq(unit.status, "full")
  T.eq(unit.full, "radish")
  T.eq(ripeCount(world, tiles), #tiles, "held in the ground")
  T.eq(Power.flow(world).tiers.machines.demand, 0, "no draw while held")
  Ledger.setCapacity(world, "radish", nil)
  run(world, HOUR * 2)
  T.eq(ripeCount(world, tiles), 0, "picked once there is room")
end)

T.test("storage: produce goes the same way as a hand harvest (kept, then surplus)", function()
  local world = harvestWorld(3, 8)
  Food.setKeep(world, "radish", 0)
  run(world, HOUR * 2)
  T.truthy(Ledger.get(world, "radish") > 0)
  T.eq(Food.surplus(world, "radish"), Ledger.get(world, "radish"), "keep 0: all of it is surplus")
end)

-- Determinism and saves ---------------------------------------------------------------------------------

local function busyWorld(seed)
  local world, anchor = harvestWorld(seed, 0)
  for _, i in ipairs(tilesAround(world, anchor, 1, DEF.machine.radius + 2, 24)) do
    plantRipe(world, i)
  end
  world.control = "idle"
  return world
end

T.test("determinism: the same seed gives the same run with a machine and the homesteader", function()
  local a, b = busyWorld(7), busyWorld(7)
  run(a, HOUR * 3)
  run(b, HOUR * 3)
  T.eq(serialize.encode(a.state), serialize.encode(b.state))
  T.truthy(Machines.done(a) > 0)
end)

T.test("saves: save and load mid-job carries on identically", function()
  local a = busyWorld(7)
  local unit
  run(a, STEP * 6)
  unit = Machines.list(a)[1]
  T.truthy(unit.job, "mid-job at the save")
  local b = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  b.control = a.control
  T.eq(Tasks.holder(b, unit.job.task, unit.job.target), unit.id, "the claim is rebuilt on load")
  run(a, HOUR * 2)
  run(b, HOUR * 2)
  T.truthy(serialize.encode(a.state) == serialize.encode(b.state), "the loaded run matches")
end)

T.test("saves: a save from before machines loads, and a machine placed later works", function()
  local a = harvestWorld(3, 0)
  run(a, STEP * 3)
  local state = serialize.decode(serialize.encode(a.state))
  state.machines = nil
  state.power.requests = nil
  for _, actor in ipairs(state.actors) do
    if actor.job then
      actor.job.holder = nil -- jobs saved before reservations named a holder
    end
  end
  local b = World.new({ registry = reg, tuning = tun }, state)
  run(b, STEP * 2)
  local list = Machines.list(b)
  T.eq(#list, 1, "the placed harvester gets a unit")
  local tiles = tilesAround(b, Grid.index(b.state.grid, list[1].x, list[1].y), 1, DEF.machine.radius, 3)
  for _, i in ipairs(tiles) do
    plantRipe(b, i)
  end
  run(b, HOUR)
  T.eq(ripeCount(b, tiles), 0)
end)

T.test("actors: the homesteader is found by kind, and machines are not in the walking list", function()
  local world = harvestWorld(3, 2)
  T.eq(Actors.homesteader(world).kind, "homesteader")
  T.eq(#Actors.list(world), 1)
  T.eq(#Machines.list(world), 1)
end)

-- Balance sanity -------------------------------------------------------------------------------------

T.test("balance: a full reach is cleared within a day of sun for a few kWh", function()
  local world, anchor = harvestWorld(3, 0)
  local tiles = tilesAround(world, anchor, 1, DEF.machine.radius, 48)
  for _, i in ipairs(tiles) do
    plantRipe(world, i)
  end
  local kwh = 0
  run(world, HOUR * 10, function()
    kwh = kwh + Power.flow(world).tiers.machines.served * STEP / HOUR
  end)
  T.eq(ripeCount(world, tiles), 0, "48 crops in under ten daylight hours")
  -- Energy per crop: a small fraction of a 20 kWh truck trip for a whole field.
  local perCrop = kwh / #tiles
  T.truthy(perCrop > 0 and perCrop < 0.15, string.format("%.3f kWh a crop", perCrop))
  T.truthy(kwh < tun.economy.tripCost / 3, string.format("%.1f kWh for the field", kwh))
end)

T.test("harvester: ignores the routine's thresholds (they only steer the idle homesteader)", function()
  local world, _, tiles = harvestWorld(3, 4)
  world.tuning.idle.routineConditions = true -- conditions are off in the shipped tuning (playtest)
  for _, e in ipairs(world.state.priorities) do
    if e.category == "harvest" then
      e.cond = { kind = "hour_after", value = 23 } -- not before 23:00
    end
  end
  T.falsy(Tasks.conditionMet(world, "harvest"), "at ten in the morning the harvest category waits")
  local job = Tasks.chooseIdleJob(world, Actors.homesteader(world))
  T.truthy(job == nil or job.task ~= "harvest", "the homesteader's routine skips the held-back category")
  run(world, HOUR * 2)
  T.eq(ripeCount(world, tiles), 0, "the machine harvests regardless")
  T.truthy(Machines.done(world) > 0)
end)
