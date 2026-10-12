-- Day-to-day weather (GDD §7.1, D51): the seeded sky, season weighting, forecast, and what weather
-- does to crops, the cistern, power, and fishing.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Fishing = require("src.sim.systems.fishing")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Model = require("src.sim.minigames.fishing_model")
local Rng = require("src.core.rng")
local Power = require("src.sim.systems.power")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SPRING, SUMMER, AUTUMN, WINTER = 1, DPS + 1, 2 * DPS + 1, 3 * DPS + 1

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

--- Jump the clock to `hour` on `day` without ticking systems.
local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- Move to `day` and announce it, as Calendar.tick would (cheap: no systems tick).
local function gotoDay(world, day, hour)
  setTime(world, day, hour or 12)
  world.events:emit("calendar.newDay", { day = day })
end

local function force(world, kind)
  world.state.weather.sky.days[1] = kind
end

--- The kind of each day from `from` through `to`.
local function kinds(world, from, to)
  local list = {}
  for day = from, to do
    gotoDay(world, day)
    list[#list + 1] = Weather.kind(world)
  end
  return list
end

-- The sky -----------------------------------------------------------------------------------

T.test("weather: the sky is deterministic per seed and differs between seeds", function()
  local a, b, c = kinds(newWorld(5), 1, 40), kinds(newWorld(5), 1, 40), kinds(newWorld(6), 1, 40)
  T.same(a, b)
  T.truthy(table.concat(a, ",") ~= table.concat(c, ","), "another seed has another sky")
  T.eq(a[1], tun.weather.startKind, "a run starts on the start kind")
end)

T.test("weather: rolling the sky leaves the winter rolls alone", function()
  local world = newWorld(9)
  local expected = Weather.winter(newWorld(9), 1)
  kinds(world, 1, 12)
  T.same(Weather.winter(world, 1), expected)
end)

T.test("weather: every kind shows up over a long run, and the queue stays full", function()
  local world = newWorld(3)
  local seen = {}
  for _, kind in ipairs(kinds(world, 1, 200)) do
    seen[kind] = true
  end
  for _, kind in ipairs(tun.weather.order) do
    T.truthy(seen[kind], kind .. " happens")
  end
  T.eq(#world.state.weather.sky.days, tun.weather.queueDays)
end)

T.test("weather: seasons weight the kinds; winter never rains", function()
  local share = { [SPRING] = {}, [SUMMER] = {}, [AUTUMN] = {}, [WINTER] = {} }
  local totals = { [SPRING] = 0, [SUMMER] = 0, [AUTUMN] = 0, [WINTER] = 0 }
  for seed = 1, 40 do
    local world = newWorld(seed)
    kinds(world, 1, 0) -- nothing: just the start
    for _, start in ipairs({ SPRING, SUMMER, AUTUMN, WINTER }) do
      for day = start, start + DPS - 1 do
        gotoDay(world, day)
        local kind = Weather.kind(world)
        share[start][kind] = (share[start][kind] or 0) + 1
        totals[start] = totals[start] + 1
      end
    end
  end
  local function frac(start, kind)
    return (share[start][kind] or 0) / totals[start]
  end
  T.truthy(frac(SUMMER, "clear") > frac(AUTUMN, "clear"), "summer is clearer than autumn")
  T.truthy(frac(AUTUMN, "rain") + frac(AUTUMN, "storm") > frac(SUMMER, "rain") + frac(SUMMER, "storm") - 0.05, "autumn is wet")
  T.eq(share[WINTER].rain, nil, "no rain on frozen ground")
  T.eq(share[WINTER].storm, nil, "no storms on frozen ground")
end)

T.test("weather: spells have bounded lengths and storms last their one day", function()
  local world = newWorld(11)
  local list = kinds(world, 1, 120)
  local run, runKind = 0, nil
  for _, kind in ipairs(list) do
    if kind == runKind then
      run = run + 1
    else
      run, runKind = 1, kind
    end
    T.truthy(run <= 3 * tun.weather.kinds[kind].days[2], "no endless " .. kind)
    T.truthy(kind ~= "storm" or run == 1, "a storm does not follow a storm")
  end
end)

T.test("weather: the transition table steers what follows what", function()
  local counts = { clear = {}, rain = {} }
  for seed = 1, 40 do
    local world = newWorld(seed)
    local list = kinds(world, SPRING, SPRING + 80)
    for n = 1, #list - 1 do
      local after = counts[list[n]]
      if after and list[n] ~= list[n + 1] then
        after[list[n + 1]] = (after[list[n + 1]] or 0) + 1
      end
    end
  end
  T.truthy((counts.clear.cloudy or 0) > (counts.clear.storm or 0), "a clear spell gives way to cloud, rarely to storm")
  T.truthy((counts.rain.cloudy or 0) > (counts.rain.windy or 0), "rain clears through cloud")
end)

-- Forecast ----------------------------------------------------------------------------------

T.test("weather: the outlook is exact and its horizon grows with weather sense", function()
  local world = newWorld(4)
  gotoDay(world, 5)
  local outlook = Weather.outlook(world)
  T.eq(#outlook, tun.weather.forecastHorizon + 1)
  T.eq(outlook[1].kind, Weather.kind(world))
  local expected = {}
  for _, entry in ipairs(outlook) do
    expected[entry.offset] = entry.kind
  end
  for offset = 1, tun.weather.forecastHorizon do
    gotoDay(world, 5 + offset)
    T.eq(Weather.kind(world), expected[offset], "forecast for +" .. offset .. " came true")
  end
  world.state.perksApplied = world.state.perksApplied or {}
  local before = Weather.forecastHorizon(world)
  tun.weather.forecastHorizon = before + 2
  T.eq(Weather.forecastHorizon(world), before + 2)
  tun.weather.forecastHorizon = before
end)

T.test("weather: a changed day announces itself", function()
  local world = newWorld(2)
  local seen = {}
  world.events:on("weather.changed", function(e)
    seen[#seen + 1] = e
  end)
  local list = kinds(world, 1, 30)
  local changes = 0
  for n = 2, #list do
    if list[n] ~= list[n - 1] then
      changes = changes + 1
    end
  end
  T.truthy(changes > 0)
  T.eq(#seen, changes)
end)

-- Crops, cistern, routine ---------------------------------------------------------------------

local function plantOne(world)
  local grid = world.state.grid
  for i = 1, #grid.terrain do
    if Grid.terrain(world, i).tillable and not world.occupancy[i] then
      world.state.fields.tilled[i] = true
      world.state.fields.plan[i] = "radish"
      world.state.crops[i] = { id = "radish", growth = 0.1, moisture = 0 }
      return i
    end
  end
end

T.test("weather: rain waters every crop for free, clear skies do not", function()
  local world = newWorld(1)
  gotoDay(world, SPRING)
  local i = plantOne(world)
  force(world, "clear")
  world:tick(STEP)
  T.eq(world.state.crops[i].moisture, 0)
  force(world, "rain")
  world:tick(STEP)
  T.near(world.state.crops[i].moisture, 1, 0.01)
  T.falsy(Crops.needsWater(world.state.crops[i]))
end)

T.test("weather: no rain on frozen ground", function()
  local world = newWorld(1)
  gotoDay(world, WINTER)
  force(world, "rain")
  T.falsy(Weather.isRaining(world))
  T.eq(Weather.rainfall(world), 0)
end)

T.test("weather: the routine does not haul or water by hand in the rain", function()
  local world = newWorld(1)
  gotoDay(world, SPRING)
  local i = plantOne(world)
  local actor = require("src.sim.systems.actors").homesteader(world)
  local function candidates(task)
    local list = {}
    require("src.sim.systems.tasks").get(world, task).candidates(world, actor, function(tile)
      list[#list + 1] = tile
    end)
    return list
  end
  force(world, "clear")
  actor.bucket = 1
  T.eq(candidates("water_crop")[1], i, "thirsty crop is work on a clear day")
  actor.bucket = 0
  T.truthy(#candidates("fetch_water") > 0, "so is filling the bucket")
  force(world, "rain")
  actor.bucket = 1
  T.eq(#candidates("water_crop"), 0)
  actor.bucket = 0
  T.eq(#candidates("fetch_water"), 0)
end)

local function cisternWorld()
  local world = newWorld(1)
  gotoDay(world, SPRING)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, "cistern", i) then
      best, bestDist = i, d
    end
  end
  Inventory.addObject(world, "cistern")
  T.truthy(Inventory.place(world, "cistern", best))
  return world
end

T.test("weather: rain tops up the cistern, up to its capacity", function()
  local world = cisternWorld()
  local hour = tun.time.dayLength / 24
  force(world, "clear")
  for _ = 1, math.floor(hour / STEP) do
    world:tick(STEP)
  end
  T.eq(Ledger.get(world, "water"), 0, "dry weather adds nothing")
  force(world, "rain")
  for _ = 1, math.floor(hour / STEP) do
    world:tick(STEP)
  end
  T.near(Ledger.get(world, "water"), tun.weather.rainWaterRate, 1, "an hour of rain")
  T.eq(Water.stats(world).rained > 0, true)
  local before = Ledger.get(world, "water")
  force(world, "storm")
  for _ = 1, math.floor(hour / STEP) do
    world:tick(STEP)
  end
  T.truthy(Ledger.get(world, "water") - before > tun.weather.rainWaterRate, "a storm gathers more")
  Ledger.add(world, "water", 1000)
  T.eq(Ledger.get(world, "water"), Ledger.capacity(world, "water"), "the cistern fills but never overflows")
end)

T.test("weather: with no cistern the rain has nowhere to go", function()
  local world = newWorld(1)
  gotoDay(world, SPRING)
  force(world, "rain")
  for _ = 1, 100 do
    world:tick(STEP)
  end
  T.eq(Ledger.get(world, "water"), 0)
end)

-- Power ---------------------------------------------------------------------------------------

local function placeSource(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best))
end

local function clearPanels(world)
  for anchor, obj in pairs(world.state.grid.objects) do
    if world.registry:get("objects", obj.id).source then
      Grid.removeObject(world, anchor)
    end
  end
end

T.test("weather: cloud cuts solar, wind lifts turbines, rain swells the hydro", function()
  local function output(id, kind, tweak)
    local world = newWorld(1)
    clearPanels(world)
    placeSource(world, id)
    setTime(world, SPRING, 12)
    force(world, kind)
    if tweak then
      tweak(world)
    end
    world:tick(STEP)
    return Power.output(world)
  end
  local clear = output("solar_array", "clear")
  T.truthy(clear > 0)
  T.near(output("solar_array", "cloudy"), clear * (1 - tun.weather.kinds.cloudy.cloud), clear * 0.01)
  T.near(output("solar_array", "storm"), clear * (1 - tun.weather.kinds.storm.cloud), clear * 0.01)

  local function pin(world)
    local wind = world.state.power.wind
    wind.value, wind.target, wind.hour = 0.5, 0.5, 12
  end
  local calm = output("wind_turbine", "clear", pin)
  T.truthy(calm > 0)
  T.near(output("wind_turbine", "windy", pin), calm * tun.weather.kinds.windy.wind, calm * 0.01)

  local creek = output("micro_hydro", "clear")
  T.near(output("micro_hydro", "rain"), creek * tun.weather.kinds.rain.flow, creek * 0.01 + 1e-9)
end)

-- Fishing -------------------------------------------------------------------------------------

T.test("weather: fish are livelier in the rain and sulk in a storm", function()
  local world = newWorld(1)
  gotoDay(world, SPRING)
  force(world, "clear")
  T.eq(Fishing.activity(world), 1)
  force(world, "rain")
  T.truthy(Fishing.activity(world) > 1)
  force(world, "storm")
  T.truthy(Fishing.activity(world) < 1)
end)

T.test("weather: livelier fish bite sooner", function()
  local fish = reg:all("fish")[1]
  local function wait(activity)
    return Model.new({ fish = fish, tuning = tun.fishing, rng = Rng.new(7), activity = activity }).timer
  end
  local normal = wait(1)
  T.near(wait(2), normal / 2, 1e-9)
  T.truthy(wait(0.5) > normal)
  T.eq(wait(nil), normal)
end)

-- Hooks ---------------------------------------------------------------------------------------

T.test("weather: the threat hook and wind hook read today's kind", function()
  local world = newWorld(1)
  gotoDay(world, SPRING)
  force(world, "storm")
  T.eq(Weather.threat(world), tun.weather.kinds.storm.threat)
  T.eq(Weather.windStrength(world), tun.weather.kinds.storm.wind)
  force(world, "clear")
  T.eq(Weather.threat(world), tun.weather.kinds.clear.threat)
end)

-- Saves ---------------------------------------------------------------------------------------

T.test("weather: the sky survives a save round-trip and carries on the same", function()
  local world = newWorld(8)
  kinds(world, 1, 6)
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.same(restored.state.weather.sky, world.state.weather.sky)
  T.same(kinds(restored, 7, 40), kinds(world, 7, 40))
end)

T.test("weather: a save from before day-to-day weather gets a sky starting today", function()
  local world = newWorld(8)
  setTime(world, SUMMER + 2, 9)
  local state = serialize.decode(serialize.encode(world.state))
  state.weather.sky = nil
  local old = World.new({ registry = reg, tuning = tun }, state)
  T.truthy(old.state.weather.sky)
  T.eq(old.state.weather.sky.first, SUMMER + 2)
  T.eq(Weather.kind(old), tun.weather.startKind)
  T.eq(#old.state.weather.sky.days, tun.weather.queueDays)
  world = nil
end)
