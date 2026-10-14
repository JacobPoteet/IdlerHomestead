-- The beginner-UX batch (D70): pantry scrolling (#170), low-stock warnings (#157), the bedtime notice
-- and morning report (#159), the won't-ripen warning (#165) and winter readiness (#166). All of it
-- is sim accessors and events; the scenes only turn them into words (src/ui/*_text.lua).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Alerts = require("src.sim.systems.alerts")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Power = require("src.sim.systems.power")
local Shelter = require("src.sim.systems.shelter")
local TripMarker = require("src.render.trip_marker")
local CropCues = require("src.render.crop_cues")
local Journal = require("src.sim.systems.journal")
local Needs = require("src.sim.systems.needs")
local Nightly = require("src.sim.systems.nightly")
local Readiness = require("src.sim.systems.readiness")
local Sleep = require("src.sim.systems.sleep")
local Weather = require("src.sim.systems.weather")
local AlertText = require("src.ui.alert_text")
local NightText = require("src.ui.night_text")
local Scroll = require("src.ui.scroll")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local RATE = tun.time.tickRate
local DPS = tun.time.daysPerSeason
local HOUR = tun.time.dayLength / 24
local SPRING, SUMMER, AUTUMN, WINTER = 1, DPS + 1, 2 * DPS + 1, 3 * DPS + 1

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

--- Jump the clock to `hour` on `day` (the next tick announces the new day).
local function setTime(world, day, hour)
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - tun.time.startHour / 24) * tun.time.dayLength
end

--- Jump the clock and bring the calendar's "last day seen" with it, so no day change is announced.
local function settleAt(world, day, hour)
  setTime(world, day, hour)
  world.state.calendar.day = day
end

local function run(world, seconds)
  for _ = 1, math.ceil(seconds * RATE) do
    world:tick(1 / RATE)
  end
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

--- Set a resource to an exact amount (a test setting up a situation, not a game action).
local function setStock(world, id, amount)
  world.state.ledger.amounts[id] = amount > 0 and amount or nil
end

local function clearFood(world)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      setStock(world, res.id, 0)
    end
  end
end

-- Scrolling (#170) -----------------------------------------------------------------------------

T.test("scroll: clamps, drags with the finger, wheels and reports what is hidden", function()
  T.eq(Scroll.max(200, 120), 80)
  T.eq(Scroll.max(100, 120), 0, "a list that fits does not scroll")
  T.eq(Scroll.clamp(-5, 200, 120), 0)
  T.eq(Scroll.clamp(500, 200, 120), 80)
  T.eq(Scroll.byDrag(0, -30, 200, 120), 30, "dragging up shows later rows")
  T.eq(Scroll.byDrag(30, 100, 200, 120), 0, "dragging down at the top stops")
  T.eq(Scroll.byWheel(0, -1, 22, 200, 120), 22, "wheel down shows later rows")
  T.eq(Scroll.byWheel(10, 5, 22, 200, 120), 0)
  local above, below = Scroll.hidden(30, 200, 120)
  T.eq(above, 30)
  T.eq(below, 50)
  T.eq(Scroll.thumb(0, 100, 120, 120, 8), nil, "no thumb when nothing overflows")
  local at, h = Scroll.thumb(0, 240, 120, 120, 8)
  T.eq(at, 0)
  T.eq(h, 60)
  at, h = Scroll.thumb(120, 240, 120, 120, 8)
  T.eq(at + h, 120, "at the bottom the thumb reaches the end of the track")
  local _, smallest = Scroll.thumb(0, 100000, 120, 120, 8)
  T.eq(smallest, 8, "the thumb never gets smaller than the minimum")
end)

-- Warnings (#157) -----------------------------------------------------------------------------

T.test("alerts: food levels follow the days in stock and the tuned thresholds", function()
  local world = newWorld(1)
  clearFood(world)
  local per = reg:get("resources", "canned_food").calories
  local function level(days)
    setStock(world, "canned_food", math.ceil(days * tun.needs.dailyCalories / per))
    return (Alerts.level(world, "food"))
  end
  T.eq(level(tun.alerts.foodAmberDays + 1), 0)
  T.eq(level(tun.alerts.foodAmberDays - 0.5), 1, "amber under the amber threshold")
  T.eq(level(tun.alerts.foodRedDays - 0.5), 2, "red under the red threshold")
  setStock(world, "canned_food", 0)
  T.eq((Alerts.level(world, "food")), 2)
end)

T.test("alerts: fuel is judged in nights against tonight's need and is quiet when no fire is needed", function()
  local world = newWorld(1)
  settleAt(world, SUMMER, 12)
  T.eq((Alerts.level(world, "fuel")), 0, "summer needs no fire")
  settleAt(world, WINTER + 2, 12)
  local need = Needs.warmthNeeded(world)
  T.truthy(need > 0)
  local perWood = Needs.warmthPerWood(world)
  setStock(world, "wood", math.ceil(need * (tun.alerts.fuelAmberNights + 1) / perWood))
  T.eq((Alerts.level(world, "fuel")), 0)
  setStock(world, "wood", math.ceil(need * (tun.alerts.fuelAmberNights - 0.5) / perWood))
  T.eq((Alerts.level(world, "fuel")), 1)
  setStock(world, "wood", math.floor(need * (tun.alerts.fuelRedNights - 0.5) / perWood))
  T.eq((Alerts.level(world, "fuel")), 2)
  T.near(Needs.fuelNights(world), Needs.warmthInStock(world) / need, 1e-9)
end)

T.test("alerts: condition levels", function()
  local world = newWorld(1)
  world.state.alerts.dawn = nil -- levels by value only here: the falling-condition rule is in test_message_log.lua (D90)
  world.state.needs.condition = tun.alerts.conditionAmber + 1
  T.eq((Alerts.level(world, "condition")), 0)
  world.state.needs.condition = tun.alerts.conditionAmber - 1
  T.eq((Alerts.level(world, "condition")), 1)
  world.state.needs.condition = tun.alerts.conditionRed - 1
  T.eq((Alerts.level(world, "condition")), 2)
end)

T.test("alerts: a worse level is raised once per day per level, and recovering re-arms it", function()
  local world = newWorld(1)
  clearFood(world)
  settleAt(world, 1, 12)
  setStock(world, "canned_food", 9)
  run(world, 2)
  local raised = collect(world, "alert.raised")
  local function food(n)
    setStock(world, "canned_food", n)
    run(world, tun.alerts.checkInterval + 0.5)
  end
  food(5) -- 1.7 days: amber
  T.eq(#raised, 1)
  T.eq(raised[1].kind, "food")
  T.eq(raised[1].level, 1)
  food(4) -- still amber: nothing new
  T.eq(#raised, 1, "no repeat while the level holds")
  food(2) -- red
  T.eq(#raised, 2)
  T.eq(raised[2].level, 2)
  food(9) -- plenty again
  food(5) -- amber again, the same day: held back
  T.eq(#raised, 2, "the same crossing twice in one day is not repeated")
  settleAt(world, 2, 12)
  food(9)
  food(5)
  T.eq(#raised, 3, "the next day it says so again")
end)

T.test("alerts: a fire-less home says so instead of counting nights", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN, 12)
  setStock(world, "wood", 40)
  run(world, 2)
  for anchor, obj in pairs(world.state.grid.objects) do
    if reg:get("objects", obj.id).heatSource then
      Grid.removeObject(world, anchor)
    end
  end
  local raised = collect(world, "alert.raised")
  run(world, 2)
  local fuel
  for _, e in ipairs(raised) do
    if e.kind == "fuel" then
      fuel = e
    end
  end
  T.truthy(fuel, "no fire means no warmth: red")
  T.truthy(fuel.noFire)
  T.truthy(AlertText.toast(fuel):find("fire", 1, true))
end)

T.test("alerts: loading raises nothing, and a save from before D70 loads", function()
  local meta = {}
  local world = newWorld(2, meta)
  clearFood(world)
  setStock(world, "canned_food", 1) -- red already
  run(world, 2)
  local data = serialize.decode(serialize.encode({ run = world.state, meta = meta }))
  data.run.alerts, data.run.nightly = nil, nil -- the shape of an older save
  local restored = World.new({ registry = reg, tuning = tun, meta = data.meta }, data.run)
  local raised = collect(restored, "alert.raised")
  run(restored, 3)
  T.eq(#raised, 0, "a level the player already had is not news")
  T.truthy(restored.state.alerts and restored.state.nightly)
  T.falsy(Nightly.hasReport(restored))
end)

T.test("alerts: deterministic, and the warning state round-trips", function()
  local function history(seed)
    local world = newWorld(seed)
    clearFood(world)
    setStock(world, "canned_food", 9)
    settleAt(world, 1, 6)
    local out = {}
    world.events:on("alert.raised", function(e)
      out[#out + 1] = string.format("%d:%s:%d:%.2f", world.state.tick, e.kind, e.level, e.value)
    end)
    for n = 1, 12 do
      setStock(world, "canned_food", 9 - n)
      run(world, 4)
    end
    return table.concat(out, " ") .. "|" .. serialize.encode(world.state.alerts)
  end
  T.eq(history(5), history(5))
  T.truthy(history(5):find("food", 1, true))
end)

T.test("alert text: toasts name the problem and what to do", function()
  T.truthy(AlertText.toast({ kind = "food", level = 1, value = 1.4 }):find("Food is low", 1, true))
  T.truthy(AlertText.toast({ kind = "food", level = 2, value = 0 }):find("Out of food", 1, true))
  T.truthy(AlertText.toast({ kind = "fuel", level = 1, value = 1.5 }):find("Wood is low", 1, true))
  T.truthy(AlertText.toast({ kind = "fuel", level = 2, value = 0.5 }):find("tonight", 1, true))
  T.truthy(AlertText.toast({ kind = "condition", level = 2, value = 30 }):find("Health is low", 1, true))
end)

-- Won't ripen before winter (#165) ---------------------------------------------------------------

T.test("frost risk: late, tight or fine from the days left to the freeze", function()
  local world = newWorld(1)
  settleAt(world, SPRING + 2, 12)
  T.eq(Crops.frostRisk(world, "potato"), nil, "plenty of time in spring")
  settleAt(world, AUTUMN + DPS - 2, 12) -- two days left, counting today
  T.eq(Weather.daysToFreeze(world), 2)
  local radish = Crops.frostRisk(world, "radish")
  T.eq(radish.level, "tight", "just enough, within the starter margin")
  T.eq(radish.daysLeft, 2)
  T.eq(radish.growDays, 2)
  T.eq(Crops.frostRisk(world, "potato").level, "late")
  settleAt(world, AUTUMN + DPS - 1, 12)
  T.eq(Crops.frostRisk(world, "radish").level, "late", "one day left and the radish needs two")
  settleAt(world, WINTER + 1, 12)
  T.eq(Crops.frostRisk(world, "radish"), nil, "frozen: nothing can be planted, no warning")
end)

T.test("frost text: says what the crop needs and what is left; none when it ripens", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN + DPS - 3, 12) -- 3 days left
  local text = AlertText.frost(world, "potato")
  T.truthy(text:find("Won't ripen before winter", 1, true))
  T.truthy(text:find("Potato", 1, true))
  T.truthy(text:find("5 watered days", 1, true))
  T.truthy(text:find("3 left", 1, true))
  settleAt(world, SPRING + 2, 12)
  T.eq(AlertText.frost(world, "potato"), nil)
end)

T.test("frost text: a crop in the ground shows days to the freeze", function()
  local world = newWorld(1)
  local crop = { id = "potato", growth = 0.2, moisture = 1 } -- 4 watered days to go
  settleAt(world, AUTUMN, 12)
  T.eq(AlertText.cropFrostLine(world, crop), string.format("Frost in %dd", Weather.daysToFreeze(world)))
  T.eq(Weather.daysToFreeze(world), DPS)
  settleAt(world, AUTUMN + DPS - 2, 12)
  T.truthy(AlertText.cropFrostLine(world, crop):find("too late", 1, true))
  crop.growth = 1
  T.truthy(AlertText.cropFrostLine(world, crop):find("harvest", 1, true))
  T.near(Crops.daysToRipe(world, { id = "potato", growth = 0.4, moisture = 1 }), 3, 1e-9)
  settleAt(world, WINTER, 12)
  T.eq(AlertText.cropFrostLine(world, crop), nil)
end)

-- Winter readiness (#166) -------------------------------------------------------------------

T.test("readiness: shows from autumn on, not before", function()
  local world = newWorld(1)
  settleAt(world, SPRING, 12)
  T.eq(Readiness.winter(world), nil)
  settleAt(world, SUMMER + DPS - 1, 12)
  T.eq(Readiness.winter(world), nil)
  settleAt(world, AUTUMN, 12)
  local r = Readiness.winter(world)
  T.truthy(r)
  T.eq(r.daysAway, DPS)
  T.eq(r.fuel.nights, 2 * DPS, "the rest of autumn and the whole winter")
  T.eq(r.food.need, DPS)
  settleAt(world, WINTER + 2, 12)
  r = Readiness.winter(world)
  T.truthy(r.frozen)
  T.eq(r.fuel.nights, DPS - 2, "winter nights still to come, tonight included")
  settleAt(world, WINTER + DPS - 1, 12)
  T.truthy(Readiness.winter(world))
  settleAt(world, 4 * DPS + 1, 12) -- spring, next year
  T.eq(Readiness.winter(world), nil)
end)

T.test("readiness: the verdict names what is short, from the stock and the forecast", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN, 12)
  clearFood(world)
  setStock(world, "wood", 0)
  local r = Readiness.winter(world)
  T.eq(r.verdict, "both")
  setStock(world, "wood", 1000)
  setStock(world, "smoked_fish", 1000)
  setStock(world, "canned_food", 0)
  r = Readiness.winter(world)
  T.eq(r.verdict, "ready")
  T.truthy(r.fuel.ok and r.food.ok)
  setStock(world, "smoked_fish", 0)
  T.eq(Readiness.winter(world).verdict, "food")
  setStock(world, "smoked_fish", 1000)
  setStock(world, "wood", math.ceil(Needs.warmthNeeded(world) / Needs.warmthPerWood(world)))
  r = Readiness.winter(world)
  T.eq(r.verdict, "fuel")
  T.truthy(
    r.fuel.covered >= 1 and r.fuel.covered < r.fuel.nights,
    "the wood of one night pays the first nights and not the whole winter"
  )
end)

T.test("readiness: the need is exact only once the forecast is, and uses what is revealed", function()
  local world = newWorld(3)
  settleAt(world, AUTUMN, 12)
  setStock(world, "wood", 1000)
  local r = Readiness.winter(world)
  T.falsy(r.exact, "nothing revealed yet")
  local floor = tun.weather.severityMin
  local function base(season, d)
    return Weather.baseWarmth(world, season, d)
  end
  local autumn, winterSum = 0, 0
  for d = 1, DPS do
    autumn = autumn + base("autumn", d)
    winterSum = winterSum + base("winter", d)
  end
  T.near(r.fuel.need, autumn + winterSum * floor, 1e-6, "the floor of what winter can be")
  -- Reveal the whole forecast.
  world.state.weather.revealed[1] = 3
  r = Readiness.winter(world)
  T.truthy(r.exact)
  local winter = Weather.winter(world)
  local expected = autumn
  for d = 1, DPS do
    local mult = winter.severity
    if d >= winter.snapStart and d < winter.snapStart + winter.snapDays then
      mult = mult * tun.weather.snapMultiplier
    end
    expected = expected + base("winter", d) * mult
  end
  T.near(r.fuel.need, expected, 1e-6, "severity and the cold snap are counted")
end)

T.test("readiness: no fire placed means nothing is covered", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN, 12)
  setStock(world, "wood", 1000)
  for anchor, obj in pairs(world.state.grid.objects) do
    if reg:get("objects", obj.id).heatSource then
      Grid.removeObject(world, anchor)
    end
  end
  local r = Readiness.winter(world)
  T.truthy(r.noFire)
  T.eq(r.fuel.covered, 0)
  T.truthy(AlertText.readinessCard(world))
end)

T.test("readiness: pill and card words, deterministic", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN, 12)
  local text, _, r = AlertText.readinessPill(world)
  T.truthy(text:find("Winter: short on", 1, true))
  T.eq(r.verdict, "both")
  local headline, message = AlertText.readinessCard(world)
  T.truthy(headline:find("short on wood and food", 1, true))
  T.truthy(message:find("Wood:", 1, true) and message:find("Food:", 1, true))
  T.truthy(message:find("forecast", 1, true), "says the forecast is still coming in")
  T.truthy(AlertText.autumnToast(world):find("Autumn: winter in", 1, true))
  settleAt(world, SPRING, 12)
  T.eq(AlertText.readinessPill(world), nil)
  T.eq(AlertText.autumnToast(world), nil)
  local a, b = newWorld(4), newWorld(4)
  settleAt(a, AUTUMN + 1, 9)
  settleAt(b, AUTUMN + 1, 9)
  T.eq(serialize.encode(Readiness.winter(a)), serialize.encode(Readiness.winter(b)))
end)

T.test("expected warmth need: base outside the cold, forecast inside it", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN, 12)
  local need, exact = Weather.expectedWarmthNeed(world, "autumn", 3)
  T.eq(need, Weather.baseWarmth(world, "autumn", 3))
  T.truthy(exact)
  need, exact = Weather.expectedWarmthNeed(world, "winter", 3)
  T.falsy(exact)
  T.near(need, Weather.baseWarmth(world, "winter", 3) * tun.weather.severityMin, 1e-9)
end)

-- Bedtime and the morning report (#159) ------------------------------------------------------------

local function studyCandidate()
  for _, def in ipairs(reg:all("catalog")) do
    if def.studyNights and not def.starter then
      return def.id
    end
  end
end

T.test("journal: studying() names the head of the queue and its progress", function()
  local world = newWorld(1)
  T.eq(Journal.studying(world), nil)
  local id = studyCandidate()
  world.meta.journal.queue = { id }
  world.meta.journal.progress[id] = 1.5
  local s = Journal.studying(world)
  T.eq(s.id, id)
  T.eq(s.nights, 1.5)
  T.eq(s.total, reg:get("catalog", id).studyNights)
  T.truthy(s.name == reg:get("catalog", id).name)
end)

T.test("bedtime text: studying, or nothing queued", function()
  local world = newWorld(1)
  T.truthy(NightText.bedtime(world):find("Nothing queued to study", 1, true))
  local id = studyCandidate()
  world.meta.journal.queue = { id }
  world.meta.journal.progress[id] = 1.2
  local text = NightText.bedtime(world)
  T.truthy(text:find("Studying: " .. reg:get("catalog", id).name, 1, true))
  T.truthy(text:find("night 2 of", 1, true))
end)

--- A world put to bed at the evening, run through midnight to the morning. Returns world, reports.
local function throughTheNight(seed, prepare, midnight)
  local world = newWorld(seed)
  world.control = "idle"
  if prepare then
    prepare(world)
  end
  local reports = collect(world, "night.report")
  local hs = Actors.homesteader(world)
  local bed, wake = Sleep.bedtimeHours(world)
  settleAt(world, 1, bed)
  run(world, HOUR * 2)
  T.truthy(hs.asleep, "in bed")
  if midnight then
    midnight(world)
  end
  setTime(world, 2, 0.5) -- past midnight: the next tick is the new day
  run(world, 5)
  settleAt(world, 2, wake - 0.1)
  run(world, HOUR * 0.5)
  T.falsy(hs.asleep, "up at sunrise")
  run(world, 1)
  return world, reports
end

T.test("morning report: slept, studied, ate and the rest, closed at sunrise", function()
  local id = studyCandidate()
  local world, reports = throughTheNight(4, function(w)
    w.meta.journal.queue = { id }
    setStock(w, "radish", 6)
  end)
  T.eq(#reports, 1)
  T.truthy(Nightly.hasReport(world))
  local report = Nightly.report(world)
  T.truthy(report.hours > 0)
  T.truthy(report.calories >= tun.needs.dailyCalories)
  T.truthy(next(report.ate), "what was eaten is listed")
  T.eq(report.study.id, id)
  T.truthy(report.study.to >= report.study.from)
  local lines = NightText.morning(world, report)
  local text = {}
  for _, line in ipairs(lines) do
    text[#text + 1] = line.text
  end
  local all = table.concat(text, "\n")
  T.truthy(all:find("Slept", 1, true))
  T.truthy(all:find("Studied", 1, true) or all:find("Finished studying", 1, true))
  T.truthy(all:find("Ate ", 1, true) and all:find("calories", 1, true))
  T.eq(Nightly.take(world), report)
  T.falsy(Nightly.hasReport(world), "taken once")
end)

T.test("morning report: hunger, burned fuel and a raid appear; the cold counts too", function()
  local world, reports = throughTheNight(4, function(w)
    clearFood(w)
    setStock(w, "canned_food", 1) -- one meal short
  end, function(w)
    w.events:emit("mice.raided", { day = 1, lost = { radish = 3 }, units = 3 })
    w.events:emit("animals.predator", { day = 1, killed = 1, stopped = false })
  end)
  T.eq(#reports, 1)
  local report = Nightly.report(world)
  T.truthy(report.hungry > 0)
  T.eq(report.raided.radish, 3)
  T.eq(report.killed, 1)
  local lines = NightText.morning(world, report)
  local all = {}
  for _, line in ipairs(lines) do
    all[#all + 1] = line.text
  end
  local text = table.concat(all, "\n")
  T.truthy(text:find("Went hungry", 1, true))
  T.truthy(text:find("Mice took 3 radish", 1, true))
  T.truthy(text:find("A fox took 1 hen", 1, true))
end)

T.test("morning report: a mid-night wake does not split the night in two", function()
  local world, reports = throughTheNight(4, nil, function(w)
    Sleep.wake(w, Actors.homesteader(w)) -- a player order in the small hours
    run(w, 1)
  end)
  T.eq(#reports, 1, "one report, at sunrise")
  T.truthy(Nightly.report(world).calories > 0, "midnight's meal is in it")
end)

T.test("morning report: survives a save, and a night nobody slept is carried to the next", function()
  local meta = {}
  local world = newWorld(4, meta)
  world.control = "idle"
  local bed, wake = Sleep.bedtimeHours(world)
  settleAt(world, 1, bed)
  run(world, HOUR * 2)
  setTime(world, 2, 0.5)
  run(world, 5)
  settleAt(world, 2, wake - 0.1)
  run(world, HOUR * 0.5 + 1)
  T.truthy(Nightly.hasReport(world))
  local data = serialize.decode(serialize.encode({ run = world.state, meta = meta }))
  local restored = World.new({ registry = reg, tuning = tun, meta = data.meta }, data.run)
  T.truthy(Nightly.hasReport(restored))
  T.truthy(Nightly.report(restored).calories >= tun.needs.dailyCalories)
  -- Awake all night: midnight's meal waits in the open ledger for the next sleeper.
  local awake = newWorld(5)
  settleAt(awake, 1, 12)
  setTime(awake, 2, 0.5)
  run(awake, 5)
  T.falsy(Nightly.hasReport(awake), "no report without a night's sleep")
  T.truthy(awake.state.nightly.open.calories >= tun.needs.dailyCalories)
end)

T.test("morning report: deterministic", function()
  local function signature(seed)
    local world = throughTheNight(seed)
    return serialize.encode(Nightly.report(world))
  end
  T.eq(signature(7), signature(7))
end)

-- Electric heat in the winter readiness (D101, #175) ---------------------------------------------

local function placeAnywhere(world, id)
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, id, i) then
      Inventory.addObject(world, id)
      T.truthy(Inventory.place(world, id, i), "placed " .. id)
      return
    end
  end
  error("no room for " .. id)
end

T.test("readiness: electric heaters and a battery pay part of each night, never twice", function()
  local world = newWorld(1)
  settleAt(world, AUTUMN, 12)
  setStock(world, "wood", 0)
  local bare = Readiness.winter(world)
  T.eq(bare.electric.total, 0)
  placeAnywhere(world, "electric_heater")
  T.eq(Readiness.winter(world).electric.total, 0, "a heater with no battery or source makes nothing")
  placeAnywhere(world, "battery_bank")
  placeAnywhere(world, "solar_array")
  local r = Readiness.winter(world)
  T.truthy(r.electric.total > 0 and r.electric.perNight > 0)
  T.near(r.fuel.need + r.electric.total, bare.fuel.need, 1e-6, "fuel pays only what the heaters do not")
  T.truthy(
    r.electric.perNight <= Weather.expectedWarmthNeed(world, "winter", 7) * Shelter.insulation(world) + 1e-9,
    "never more than the night needs"
  )
  local _, message = AlertText.readinessCard(world)
  T.truthy(message:find("Electric:", 1, true))
  T.eq(Readiness.winter(newWorld(1)), nil)
  -- Switching the heater off (or removing it) takes the electric share away again.
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "electric_heater" then
      Power.setEnabled(world, anchor, false)
    end
  end
  T.eq(Readiness.winter(world).electric.total, 0)
end)

T.test("catalog: the Stand cooler line says what the modifier does", function()
  local item = reg:get("catalog", "stand_cooler")
  T.truthy(item.line:find("+" .. item.modifiers.standCap, 1, true), "names the cap it adds")
  T.eq(item.line:lower():find("keep", 1, true), nil, "does not claim to slow spoilage")
  T.eq(item.modifiers.spoilSlow, nil)
end)

T.test("trip marker: shown only while a trip is ready and the player is home", function()
  T.truthy(TripMarker.visible(true, false))
  T.falsy(TripMarker.visible(true, true))
  T.falsy(TripMarker.visible(false, false))
  T.falsy(TripMarker.visible(nil, nil))
  local cfg = tun.visuals.tripMarker
  T.eq(TripMarker.offset(0.3, cfg, true), 0, "reduce motion holds it still")
  for t = 0, 24 do
    local dy = TripMarker.offset(t * 0.1, cfg, false)
    T.truthy(dy >= 0 and dy <= cfg.bobPixels and dy == math.floor(dy), "whole art pixels inside the bob")
  end
end)

T.test("crop cues: ripe, thirsty and planned map from sim state (D102)", function()
  T.eq(CropCues.cue(nil), nil)
  T.eq(CropCues.cue({ growth = 0.3, moisture = 1 }), nil, "watered and growing: no cue")
  T.eq(CropCues.cue({ growth = 0.3, moisture = 0 }), "thirsty")
  T.eq(CropCues.cue({ growth = 1, moisture = 0 }), "ready", "ripe wins over dry (a ripe crop needs no water)")
  T.eq(CropCues.cue({ growth = 1.2, moisture = 1 }), "ready")
  T.eq(CropCues.planState("radish", false, nil), "planned_bare")
  T.eq(CropCues.planState("radish", true, nil), "planned_tilled")
  T.eq(CropCues.planState("radish", true, { growth = 0, moisture = 0 }), nil, "a planted tile is a plant, not a plan")
  T.eq(CropCues.planState(nil, true, nil), nil)
end)

T.test("crop cues: sparkle is always visible, still under reduce motion", function()
  local cfg = tun.visuals.cropCues
  local a, frame = CropCues.sparkle(5, 3, 4, cfg, true)
  T.eq(a, cfg.sparkleRest)
  T.eq(frame, 1)
  local sawStar = false
  for t = 0, 60 do
    local alpha, f = CropCues.sparkle(t * 0.05, 3, 4, cfg, false)
    T.truthy(alpha >= cfg.sparkleRest - 1e-9 and alpha <= 1 + 1e-9, "never fades out")
    T.truthy(f == 1 or f == 2)
    sawStar = sawStar or f == 2
  end
  T.truthy(sawStar, "it twinkles")
  T.truthy(CropCues.iconAlpha(0, cfg) < CropCues.iconAlpha(1, cfg), "icons dim a little at night")
  T.truthy(CropCues.iconAlpha(0, cfg) > 0.5, "but stay readable")
  T.eq(CropCues.nightLift(1, cfg), 0)
  T.eq(CropCues.nightLift(0, cfg), cfg.nightLift, "full lift in the dark")
end)
