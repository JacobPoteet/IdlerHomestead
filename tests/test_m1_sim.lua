local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")
local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Crops = require("src.sim.systems.crops")
local Actors = require("src.sim.systems.actors")
local Needs = require("src.sim.systems.needs")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

-- Find `count` tillable, unoccupied tiles near the spawn for a test field.
local function fieldNearSpawn(world, count)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local tiles = {}
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        if #tiles < count and Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if Grid.terrain(world, i).tillable and not world.occupancy[i] and i ~= world.state.land.spawn then
            local dup = false
            for _, t in ipairs(tiles) do
              dup = dup or t == i
            end
            if not dup then
              tiles[#tiles + 1] = i
            end
          end
        end
      end
    end
  end
  return tiles
end

-- Land -----------------------------------------------------------------------

T.test("landgen: same seed, same land; different seed, different land", function()
  local a, b, c = newWorld(11), newWorld(11), newWorld(12)
  T.eq(serialize.encode(a.state.grid), serialize.encode(b.state.grid))
  T.truthy(serialize.encode(a.state.grid) ~= serialize.encode(c.state.grid))
end)

T.test("landgen: creek, fords, road, truck, clear spawn", function()
  for seed = 1, 20 do
    local world = newWorld(seed)
    local grid = world.state.grid
    local counts = {}
    for i = 1, #grid.terrain do
      counts[grid.terrain[i]] = (counts[grid.terrain[i]] or 0) + 1
    end
    T.truthy((counts.water or 0) >= grid.h, "seed " .. seed .. " creek")
    T.truthy((counts.ford or 0) >= 1, "seed " .. seed .. " ford")
    T.truthy((counts.road or 0) >= tun.landgen.roadMinLength - 4, "seed " .. seed .. " road")
    local truck = Grid.object(world, world.state.land.truck)
    T.eq(truck.id, "truck")
    T.truthy(Grid.walkable(world, world.state.land.spawn), "seed " .. seed .. " spawn walkable")
  end
end)

T.test("landgen: the far bank is reachable through a ford", function()
  for seed = 1, 10 do
    local world = newWorld(seed)
    local grid = world.state.grid
    local spawn = world.state.land.spawn
    local sx = Grid.coords(grid, spawn)
    -- Find a walkable grass tile on the other side of the creek.
    local target
    for i = 1, #grid.terrain do
      local x = Grid.coords(grid, i)
      local creekBetween = false
      local lo, hi = math.min(x, sx), math.max(x, sx)
      local _, y = Grid.coords(grid, i)
      for cx = lo, hi do
        if grid.terrain[Grid.index(grid, cx, y)] == "water" then
          creekBetween = true
        end
      end
      if creekBetween and grid.terrain[i] == "grass" and Grid.walkable(world, i) then
        target = i
        break
      end
    end
    T.truthy(target, "seed " .. seed .. " has a far bank")
    -- Clutter may wall things off, so test with objects ignored: only terrain matters here.
    local saved = world.occupancy
    world.occupancy = {}
    local path = Pathfind.find(world, spawn, function(i)
      return i == target
    end, target)
    world.occupancy = saved
    T.truthy(path, "seed " .. seed .. " far bank reachable")
  end
end)

T.test("landgen: no clutter right around the truck", function()
  local world = newWorld(5)
  local grid = world.state.grid
  for anchor, obj in pairs(grid.objects) do
    if obj.id ~= "truck" then
      T.truthy(Grid.distance(grid, anchor, world.state.land.truck) > tun.landgen.truckClearRadius)
    end
  end
end)

T.test("land: starting kit is given once, not again on load", function()
  local world = newWorld(3)
  T.eq(Ledger.get(world, "seed_radish"), tun.run.startingResources.seed_radish)
  local reloaded = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(Ledger.get(reloaded, "seed_radish"), tun.run.startingResources.seed_radish)
end)

-- Calendar -------------------------------------------------------------------

T.test("calendar: starts at the configured hour on spring day 1", function()
  local world = newWorld(1)
  local now = Calendar.now(world)
  T.eq(now.day, 1)
  T.eq(now.season, "spring")
  T.eq(now.year, 1)
  T.near(now.hour, tun.time.startHour, 1e-6)
end)

T.test("calendar: days, seasons and years roll over with events", function()
  local world = newWorld(1)
  local days, seasons = 0, {}
  world.events:on("calendar.newDay", function()
    days = days + 1
  end)
  world.events:on("calendar.newSeason", function(e)
    seasons[#seasons + 1] = e.season
  end)
  local daysToAdvance = tun.time.daysPerSeason * #tun.time.seasons
  world.state.calendar.elapsed = 0
  for _ = 1, daysToAdvance do
    world.state.calendar.elapsed = world.state.calendar.elapsed + tun.time.dayLength
    world:tick(0)
  end
  T.eq(days, daysToAdvance)
  T.eq(#seasons, #tun.time.seasons)
  T.eq(seasons[#seasons], "spring")
  T.eq(Calendar.now(world).year, 2)
end)

-- Orders & tasks -------------------------------------------------------------

T.test("orders: tapping picks the right task for the tile", function()
  local world = newWorld(8)
  local hs = Actors.homesteader(world)
  local grid = world.state.grid
  -- A clutter object near the spawn
  local brushTile
  for anchor, obj in pairs(grid.objects) do
    if obj.id ~= "truck" and obj.id ~= "tree" and Pathfind.toWorkSpot(world, world.state.land.spawn, anchor) then
      brushTile = anchor
      break
    end
  end
  T.eq(Actors.order(world, hs, brushTile).id, "clear")
  local field = fieldNearSpawn(world, 1)[1]
  T.eq(Actors.order(world, hs, field, { crop = "radish" }).id, "till")
  T.eq(Actors.order(world, hs, field).id, "move", "no seed selected: just walk there")
end)

T.test("orders: till, plant, water, harvest by hand", function()
  local world = newWorld(9)
  local hs = Actors.homesteader(world)
  local tile = fieldNearSpawn(world, 1)[1]
  Actors.order(world, hs, tile, { crop = "radish" })
  run(world, 10)
  T.truthy(world.state.fields.tilled[tile], "tilled")
  T.eq(world.state.fields.plan[tile], "radish")
  Actors.order(world, hs, tile, { crop = "radish" })
  run(world, 10)
  T.truthy(world.state.crops[tile], "planted")
  T.eq(Ledger.get(world, "seed_radish"), tun.run.startingResources.seed_radish - 1)
  hs.bucket = 2
  Actors.order(world, hs, tile)
  run(world, 5)
  T.eq(world.state.crops[tile].moisture > 0.9, true, "watered")
  world.state.crops[tile].growth = 1
  Actors.order(world, hs, tile)
  run(world, 5)
  T.eq(world.state.crops[tile], nil, "harvested")
  T.truthy(Ledger.get(world, "radish") >= 1)
end)

T.test("idle routine farms a planned field end to end", function()
  local world = newWorld(21)
  world.control = "idle"
  local tiles = fieldNearSpawn(world, 6)
  for _, i in ipairs(tiles) do
    T.truthy(Crops.setPlan(world, i, "radish"))
  end
  local harvested, fetched = 0, 0
  world.events:on("crop.harvested", function(e)
    harvested = harvested + e.amount
  end)
  world.events:on("task.completed", function(e)
    if e.task == "fetch_water" then
      fetched = fetched + 1
    end
  end)
  -- Long enough to clear, till, plant and grow radishes with watering.
  run(world, tun.time.dayLength * 4)
  T.truthy(fetched > 0, "fetched water")
  T.truthy(harvested > 0, "harvested something (got " .. harvested .. ")")
end)

T.test("idle routine respects disabled categories", function()
  local world = newWorld(21)
  world.control = "idle"
  for _, entry in ipairs(world.state.priorities) do
    entry.enabled = false
  end
  local done = 0
  world.events:on("task.completed", function()
    done = done + 1
  end)
  run(world, 20)
  T.eq(done, 0)
end)

T.test("active control: no idle work without orders", function()
  local world = newWorld(21)
  world.control = "active"
  local done = 0
  world.events:on("task.completed", function()
    done = done + 1
  end)
  run(world, 20)
  T.eq(done, 0)
end)

-- Needs ----------------------------------------------------------------------

T.test("needs: eats daily, freshest first; hunger costs condition", function()
  local world = newWorld(2)
  Ledger.add(world, "radish", 10)
  Needs.eat(world)
  T.eq(Ledger.get(world, "radish"), 10 - math.ceil(tun.needs.dailyCalories / 300))
  T.eq(Ledger.get(world, "canned_food"), tun.run.startingResources.canned_food)
  -- Empty the pantry and go hungry.
  for _, id in ipairs({ "radish", "potato", "canned_food" }) do
    Ledger.remove(world, id, Ledger.get(world, id))
  end
  local before = world.state.needs.condition
  Needs.eat(world)
  T.eq(world.state.needs.condition, before - tun.needs.hungerDamage)
end)

-- Persistence ----------------------------------------------------------------

T.test("save mid-job: the homesteader resumes the same job", function()
  local world = newWorld(9)
  local hs = Actors.homesteader(world)
  local tile = fieldNearSpawn(world, 1)[1]
  Actors.order(world, hs, tile, { crop = "potato" })
  run(world, 0.5)
  T.truthy(hs.job, "has a job")
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  run(restored, 10)
  T.truthy(restored.state.fields.tilled[tile], "tilled after reload")
end)
