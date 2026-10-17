-- The goal ladder and the Progress panel (D163, #342, #276): the run milestone tracker (events, matches, counts, run
-- state, save), the pressing goal (Tonight until Footing, Footing, then the winter), the line's and the panel's words,
-- the gates, and the P key.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Goal = require("src.sim.systems.goal")
local GoalText = require("src.ui.goal_text")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Milestones = require("src.sim.systems.milestones")
local Readiness = require("src.sim.systems.readiness")
local KeyBindings = require("src.core.key_bindings")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.night.footing

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

-- A world in autumn with a campfire placed, at noon.
local function autumnWorld(seed, meta)
  local world = newWorld(seed, meta)
  setTime(world, 2 * tun.time.daysPerSeason + 2, 12)
  Inventory.addObject(world, "campfire")
  local truck = world.state.land.truck
  for i = 1, #world.state.grid.terrain do
    if Grid.distance(world.state.grid, truck, i) >= 1 and Inventory.canPlace(world, "campfire", i) then
      T.truthy(Inventory.place(world, "campfire", i))
      break
    end
  end
  return world
end

-- Stock the woodpile, the larder and the water so every row of tonight is fine (`good`) or all are short.
local function stock(world, good)
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Ledger.add(world, "wood", good and 150 or 0)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  if good then
    Ledger.add(world, "canned_food", 6 * tun.needs.dailyCalories / reg:get("resources", "canned_food").calories)
  end
  world.state.needs.canteen = good and tun.needs.canteenCapacity or 0
  Ledger.remove(world, "water", Ledger.get(world, "water"))
end

local function measure(s)
  return #s * 6
end

-- Milestones ---------------------------------------------------------------------------------------------------------

T.test("milestones: the checklist is content, in order, and none is ticked at the start of a run", function()
  local world = newWorld(1)
  local list = Milestones.list(world)
  T.eq(#list, #reg:all("milestones"))
  T.truthy(#list >= 6, "a short checklist, not a long one")
  for _, m in ipairs(list) do
    T.falsy(m.done, m.id)
    T.truthy(m.name and m.hint, m.id .. " has words")
  end
  local done, total = Milestones.tally(world)
  T.eq(done, 0)
  T.eq(total, #list)
end)

T.test("milestones: an event ticks its milestone once, with the day, and says so", function()
  local world = newWorld(1)
  local seen = {}
  world.events:on("milestone.reached", function(e)
    seen[#seen + 1] = e.id
  end)
  world.events:emit("crop.harvested", { crop = "radish", amount = 1 })
  world.events:emit("crop.harvested", { crop = "radish", amount = 1 })
  T.truthy(Milestones.done(world, "first_harvest"))
  T.falsy(Milestones.done(world, "first_sale"))
  T.eq(#seen, 1, "reached once")
  T.eq(seen[1], "first_harvest")
  for _, m in ipairs(Milestones.list(world)) do
    if m.id == "first_harvest" then
      T.truthy(m.done)
      T.eq(m.year, 1)
      T.truthy(m.day >= 1)
      T.truthy(m.season)
    end
  end
  T.eq((Milestones.tally(world)), 1)
end)

T.test("milestones: a match narrows the event, and a list of values means any one of them", function()
  local world = newWorld(1)
  world.events:emit("object.placed", { object = "campfire", tile = 1 })
  T.falsy(Milestones.done(world, "shack"))
  T.falsy(Milestones.done(world, "power"))
  world.events:emit("object.placed", { object = "shack", tile = 1 })
  T.truthy(Milestones.done(world, "shack"))
  T.falsy(Milestones.done(world, "power"))
  world.events:emit("object.placed", { object = "wind_turbine", tile = 2 })
  T.truthy(Milestones.done(world, "power"), "a turbine is power too")
  local other = newWorld(2)
  other.events:emit("object.placed", { object = "solar_array", tile = 2 })
  T.truthy(Milestones.done(other, "power"), "and so is a solar array")
end)

T.test("milestones: a numeric match uses min and max (a second year, not the first)", function()
  local world = newWorld(1)
  world.events:emit("calendar.newSeason", { season = "summer", year = 1 })
  T.falsy(Milestones.done(world, "first_year"))
  world.events:emit("calendar.newSeason", { season = "spring", year = 2 })
  T.truthy(Milestones.done(world, "first_year"))
end)

T.test("milestones: the footing, thaw and Great Winter events tick theirs", function()
  local world = newWorld(1)
  world.events:emit("footing.gained", { day = 12 })
  T.truthy(Milestones.done(world, "footing"))
  world.events:emit("weather.thawed", {})
  T.truthy(Milestones.done(world, "first_winter"))
  world.events:emit("progress.established", { year = 3, run = 1, first = true })
  T.truthy(Milestones.done(world, "great_winter"))
  T.eq((Milestones.tally(world)), 3)
end)

T.test("milestones: a count milestone ticks after its count, and shows progress on the way", function()
  local world = newWorld(1)
  -- Counts are content (`count`); stand one in for the test with a registry entry of the same shape.
  local def = { id = "test_count", name = "Three sales", hint = "Sell three times", event = "market.sold", count = 3 }
  local all = world.registry:all("milestones")
  all[#all + 1] = def
  Milestones.init(world)
  world.events:emit("market.sold", { earnings = 5 })
  local row
  for _, m in ipairs(Milestones.list(world)) do
    if m.id == "test_count" then
      row = m
    end
  end
  T.falsy(row.done)
  T.eq(row.need, 3)
  T.truthy(row.have >= 1)
  world.events:emit("market.sold", { earnings = 5 })
  world.events:emit("market.sold", { earnings = 5 })
  T.truthy(Milestones.done(world, "test_count"))
  all[#all] = nil
end)

T.test("milestones: run state, so a new world starts clean, and it survives a save", function()
  local world = newWorld(1)
  world.events:emit("market.sold", { earnings = 5 })
  T.truthy(Milestones.done(world, "first_sale"))
  local copy = serialize.decode(serialize.encode(world.state.milestones))
  T.truthy(copy.done.first_sale)
  local back = World.new(
    { registry = reg, tuning = tun },
    (function()
      local st = World.newState(1)
      st.milestones = copy
      return st
    end)()
  )
  T.truthy(Milestones.done(back, "first_sale"), "kept through the save")
  T.falsy(Milestones.done(newWorld(1), "first_sale"), "a new run starts without it")
  back.events:emit("market.sold", { earnings = 5 })
  T.eq((Milestones.tally(back)), 1, "ticked once only")
end)

-- The pressing goal --------------------------------------------------------------------------------------------------

T.test("goal: Tonight leads while a row is short and Footing is not held", function()
  local world = autumnWorld(1)
  stock(world, false)
  local goal = Goal.current(world)
  T.eq(goal.kind, "tonight")
  T.truthy(#goal.gaps >= 1)
  T.truthy(goal.level >= 1)
  T.falsy(goal.footing.held)
  T.truthy(GoalText.line(goal):find("Tonight:", 1, true))
end)

T.test("goal: with nothing short the Footing checklist leads, with the nights in a row", function()
  local world = autumnWorld(2)
  stock(world, true)
  local goal = Goal.current(world)
  T.eq(goal.kind, "footing")
  T.eq(goal.level, 0)
  T.eq(goal.footing.total, 4)
  T.eq(goal.footing.okCount, 4)
  world.state.footing.streak = 2
  goal = Goal.current(world)
  local line = GoalText.line(goal)
  T.truthy(line:find("Footing: 4 of 4 held", 1, true), line)
  T.truthy(line:find("night 2 of " .. cfg.streakNights, 1, true), line)
end)

T.test("goal: the line names what Footing still needs", function()
  local world = autumnWorld(3)
  stock(world, true)
  world.state.needs.canteen = 0 -- no water in hand
  local goal = Goal.current(world, { gaps = 0, warmth = { level = 0 }, food = { level = 0 }, water = { level = 0 } })
  T.eq(goal.kind, "footing")
  T.truthy(GoalText.line(goal):find("needs water", 1, true), GoalText.line(goal))
end)

T.test("goal: once Footing is held the winter leads, with days to the freeze and the reserve target", function()
  local world = newWorld(4)
  setTime(world, 3, 12) -- spring, day 3
  world.state.footing.held = true
  local goal = Goal.current(world)
  T.eq(goal.kind, "winter")
  T.falsy(goal.winter.frozen)
  local expected = (#tun.time.seasons - 1) * tun.time.daysPerSeason - 3 + 1
  T.eq(goal.winter.daysAway, expected, "days to the first frozen season")
  local line = GoalText.line(goal)
  T.truthy(line:find("Winter in " .. expected .. " days", 1, true), line)
  T.truthy(line:find("Great Winter in year " .. tun.progress.greatWinterYear, 1, true), line)
end)

T.test("goal: a slip brings Tonight back as the lead, and the way back is the Regain line", function()
  local world = autumnWorld(5)
  world.state.footing.held = true
  stock(world, false)
  world.state.footing.slipped = true
  T.eq(Goal.current(world).kind, "tonight")
  T.truthy(GoalText.line(Goal.current(world)):find("Footing slipped", 1, true))
  stock(world, true)
  local goal = Goal.current(world)
  T.eq(goal.kind, "regain")
  T.truthy(GoalText.line(goal):find("Regain Footing: night 0 of " .. cfg.regainNights, 1, true))
  world.state.footing.slipped = false
  T.eq(Goal.current(world).kind, "winter")
end)

T.test("goal: the Great Winter's status runs ahead, now, survived", function()
  local world = newWorld(6)
  setTime(world, 3, 12)
  T.eq(Goal.current(world).great.state, "ahead")
  T.eq(Goal.current(world).great.yearsAway, tun.progress.greatWinterYear - 1)
  local year = tun.progress.greatWinterYear
  setTime(world, (year - 1) * #tun.time.seasons * tun.time.daysPerSeason + 3 * tun.time.daysPerSeason + 2, 12) -- winter of that year
  T.eq(Goal.current(world).great.state, "now")
  setTime(world, year * #tun.time.seasons * tun.time.daysPerSeason + 2, 12)
  T.eq(Goal.current(world).great.state, "survived")
  T.falsy(Goal.current(world).great.slotEstablished)
  local meta = { established = { run = 1, year = year, seen = true } }
  T.truthy(Goal.current(newWorld(6, meta)).great.slotEstablished)
end)

T.test("goal: it reads the Tonight card's own look, so the two cannot disagree", function()
  local world = autumnWorld(7)
  stock(world, false)
  local look = Readiness.tonight(world)
  local goal = Goal.current(world, look)
  T.eq(#goal.gaps, look.gaps)
end)

-- Words ---------------------------------------------------------------------------------------------------------------

T.test("goal text: the line drops trailing parts to fit, then cuts with an ellipsis", function()
  local world = newWorld(8)
  setTime(world, 3, 12)
  world.state.footing.held = true
  local goal = Goal.current(world)
  local full = GoalText.line(goal)
  T.eq(GoalText.line(goal, nil, measure), full, "no limit, the whole line")
  local fitted = GoalText.line(goal, measure("Winter in 99 days") + 6, measure)
  T.truthy(measure(fitted) <= measure("Winter in 99 days") + 6)
  T.truthy(fitted:find("Winter in", 1, true))
  local cut = GoalText.line(goal, 6 * 6, measure)
  T.truthy(cut:sub(-2) == GoalText.ellipsis)
  T.truthy(measure(cut) <= 6 * 6)
end)

T.test("goal text: the level is the worst of the line's parts", function()
  local world = autumnWorld(9)
  stock(world, false)
  T.truthy(GoalText.level(Goal.current(world)) >= 1)
  stock(world, true)
  T.eq(GoalText.level(Goal.current(world)), 0)
end)

T.test("goal text: the panel has the five sections, with ticks and the locked gates", function()
  local world = autumnWorld(10)
  stock(world, true)
  world.events:emit("crop.harvested", { crop = "radish", amount = 1 })
  local done, total = Milestones.tally(world)
  local sections = GoalText.panel(Goal.current(world), Milestones.list(world), { done, total }, Goal.gates(world))
  local titles = {}
  for i, s in ipairs(sections) do
    titles[i] = s.title
  end
  T.eq(titles[1], "Now")
  T.eq(titles[2], "Year and season")
  T.eq(titles[3], "Footing")
  T.eq(titles[4], "Milestones")
  T.eq(titles[5], "Opens at Footing")
  T.eq(sections[4].tag, "1 of " .. total)
  T.eq(#sections[3].rows, 1 + 4, "the status, then the four tests")
  local marks = 0
  for _, r in ipairs(sections[4].rows) do
    if r.mark == "done" then
      marks = marks + 1
    end
  end
  T.eq(marks, 1, "one milestone ticked")
  T.truthy(#sections[5].rows >= 1)
  for _, r in ipairs(sections[5].rows) do
    T.eq(r.mark, "lock")
    T.truthy(r.text:find("opens at Footing", 1, true), r.text)
  end
end)

T.test("goal text: once Footing is held the gates read as open", function()
  local world = newWorld(11)
  world.state.footing.held = true
  world.state.footing.gainedDay = 12
  local gates = Goal.gates(world)
  T.truthy(gates.open)
  local sections = GoalText.panel(Goal.current(world), Milestones.list(world), { 0, 8 }, gates)
  T.eq(sections[5].title, "Opened by Footing")
  T.eq(sections[5].rows[1].mark, "open")
  T.truthy(sections[3].rows[1].text:find("Held since day 12", 1, true))
end)

T.test("goal: a content flag `requiresFooting` lists a gate ahead of the named surfaces", function()
  local world = newWorld(12)
  T.eq(#Goal.gates(world).items, #tun.progress.surfaces, "no content carries the flag yet: only the named surfaces")
  local def = world.registry:all("catalog")[1]
  rawset(def, "requiresFooting", true) -- (a test-only flag; no shipped item carries it, D164)
  local gates = Goal.gates(world)
  rawset(def, "requiresFooting", nil)
  T.eq(#gates.items, #tun.progress.surfaces + 1)
  T.eq(gates.items[1].id, def.id)
end)

-- The key ---------------------------------------------------------------------------------------------------------------

T.test("goal: P is the Progress panel's key and it is rebindable", function()
  local map = KeyBindings.keyMap(tun.input, {})
  T.eq(map.p, "progress")
  local listed = false
  for _, a in ipairs(tun.input.rebindable) do
    listed = listed or a == "progress"
  end
  T.truthy(listed)
  T.truthy(require("src.ui.controls_text").actions.progress)
end)

T.test("goal: the Calendar day helper stays in step (sanity for the date maths above)", function()
  local world = newWorld(13)
  setTime(world, 3, 12)
  T.eq(Calendar.now(world).day, 3)
end)
