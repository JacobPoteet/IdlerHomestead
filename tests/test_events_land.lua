-- The land events pack (B8, D193, docs/PLAN_DEPTH.md §6.2, data/content/events.lua): livestock in the field, late frost and
-- the storm-felled tree. Each event's triggers, its two options and its free ignore, and that nothing shrinks the farm.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Events = require("src.sim.systems.events")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Status = require("src.sim.systems.status")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local LAND = { "livestock_in_field", "late_frost", "storm_tree" }

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function tick(world, n)
  for _ = 1, n or 1 do
    world:tick(STEP)
  end
end

-- Days: spring 1-7, summer 8-14, autumn 15-21, winter 22-28 (daysPerSeason 7).
local SPRING, SUMMER, AUTUMN, WINTER = 5, 10, 16, 25

local function plant(world, count, growth)
  for i = 1, count do
    world.state.crops[i] = { id = "radish", growth = growth or 0.6, moisture = 0, thirst = 0 }
  end
end

local function growths(world)
  local out = {}
  for i = 1, 10 do
    local crop = world.state.crops[i]
    if crop then
      out[#out + 1] = crop.growth
    end
  end
  return out
end

local function answer(world, id, how)
  Ledger.add(world, "wood", 10)
  world.state.events.budget.day = 0
  T.truthy(Events.force(world, id), "the card opens")
  if how == "ignore" then
    T.truthy(Events.ignore(world))
  else
    T.truthy(Events.choose(world, how))
  end
end

T.test("land events: clean two-option content with a free, non-escalating ignore and a note", function()
  local world = newWorld()
  T.same(Events.audit(world), {}, "the audit finds nothing: " .. table.concat(Events.audit(world), "; "))
  for _, id in ipairs(LAND) do
    local d = reg:get("events", id)
    T.eq(d.class, "land", id)
    T.eq(d.options[1].careful, true, id)
    T.eq(d.options[2].bold, true, id)
    T.eq(d.ignore.cost, nil, id)
    T.eq(d.ignore.effect.later, nil, id)
    T.eq(d.ignore.effect.damageTiles, nil, id)
    T.truthy(d.journalNote and reg:has("notes", d.journalNote), id)
    for _, o in ipairs({ d.options[1], d.options[2], d.ignore }) do
      T.falsy(o.risk:find("%d") or o.risk:find("%%"), id .. ": the risk is in words: " .. o.risk)
    end
    local fresh = newWorld()
    plant(fresh, 3)
    Events.force(fresh, id)
    T.truthy(Journal.hasNote(fresh, d.journalNote), id)
  end
end)

T.test("land events: the whole pack ignored costs a day of slightly slower work and no crop or Condition", function()
  for _, id in ipairs(LAND) do
    local world = newWorld()
    setTime(world, SPRING, 8)
    plant(world, 4)
    world.state.needs.condition = 90
    local before = growths(world)
    Events.force(world, id)
    Events.ignore(world)
    T.eq(Needs.condition(world), 90, id)
    T.same(growths(world), before, id)
    for _, s in ipairs(Status.active(world)) do
      T.eq(reg:get("statuses", s.id).escalatesTo, nil, id .. " " .. s.id)
    end
    T.eq(#world.state.events.delayed, 0, id)
    T.eq(#Events.openDamage(world), 0, id)
  end
end)

T.test("livestock in the field: needs a planted crop and a growing season", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  T.eq(Events.weight(world, "livestock_in_field"), 0, "nothing in the ground to eat")
  plant(world, 3)
  T.truthy(Events.weight(world, "livestock_in_field") > 0)
  setTime(world, SUMMER, 13)
  T.truthy(Events.weight(world, "livestock_in_field") > 0)
  setTime(world, AUTUMN, 13)
  T.truthy(Events.weight(world, "livestock_in_field") > 0)
  setTime(world, WINTER, 13)
  T.eq(Events.weight(world, "livestock_in_field"), 0, "no cow in a winter field")
end)

T.test(
  "livestock in the field: chasing it off costs an hour, grazing sets two rows back, ignoring is a mild day",
  function()
    local world = newWorld()
    setTime(world, SPRING, 13)
    plant(world, 5, 0.6)
    answer(world, "livestock_in_field", 1)
    T.truthy(Status.has(world, "tending"))
    T.same(growths(world), { 0.6, 0.6, 0.6, 0.6, 0.6 }, "the crops are untouched")

    local graze = newWorld()
    setTime(graze, SPRING, 13)
    plant(graze, 5, 0.6)
    answer(graze, "livestock_in_field", 2)
    local nibbled = 0
    for _, g in ipairs(growths(graze)) do
      if g < 0.6 then
        nibbled = nibbled + 1
        T.near(g, 0.35, 1e-9)
      end
    end
    T.eq(nibbled, 2, "two rows are set back, none lost")
    T.eq(Status.count(graze), 0)
    T.eq(#graze.state.events.delayed, 0)

    local ignored = newWorld()
    setTime(ignored, SPRING, 13)
    plant(ignored, 5, 0.6)
    answer(ignored, "livestock_in_field", "ignore")
    T.near(Status.modifier(ignored, "workSpeed"), 0.95, 1e-9)
    T.same(growths(ignored), { 0.6, 0.6, 0.6, 0.6, 0.6 })
  end
)

T.test("late frost: spring and autumn with a crop in the ground; smudge fires cost wood and save the rows", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  T.eq(Events.weight(world, "late_frost"), 0, "no crops, no frost to fear")
  plant(world, 4, 0.5)
  T.truthy(Events.weight(world, "late_frost") > 0)
  setTime(world, SUMMER, 21.5)
  T.eq(Events.weight(world, "late_frost"), 0, "not in summer")
  setTime(world, AUTUMN, 21.5)
  T.truthy(Events.weight(world, "late_frost") > 0)
  setTime(world, SPRING, 21.5)
  local wood = Ledger.get(world, "wood")
  answer(world, "late_frost", 1)
  T.eq(Ledger.get(world, "wood"), wood + 10 - 2)
  T.truthy(Status.has(world, "tending"))
  T.eq(#world.state.events.delayed, 0)
  setTime(world, SPRING + 1, 8)
  tick(world)
  T.same(growths(world), { 0.5, 0.5, 0.5, 0.5 })
end)

T.test("late frost: trusting the sprouts may set three rows back at dawn, and never loses a crop", function()
  local nipped, spared = 0, 0
  for seed = 1, 30 do
    local world = newWorld(seed)
    setTime(world, SPRING, 21.5)
    plant(world, 5, 0.5)
    answer(world, "late_frost", 2)
    T.eq(#world.state.events.delayed, 1, "a roll waits for dawn")
    T.same(growths(world), { 0.5, 0.5, 0.5, 0.5, 0.5 }, "nothing happens tonight")
    setTime(world, SPRING + 1, 6)
    tick(world)
    local cut = 0
    for _, g in ipairs(growths(world)) do
      if g < 0.5 then
        cut = cut + 1
        T.near(g, 0.2, 1e-9)
      end
    end
    for i = 1, 5 do
      T.truthy(world.state.crops[i], "no crop is lost")
    end
    if cut > 0 then
      T.eq(cut, 3)
      nipped = nipped + 1
    else
      spared = spared + 1
    end
  end
  T.truthy(nipped > 0 and spared > 0, "a gamble: both outcomes happen across seeds")
end)

T.test("late frost: ignoring puts sacks over a few and costs a mild day", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  plant(world, 4, 0.5)
  answer(world, "late_frost", "ignore")
  T.near(Status.modifier(world, "workSpeed"), 0.95, 1e-9)
  T.eq(#world.state.events.delayed, 0, "no roll, no loss")
end)

T.test("storm-felled tree: drawn only after wind; the easy branches are free wood", function()
  local world = newWorld()
  setTime(world, SPRING, 8)
  Weather.force(world, "clear")
  T.eq(Events.weight(world, "storm_tree"), 0, "needs a windy night to draw")
  Weather.force(world, "windy")
  T.truthy(Events.weight(world, "storm_tree") > 0)
  Weather.force(world, "clear")
  local wood = Ledger.get(world, "wood")
  answer(world, "storm_tree", 1)
  T.eq(Ledger.get(world, "wood"), wood + 10 + 2)
  T.eq(Status.count(world), 0)
  T.eq(#world.state.events.delayed, 0)
end)

T.test("storm-felled tree: bucking it whole gains more wood for an hour and a small chance of a slip", function()
  local slipped, clean = 0, 0
  for seed = 1, 60 do
    local world = newWorld(seed)
    setTime(world, SPRING, 8)
    local wood = Ledger.get(world, "wood")
    answer(world, "storm_tree", 2)
    T.eq(Ledger.get(world, "wood"), wood + 10 + 5)
    T.truthy(Status.has(world, "tending"))
    T.eq(#world.state.events.delayed, 1)
    setTime(world, SPRING, 10)
    tick(world)
    if Status.has(world, "ankle_1") then
      slipped = slipped + 1
    else
      clean = clean + 1
    end
  end
  T.truthy(slipped > 0 and clean > slipped, "a slip is the exception")
end)

T.test("storm-felled tree: ignoring leaves it, with nothing lost; a bad ankle keeps it away", function()
  local world = newWorld()
  setTime(world, SPRING, 8)
  local wood = Ledger.get(world, "wood")
  answer(world, "storm_tree", "ignore")
  T.eq(Ledger.get(world, "wood"), wood + 10)
  T.eq(Status.count(world), 0)
  local hurt = newWorld()
  setTime(hurt, SPRING, 8)
  Weather.force(hurt, "windy")
  Status.apply(hurt, "ankle_1")
  T.eq(Events.weight(hurt, "storm_tree"), 0)
end)
