-- Routine v2: priority thresholds (GDD §7.4, D66, issue #43). A category with a condition is skipped
-- by the idle routine while the condition is not met; orders and machines are unaffected.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Rules = require("src.sim.routine_rules")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 2))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
  end
end

local function onlyCategory(world, category)
  for _, e in ipairs(world.state.priorities) do
    e.enabled = e.category == category
  end
end

local function entry(state, category)
  for _, e in ipairs(state.priorities) do
    if e.category == category then
      return e
    end
  end
end

local function reload(world)
  return World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
end

-- Content ---------------------------------------------------------------------------------------

T.test("routine conditions content: kinds are well formed and match tuning", function()
  local list = reg:all("routine_conditions")
  T.truthy(#list >= 5)
  for _, def in ipairs(list) do
    T.truthy(def.min <= def.default and def.default <= def.max, def.id .. " default in range")
    T.truthy(def.step > 0 and def.short:find("%%s"), def.id)
    T.truthy(def.cmp == "below" or def.cmp == "atleast" or def.cmp == "is", def.id)
    if def.measure == "stock" then
      for _, id in ipairs(def.resources) do
        T.truthy(reg:has("resources", id), def.id .. " reads " .. id)
      end
    end
    if def.measure == "seasonIndex" then
      T.eq(def.max, #tun.time.seasons)
    end
  end
end)

-- Defaults ---------------------------------------------------------------------------------------

T.test("thresholds: a new run ships no conditions, so unattended play is as before (D66)", function()
  local world = newWorld()
  for _, e in ipairs(world.state.priorities) do
    T.eq(e.cond, nil, e.category)
    T.truthy(Tasks.conditionMet(world, e.category))
  end
end)

-- Skip and resume -------------------------------------------------------------------------------

T.test("thresholds: the routine skips a category until its condition holds again", function()
  local world = newWorld()
  world.control = "idle"
  onlyCategory(world, "fuel")
  setTime(world, 1, 8)
  Ledger.add(world, "wood", 20)
  Ledger.add(world, "firewood", 5)
  entry(world.state, "fuel").cond = { kind = "firewood_below", value = 5 }
  T.falsy(Tasks.conditionMet(world, "fuel"))
  local hs = Actors.homesteader(world)
  T.eq(Tasks.chooseIdleJob(world, hs), nil, "stock at the threshold: nothing to do")
  run(world, HOUR * 2)
  T.eq(Ledger.get(world, "wood"), 20, "no wood was split while waiting")
  Tasks.stepCondition(world, "fuel", 1) -- raise the threshold: stock is now below it
  T.truthy(Tasks.conditionMet(world, "fuel"))
  run(world, HOUR * 3)
  T.truthy(Ledger.get(world, "wood") < 20, "work resumes once below the threshold")
end)

T.test("thresholds: a waiting category is skipped for the next one, and orders still work", function()
  local world = newWorld()
  onlyCategory(world, "fuel")
  entry(world.state, "fuel").cond = { kind = "wood_below", value = 5 }
  Ledger.add(world, "wood", 20)
  local hs = Actors.homesteader(world)
  T.eq(Tasks.chooseIdleJob(world, hs), nil)
  local block
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "chopping_block" then
      block = anchor
    end
  end
  local job = Tasks.jobForOrder(world, hs, block, {})
  T.truthy(job and job.task == "split_wood", "a player order is not held back by the condition")
  for _, e in ipairs(world.state.priorities) do
    e.enabled = true
  end
  local other = Tasks.chooseIdleJob(world, hs)
  T.truthy(other == nil or other.task ~= "split_wood", "the routine falls through to other categories")
end)

T.test("thresholds: each condition kind reads its measure", function()
  local world = newWorld()
  local function met(kind, value)
    return Rules.met(world, { kind = kind, value = value })
  end
  setTime(world, 1, 10)
  T.truthy(met("hour_after", 10) and not met("hour_after", 11))
  T.truthy(met("hour_before", 11) and not met("hour_before", 10))
  T.truthy(met("season_is", 1) and not met("season_is", 2))
  T.eq(Calendar.now(world).season, tun.time.seasons[1])
  local w = Ledger.get(world, "wood")
  T.truthy(met("wood_below", w + 5) and not met("wood_below", w))
  local days = Needs.foodDays(world)
  T.eq(met("food_days_below", 10), days < 10)
  T.eq(met("food_days_atleast", 10), days >= 10)
  Ledger.add(world, "potato", 20) -- plenty of food
  T.truthy(Needs.foodDays(world) > days)
  T.truthy(met("food_days_atleast", math.floor(days) + 1))
  local f0 = Ledger.get(world, "firewood") + Ledger.get(world, "seasoned_firewood")
  Ledger.add(world, "firewood", 4)
  Ledger.add(world, "seasoned_firewood", 3)
  T.truthy(met("firewood_below", f0 + 8) and not met("firewood_below", f0 + 7), "green and seasoned count together")
  T.truthy(Rules.met(world, nil), "no condition is always met")
end)

T.test("thresholds: stepper clamps, kinds cycle through content and back to always", function()
  local world = newWorld()
  Tasks.setCondition(world, "fish", "food_days_below")
  local def = reg:get("routine_conditions", "food_days_below")
  T.eq(Tasks.condition(world, "fish").value, def.default)
  for _ = 1, 200 do
    Tasks.stepCondition(world, "fish", 1)
  end
  T.eq(Tasks.condition(world, "fish").value, def.max)
  for _ = 1, 200 do
    Tasks.stepCondition(world, "fish", -1)
  end
  T.eq(Tasks.condition(world, "fish").value, def.min)
  Tasks.setCondition(world, "fish", nil)
  T.eq(Tasks.condition(world, "fish"), nil)
  local presses = 0
  repeat
    Tasks.cycleCondition(world, "fish")
    presses = presses + 1
  until Tasks.condition(world, "fish") == nil or presses > 50
  T.eq(presses, #reg:all("routine_conditions") + 1)
  Tasks.stepCondition(world, "fish", 1) -- no condition: harmless
  T.eq(Rules.describe(world, nil), "always")
  Tasks.setCondition(world, "fish", "season_is")
  T.eq(Rules.describe(world, Tasks.condition(world, "fish")), "only in Spring")
end)

-- Saves --------------------------------------------------------------------------------------------

T.test("thresholds: conditions survive a save and the loaded list is identical", function()
  local world = newWorld()
  Tasks.setCondition(world, "fish", "hour_before")
  Tasks.stepCondition(world, "fish", -1)
  local loaded = reload(world)
  T.eq(Tasks.condition(loaded, "fish").kind, "hour_before")
  T.eq(serialize.encode(loaded.state.priorities), serialize.encode(world.state.priorities))
end)

T.test("thresholds: a save from before thresholds keeps no conditions", function()
  local world = newWorld()
  local state = serialize.decode(serialize.encode(world.state))
  for _, e in ipairs(state.priorities) do
    e.cond = nil -- the older shape: no thresholds anywhere
  end
  local old = World.new({ registry = reg, tuning = tun }, state)
  for _, e in ipairs(old.state.priorities) do
    T.eq(e.cond, nil, e.category .. " stays unconditional")
  end
  T.truthy(Tasks.conditionMet(old, "fuel"))
  -- It plays exactly like a world that never had the field: same seed, same run.
  local function play(w)
    w.control = "idle"
    Ledger.add(w, "wood", 30)
    run(w, HOUR * 12)
    return serialize.encode(w.state)
  end
  T.eq(play(old), play(newWorld()))
end)

T.test("thresholds: a bad saved condition is dropped or clamped, never a crash", function()
  local world = newWorld()
  local state = serialize.decode(serialize.encode(world.state))
  entry(state, "fish").cond = { kind = "no_such_kind", value = 3 }
  entry(state, "harvest").cond = { kind = "wood_below", value = 9999 }
  local loaded = World.new({ registry = reg, tuning = tun }, state)
  T.eq(entry(loaded.state, "fish").cond, nil)
  T.eq(entry(loaded.state, "harvest").cond.value, reg:get("routine_conditions", "wood_below").max)
end)

-- Determinism -----------------------------------------------------------------------------------

T.test("thresholds: the same seed and conditions give the same run", function()
  local function play()
    local world = newWorld(5)
    world.control = "idle"
    entry(world.state, "fuel").cond = { kind = "firewood_below", value = 10 }
    entry(world.state, "harvest").cond = { kind = "hour_before", value = 14 }
    entry(world.state, "water").cond = { kind = "food_days_atleast", value = 3 }
    Ledger.add(world, "wood", 30)
    run(world, HOUR * 36)
    return serialize.encode(world.state)
  end
  T.eq(play(), play())
end)

-- Starter plan ----------------------------------------------------------------------------------------

T.test("thresholds: the starter field is planned even when every category is waiting", function()
  local world = newWorld(1)
  for _, e in ipairs(world.state.priorities) do
    e.cond = { kind = "hour_after", value = 23 }
  end
  setTime(world, 1, 9)
  world.control = "idle"
  world:tick(STEP)
  local n = 0
  for _ in pairs(world.state.fields.plan) do
    n = n + 1
  end
  T.truthy(n > 0, "planning is the routine's own step, not a category")
  T.eq(Tasks.chooseIdleJob(world, Actors.homesteader(world)), nil, "but every category waits for 23:00")
end)
