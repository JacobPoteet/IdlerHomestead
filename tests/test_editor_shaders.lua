-- The in-game shader editor's data and the pieces under it (GDD D133): the dither tuning shape, stepping
-- and compare snapshots, the blue-noise tile, and the editor's clock and weather jumps.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")
local BlueNoise = require("src.render.blue_noise")
local Model = require("src.ui.editor_shaders")
local Knobs = require("src.ui.editor_knobs")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")

local reg = Registry.new():loadAll()

-- tuningLoader.load() wraps the shared module tables, so an edit here would leak into every later test:
-- hand out the tuning with the dither values put back when the test file is done with each test.
local pristine
local function newTuning()
  local tun = tuningLoader.load()
  pristine = pristine or Model.snapshot(tun)
  Model.apply(tun, pristine)
  return tun
end

local function newWorld(tun)
  return World.new({ registry = reg, tuning = tun }, World.newState(1))
end

T.test("every dither effect in tuning is listed in the editor, and every listed one exists", function()
  local d = newTuning().visuals.dither
  local listed = {}
  for _, entry in ipairs(Model.ENTRIES) do
    listed[entry.id] = true
    T.truthy(rawget(d, entry.id), "editor lists " .. entry.id .. " but tuning has no such effect")
  end
  for id, value in pairs(d) do
    if type(value) == "table" and id ~= "algorithms" then
      T.truthy(listed[id], "tuning.visuals.dither." .. id .. " is missing from the editor's ENTRIES")
    end
  end
end)

T.test("every effect names a known algorithm and has values inside the editor's limits", function()
  local d = newTuning().visuals.dither
  local known = {}
  for _, name in ipairs(d.algorithms) do
    known[name] = true
  end
  T.falsy(known.bands, "plain bands are not a dither pattern")
  for _, entry in ipairs(Model.ENTRIES) do
    local cfg = d[entry.id]
    T.truthy(known[cfg.algorithm], entry.id .. ": unknown algorithm " .. tostring(cfg.algorithm))
    for _, field in ipairs(Model.fields(cfg)) do
      if field ~= "algorithm" then
        local f = Model.FIELDS[field]
        T.truthy(
          cfg[field] >= f.min and cfg[field] <= f.max,
          entry.id .. "." .. field .. " is outside the editor's range"
        )
      end
    end
  end
end)

T.test("change cycles the algorithm and stops numbers at their limits", function()
  local tun = newTuning()
  local d = tun.visuals.dither
  local count = #d.algorithms
  local start = d.light.algorithm
  for _ = 1, count do
    T.truthy(Model.change(tun, "light", "algorithm", 1))
  end
  T.eq(d.light.algorithm, start, "a full turn comes back")
  d.light.steps = 16
  T.eq(Model.change(tun, "light", "steps", 1), nil, "steps stop at the top")
  d.light.amount = 0.9
  T.near(Model.change(tun, "light", "amount", 1), 0.95, 1e-9)
  T.near(Model.change(tun, "light", "amount", 1), 1, 1e-9)
  T.eq(Model.change(tun, "light", "amount", 1), nil, "amount stops at 1")
  d.light.scale = 1
  T.eq(Model.change(tun, "light", "scale", -1), nil, "cell size stops at 1")
end)

T.test("snapshot, apply and changed track what the editor edited", function()
  local tun = newTuning()
  local snap = Model.snapshot(tun)
  T.eq(#Model.changedIds(tun, snap), 0)
  Model.change(tun, "shadows", "algorithm", 1)
  Model.change(tun, "clouds", "steps", 1)
  local ids = Model.changedIds(tun, snap)
  T.eq(table.concat(ids, ","), "shadows,clouds")
  Model.apply(tun, snap)
  T.eq(#Model.changedIds(tun, snap), 0, "apply puts the saved values back")
end)

T.test("export writes Lua that loads back to the same values", function()
  local tun = newTuning()
  local snap = Model.snapshot(tun)
  Model.change(tun, "heat", "algorithm", 1)
  Model.change(tun, "light", "steps", -1)
  local text = Model.export(tun)
  local chunk = assert(loadstring("return {" .. text .. "\n}"))
  local back = chunk()
  for _, entry in ipairs(Model.ENTRIES) do
    for _, field in ipairs(Model.fields(tun.visuals.dither[entry.id])) do
      T.near(
        type(back[entry.id][field]) == "number" and back[entry.id][field] or 0,
        type(tun.visuals.dither[entry.id][field]) == "number" and tun.visuals.dither[entry.id][field] or 0,
        1e-9
      )
    end
  end
  T.eq(back.heat.algorithm, tun.visuals.dither.heat.algorithm)
  T.truthy(Model.export(tun, snap):find("heat", 1, true), "the changed effect is exported")
  T.falsy(Model.export(tun, snap):find("sunbeams", 1, true), "only the changed effects")
  Model.apply(tun, snap)
end)

T.test("blue noise ranks each texel once, the same every run, and keeps the sparse points apart", function()
  local size = 16
  local ranks = BlueNoise.ranks(size)
  local seen = {}
  for i = 1, size * size do
    T.truthy(ranks[i] and ranks[i] >= 0 and ranks[i] < size * size and not seen[ranks[i]], "ranks are a permutation")
    seen[ranks[i]] = true
  end
  local again = BlueNoise.ranks(size)
  for i = 1, size * size do
    T.eq(again[i], ranks[i], "the tile does not change between runs")
  end
  -- The lowest tenth of the ranks is what a 10% threshold lights: no two of those may touch.
  local low = {}
  for i = 1, size * size do
    if ranks[i] < size * size * 0.1 then
      low[#low + 1] = { (i - 1) % size, math.floor((i - 1) / size) }
    end
  end
  for a = 1, #low do
    for b = a + 1, #low do
      local dx = math.min(math.abs(low[a][1] - low[b][1]), size - math.abs(low[a][1] - low[b][1]))
      local dy = math.min(math.abs(low[a][2] - low[b][2]), size - math.abs(low[a][2] - low[b][2]))
      T.truthy(dx > 1 or dy > 1, "two of the sparsest points are neighbours")
    end
  end
end)

T.test("Calendar.skipTo only moves forward, to the hour and season asked for", function()
  local tun = newTuning()
  local world = newWorld(tun)
  local before = world.state.calendar.elapsed
  local now = Calendar.skipTo(world, 22)
  T.near(now.hour, 22, 1e-6)
  T.truthy(world.state.calendar.elapsed > before)
  local later = Calendar.skipTo(world, 12) -- noon is behind us today: it is tomorrow's
  T.near(later.hour, 12, 1e-6)
  T.truthy(later.day > now.day)
  local summer = Calendar.skipTo(world, 6, 2)
  T.eq(summer.season, "summer")
  T.eq(summer.dayOfSeason, tun.time.skipDayOfSeason)
  local spring = Calendar.skipTo(world, 6, 1) -- spring is behind us: next year's
  T.eq(spring.season, "spring")
  T.eq(spring.year, summer.year + 1)
end)

T.test("Weather.force sets every queued day, and rain in a frozen season becomes snow weather", function()
  local tun = newTuning()
  local world = newWorld(tun)
  Weather.force(world, "storm")
  T.eq(Weather.kind(world), "storm")
  for _, kind in ipairs(world.state.weather.sky.days) do
    T.eq(kind, "storm")
  end
  Calendar.skipTo(world, 12, 4) -- winter
  Weather.force(world, "rain")
  T.eq(Weather.kind(world), tun.weather.frozenRainKind)
  T.falsy(pcall(Weather.force, world, "no-such-weather"))
end)

T.test("the editor tests leave the shared dither tuning as they found it", function()
  local tun = tuningLoader.load()
  Model.apply(tun, pristine)
  T.eq(#Model.changedIds(tun, pristine), 0)
end)

T.test("every wind knob exists in tuning and sits inside its own range", function()
  local tun = newTuning()
  for _, k in ipairs(Knobs.all(Knobs.WIND)) do
    local v = Knobs.get(tun, k)
    T.truthy(type(v) == "number", table.concat(k.path, ".") .. " is a number")
    T.truthy(v >= k.min and v <= k.max, table.concat(k.path, ".") .. " is outside the editor's range")
  end
end)

T.test("knob steps stop at the limits, snapshot and apply put values back, export lists only changes", function()
  local tun = newTuning()
  local groups = Knobs.WIND
  local snap = Knobs.snapshot(tun, groups)
  local k = groups[1].knobs[1]
  local original = Knobs.get(tun, k)
  T.truthy(Knobs.change(tun, k, 1))
  T.truthy(Knobs.changed(tun, groups, snap))
  T.truthy(Knobs.export(tun, groups, snap):find(k.label, 1, true))
  T.falsy(Knobs.export(tun, groups, snap):find("\n", 1, true), "one changed knob is one line")
  Knobs.apply(tun, groups, snap)
  T.eq(Knobs.get(tun, k), original)
  T.falsy(Knobs.changed(tun, groups, snap))
  for _ = 1, 400 do
    if not Knobs.change(tun, k, 1) then
      break
    end
  end
  T.eq(Knobs.get(tun, k), k.max)
  T.eq(Knobs.change(tun, k, 1), nil)
  Knobs.apply(tun, groups, snap)
end)

T.test("invincible: no hunger or cold lowers Condition while the editor holds it", function()
  local tun = newTuning()
  local world = newWorld(tun)
  for _, res in ipairs(reg:all("resources")) do
    Ledger.remove(world, res.id, Ledger.get(world, res.id), "test")
  end
  local before = Needs.condition(world)
  Needs.eat(world)
  T.truthy(Needs.condition(world) < before, "an empty larder hurts a normal game")
  Needs.setInvincible(world, true)
  local held = Needs.condition(world)
  Needs.eat(world)
  Needs.warm(world)
  T.eq(Needs.condition(world), held, "nothing hurts while invincible")
  Needs.setInvincible(world, false)
  Needs.eat(world)
  T.truthy(Needs.condition(world) < held, "and it hurts again after")
end)

T.test("a wind override beats the weather until it is let go", function()
  local tun = newTuning()
  local world = newWorld(tun)
  local weather = Weather.windStrength(world)
  Weather.setWindOverride(world, 0)
  T.eq(Weather.windStrength(world), 0, "zero is a real override, not unset")
  Weather.setWindOverride(world, 2.5)
  T.eq(Weather.windStrength(world), 2.5)
  Weather.setWindOverride(world, nil)
  T.eq(Weather.windStrength(world), weather)
end)
