-- Routine defaults (PLAN_DEPTH "Depth trim", D185, issue #430, absorbs #370): every upkeep task is ON in the default
-- routine, and an idle day finishes them all. Neglect only costs a share of yield (`farming.minSoilMultiplier`), so an
-- idle player does fine. A new upkeep task (category "maintenance") fails the table test here until it has a scenario.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Compost = require("src.sim.systems.compost")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Soil = require("src.sim.systems.soil")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local SUMMER = tun.time.daysPerSeason + 1

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "idle"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function runDay(world)
  for _ = 1, math.floor(tun.time.dayLength / STEP) do
    world:tick(STEP)
  end
end

--- `n` free tillable tiles near the spawn, tilled and planned (a field the routine has nothing to untill or plant).
local function field(world, n)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local tiles = {}
  for r = 1, 12 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and #tiles < n
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and not Crops.tileInUse(world, i)
          and i ~= world.state.land.spawn
        then
          world.state.fields.tilled[i] = true
          world.state.fields.plan[i] = "radish"
          tiles[#tiles + 1] = i
        end
      end
    end
  end
  T.eq(#tiles, n, "room for the field")
  Ledger.remove(world, "seed_radish", Ledger.get(world, "seed_radish"), "test") -- nothing to plant
  return tiles
end

--- A world on a summer morning with a field of `n` tiles.
local function dayWorld(n)
  local world = newWorld(3)
  setTime(world, SUMMER + 2, 6)
  return world, field(world, n)
end

-- One scenario per upkeep task: set up the neglect, run one idle day, and check the routine did the job.
local SCENARIOS = {
  weed = function()
    local world, tiles = dayWorld(6)
    for _, i in ipairs(tiles) do
      world.state.soil.weeds[i] = 0.5
    end
    runDay(world)
    for _, i in ipairs(tiles) do
      T.truthy(Soil.weeds(world, i) < tun.soil.weedPullAt, "tile " .. i .. " was weeded inside the day")
    end
  end,
  fertilize = function()
    local world, tiles = dayWorld(3)
    for _, i in ipairs(tiles) do
      world.state.grid.fertility[i] = 0.5
    end
    Soil.add(world, tiles[1], -0.35, "test") -- 0.15, the worst
    Soil.add(world, tiles[2], -0.2, "test") -- 0.30
    Ledger.add(world, "compost", 2, "test")
    local before = Soil.fertility(world, tiles[1])
    runDay(world)
    T.truthy(Soil.fertility(world, tiles[1]) >= before + tun.compost.compostFertility - 0.001, "the worst tile got it")
  end,
}

T.test("routine defaults: every upkeep task has an idle-day scenario, and it passes", function()
  local seen = 0
  local byId = newWorld().taskTypes.byId
  for _, task in ipairs(newWorld().taskTypes.list) do
    if task.category == "maintenance" then
      seen = seen + 1
      local scenario = SCENARIOS[task.id]
      T.truthy(
        scenario,
        "upkeep task '" .. task.id .. "' needs an idle-day scenario in tests/test_routine_defaults.lua"
      )
      if scenario then
        scenario()
      end
    end
  end
  T.truthy(seen >= 2, "weeding and fertilizing are upkeep tasks")
  for id in pairs(SCENARIOS) do
    T.truthy(byId[id], "scenario '" .. id .. "' names a task that exists")
  end
end)

T.test("routine defaults: every category is ON except the opt-in ones, and upkeep sits above planting", function()
  local world = newWorld()
  local place = {}
  for rank, entry in ipairs(world.state.priorities) do
    place[entry.category] = rank
    local def = reg:get("task_categories", entry.category)
    T.eq(entry.enabled, not def.startsOff, entry.category .. " follows its default")
    T.eq(entry.cond, nil, entry.category .. " has no condition by default")
  end
  T.truthy(place.maintenance < place.plant, "weeds are pulled before new ground is planted")
  T.truthy(place.maintenance > place.harvest and place.maintenance > place.water, "but after harvest and water")
end)

T.test("routine defaults: manure in the ledger reaches the bin with no one hauling it", function()
  local world = newWorld(2)
  setTime(world, SUMMER + 2, 6)
  local spot
  for i = 1, #world.state.grid.terrain do
    if not spot and Inventory.canPlace(world, "compost_bin", i) then
      spot = i
    end
  end
  Inventory.addObject(world, "compost_bin")
  T.truthy(Inventory.place(world, "compost_bin", spot))
  Ledger.add(world, "manure", 6, "test")
  runDay(world)
  T.eq(Ledger.get(world, "manure"), 0)
  T.truthy(Compost.raw(world, spot) > 0 or Compost.batch(world, spot) or Ledger.get(world, "compost") > 0)
end)

T.test("routine defaults: an idle day does all the upkeep at once", function()
  local world, tiles = dayWorld(8)
  for n, i in ipairs(tiles) do
    world.state.grid.fertility[i] = 0.5
    if n <= 5 then
      world.state.soil.weeds[i] = 0.4
    end
  end
  Soil.add(world, tiles[8], -0.4, "test") -- the worst of them
  Ledger.add(world, "compost", 3, "test")
  local before = Soil.fertility(world, tiles[8])
  runDay(world)
  for _, i in ipairs(tiles) do
    T.truthy(Soil.weeds(world, i) < tun.soil.weedPullAt, "clean after the day")
  end
  T.truthy(Soil.fertility(world, tiles[8]) > before, "and the worst tile was fed")
end)
