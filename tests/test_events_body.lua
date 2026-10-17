-- The body events pack (B6, D173, docs/PLAN_DEPTH.md §6.2, §7, src/sim/systems/events.lua, data/content/events.lua): each event's
-- two options and its ignore outcome, the triggers and weights (boots, cold nights, the stove, the sun), the delayed outcomes
-- (`later`), the mercy rules over them, and the words of the card.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local EventText = require("src.ui.event_text")
local Events = require("src.sim.systems.events")
local Grid = require("src.sim.grid")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Status = require("src.sim.systems.status")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.events

local BODY = {
  "sprained_ankle",
  "torn_ankle",
  "festering_cut",
  "fever_cold_night",
  "back_strain",
  "stove_burn",
  "heat_exhaustion",
  "bad_tooth",
}

-- Tests change tuning to force a case; every test starts from the shipped values.
local shippedChances = {}
for k, v in pairs(cfg.chances) do
  shippedChances[k] = v
end
local test = T.test
T.test = function(name, fn)
  test(name, function()
    for k, v in pairs(shippedChances) do
      cfg.chances[k] = v
    end
    return fn()
  end)
end

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true -- bad events wait for Footing (or day 10)
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

local function place(world, id)
  local grid = world.state.grid
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for r = 0, 12 do
    for step = 0, 12 do
      local x, y = tx + 2 + r, ty + step
      if Grid.inBounds(grid, x, y) then
        local anchor = Grid.placeObject(world, id, x, y)
        if anchor then
          return anchor
        end
      end
    end
  end
  error("no tile for " .. id)
end

--- Offer `id` now and answer it: option 1 or 2, or "ignore". Gives the world the stock the cost needs (water needs a cistern).
local function answer(world, id, how)
  Ledger.setCapacity(world, "water", 60) -- a cistern: water has nowhere to go without one
  Ledger.add(world, "wood", 10)
  Ledger.add(world, "water", 5)
  Ledger.add(world, "canned_food", 2)
  world.state.events.budget.day = 0
  T.truthy(Events.force(world, id), "the card opens")
  if how == "ignore" then
    T.truthy(Events.ignore(world))
  else
    T.truthy(Events.choose(world, how))
  end
end

-- The pack ----------------------------------------------------------------------------------------------------

T.test("body events: every one is a clean two-option content table with a free, non-escalating ignore", function()
  local world = newWorld()
  T.same(Events.audit(world), {}, "the audit finds nothing")
  for _, id in ipairs(BODY) do
    local d = reg:get("events", id)
    T.eq(d.class, "body", id)
    T.eq(d.bad, true, id)
    T.eq(#d.options, 2, id)
    T.eq(d.options[1].careful, true, id .. " option 1 is the careful one")
    T.eq(d.options[2].bold, true, id .. " option 2 is the bold one")
    T.truthy(d.journalNote and reg:has("notes", d.journalNote), id .. " writes a Journal note")
    T.eq(d.ignore.cost, nil, id .. " ignore is free")
    for _, o in ipairs({ d.options[1], d.options[2], d.ignore }) do
      T.falsy(o.risk:find("%d") or o.risk:find("%%"), id .. ": the risk is in words, never odds: " .. o.risk)
    end
  end
  -- Each ignore is a status that cannot escalate (or nothing) and is not a chance.
  for _, id in ipairs(BODY) do
    local ignore = reg:get("events", id).ignore
    T.eq(ignore.effect.later, nil, id)
    local status = ignore.effect.status
    if status then
      T.eq(reg:get("statuses", status).escalatesTo, nil, id .. " ignore " .. status)
    end
  end
end)

T.test("body events: the first occurrence writes the Journal note", function()
  for _, id in ipairs(BODY) do
    local world = newWorld()
    T.falsy(Journal.hasNote(world, reg:get("events", id).journalNote), id)
    Events.force(world, id)
    T.truthy(Journal.hasNote(world, reg:get("events", id).journalNote), id)
  end
end)

-- Sprained ankle, torn ankle ---------------------------------------------------------------------------------------

T.test("sprained ankle: splinting costs wood and hobbles today only", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  Ledger.add(world, "wood", 10)
  local wood = Ledger.get(world, "wood")
  answer(world, "sprained_ankle", 1)
  T.eq(Ledger.get(world, "wood"), wood + 10 - 2)
  T.eq(Status.get(world, "ankle_1").left, 1)
  T.eq(Status.modifier(world, "workSpeed"), 0.5)
  T.eq(Status.modifier(world, "fallChance"), 1, "no fall risk change")
  world.events:emit("calendar.newDay", { day = SPRING + 1, season = "spring", year = 1 })
  T.falsy(Status.has(world, "ankle_1"), "gone tomorrow morning")
end)

T.test("sprained ankle: powering through is fine today, strained tomorrow, and a fall tears it", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  answer(world, "sprained_ankle", 2)
  T.eq(Status.count(world), 0)
  T.eq(Status.modifier(world, "workSpeed"), 1, "no slowdown today")
  setTime(world, SPRING + 1, 8)
  tick(world)
  T.eq(Status.get(world, "ankle_2").id, "ankle_2", "strained tomorrow")
  T.eq(Status.modifier(world, "fallChance"), 2)
  -- A fresh sprain is not drawn while it lasts, and the fall is.
  setTime(world, SPRING + 1, 21.5)
  T.eq(Events.weight(world, "sprained_ankle"), 0, "not a fresh sprain")
  T.near(
    Events.weight(world, "torn_ankle"),
    reg:get("events", "torn_ankle").weight * 2,
    1e-9,
    "a fall, twice as likely"
  )
  local fresh = newWorld()
  setTime(fresh, SPRING + 1, 21.5)
  T.eq(Events.weight(fresh, "torn_ankle"), 0, "no fall without the strain")
  T.truthy(Events.weight(fresh, "sprained_ankle") > 0)
end)

T.test("torn ankle: the fall comes after the strain has gone, and splinting it shortens it", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  Status.apply(world, "ankle_2")
  -- Drawn at dusk with the strain on, offered the next morning when it is over.
  world.state.events.scheduled = { { id = "torn_ankle", due = (SPRING + 1) * 24 + 8, depth = 0 } }
  Status.clear(world, "ankle_2")
  setTime(world, SPRING + 1, 9)
  tick(world)
  T.eq(Events.pending(world).id, "torn_ankle", "its cause has passed but it still comes")
  Ledger.add(world, "wood", 10)
  Ledger.add(world, "canned_food", 2)
  local food = Ledger.get(world, "canned_food")
  local view = Events.pending(world)
  T.eq(view.options[1].cost.wood, 3)
  T.eq(view.options[1].cost.canned_food, 1)
  T.truthy(Events.choose(world, 1))
  T.eq(Ledger.get(world, "canned_food"), food - 1)
  T.eq(Status.get(world, "ankle_3b").left, 2, "two days, not three")
  T.eq(Status.modifier(world, "workSpeed"), 0.4)
end)

T.test("torn ankle: walking it off costs Condition once, never under the floor, and takes three days", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  world.state.needs.condition = 80
  answer(world, "torn_ankle", 2)
  T.eq(Needs.condition(world), 65)
  T.eq(Status.get(world, "ankle_3").left, 3)
  local low = newWorld()
  low.state.needs.condition = 20
  answer(low, "torn_ankle", 2)
  T.eq(Needs.condition(low), cfg.mercy.conditionFloor, "never the killing blow")
end)

T.test("sprained and torn ankle: ignoring limps on for two days, free, and never worse", function()
  for _, id in ipairs({ "sprained_ankle", "torn_ankle" }) do
    local world = newWorld()
    setTime(world, SPRING, 13)
    Status.apply(world, "ankle_2")
    local wood, food = Ledger.get(world, "wood"), Ledger.get(world, "canned_food")
    Events.force(world, id)
    T.truthy(Events.ignore(world))
    T.eq(Ledger.get(world, "wood"), wood, id)
    T.eq(Ledger.get(world, "canned_food"), food, id)
    T.eq(Status.get(world, "limp").left, 2, id)
    T.eq(Status.get(world, "ankle_2").id, "ankle_2", id .. ": the ankle itself is not made worse")
    T.truthy(Journal.hasNote(world, "limped_on"), id)
    T.eq(#world.state.events.delayed, 0, id .. ": nothing is left to roll later")
  end
end)

T.test("sprained ankle: loose boots raise its weight and heavy boots lower it", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  Weather.force(world, "clear")
  local mid = Events.weight(world, "sprained_ankle")
  T.truthy(mid > 0)
  world.state.wardrobe.dressed.feet = "canvas_shoes"
  T.near(Events.weight(world, "sprained_ankle"), mid * 1.5, 1e-9, "loose, light shoes")
  world.state.wardrobe.dressed.feet = "felt_boots"
  T.near(Events.weight(world, "sprained_ankle"), mid * 0.6, 1e-9, "heavy boots")
  world.state.wardrobe.dressed.feet = "work_boots"
  T.near(Events.weight(world, "sprained_ankle"), mid, 1e-9)
  Weather.force(world, "rain")
  T.near(Events.weight(world, "sprained_ankle"), mid * 3, 1e-9, "wet rocks")
end)

-- Festering cut ------------------------------------------------------------------------------------------------------

T.test("festering cut: cleaning it costs water and an hour of work, with no infection", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  cfg.chances.festerInfection = 1
  local water = Ledger.get(world, "water")
  answer(world, "festering_cut", 1)
  T.eq(Ledger.get(world, "water"), water + 5 - 1)
  T.eq(Status.get(world, "tending").left, 1)
  T.near(Status.modifier(world, "workSpeed"), 0.92, 1e-9, "an hour of about twelve")
  T.eq(#world.state.events.delayed, 0)
  setTime(world, SPRING + 2, 9)
  tick(world)
  T.falsy(Status.has(world, "infection"))
end)

T.test("festering cut: leaving it may turn infected two mornings on, and the roll is seeded", function()
  local function leave(chance)
    local world = newWorld(3)
    setTime(world, SPRING, 13)
    cfg.chances.festerInfection = chance
    local landed = {}
    world.events:on("event.later", function(e)
      landed[#landed + 1] = e
    end)
    answer(world, "festering_cut", 2)
    T.eq(Status.count(world), 0, "nothing yet")
    T.eq(#world.state.events.delayed, 1)
    setTime(world, SPRING + 1, 23)
    tick(world)
    T.eq(#landed, 0, "not before the second morning")
    setTime(world, SPRING + 2, 8)
    tick(world)
    T.eq(#landed, 1)
    T.eq(#world.state.events.delayed, 0)
    return world, landed[1]
  end
  local sick, event = leave(1)
  T.eq(event.hit, true)
  T.eq(event.id, "festering_cut")
  T.eq(Status.has(sick, "infection"), true)
  T.eq(Status.modifier(sick, "workSpeed"), 0.75)
  local well, miss = leave(0)
  T.eq(miss.hit, false)
  T.eq(Status.count(well), 0, "the chance missed")
  -- Same seed, same answer.
  local again = leave(0.4)
  local twice = leave(0.4)
  T.eq(Status.has(again, "infection"), Status.has(twice, "infection"))
end)

T.test("festering cut: rinsing it is free, a little slow, and has no infection roll", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  answer(world, "festering_cut", "ignore")
  T.eq(Status.get(world, "rinse").left, 2)
  T.near(Status.modifier(world, "workSpeed"), 0.9, 1e-9)
  T.eq(#world.state.events.delayed, 0, "no roll")
  T.eq(reg:get("statuses", "rinse").escalatesTo, nil)
end)

-- Fever --------------------------------------------------------------------------------------------------------------

T.test("fever: resting a day loses the work and the fever never takes hold", function()
  local world = newWorld()
  setTime(world, WINTER, 9)
  answer(world, "fever_cold_night", 1)
  T.eq(Status.has(world, "fever"), false)
  T.eq(Status.get(world, "rested").left, 1)
  T.eq(Status.modifier(world, "workSpeed"), tun.status.minWorkSpeed, "no real work today")
  T.eq(Status.modifier(world, "conditionRecovery"), 2, "twice the recovery")
  T.eq(#world.state.events.delayed, 0)
end)

T.test("fever: working through is slow and may turn into flu with a Condition loss", function()
  cfg.chances.feverFlu = 1
  local world = newWorld()
  setTime(world, WINTER, 9)
  world.state.needs.condition = 80
  answer(world, "fever_cold_night", 2)
  T.near(Status.modifier(world, "workSpeed"), 0.6, 1e-9)
  T.eq(Status.get(world, "fever").left, 3)
  setTime(world, WINTER + 2, 8)
  tick(world)
  T.eq(Status.get(world, "flu").severity, 2, "the fever became the flu")
  T.eq(Needs.condition(world), 60)
  -- A missed chance leaves the fever as it was.
  cfg.chances.feverFlu = 0
  local other = newWorld()
  setTime(other, WINTER, 9)
  answer(other, "fever_cold_night", 2)
  other.state.events.delayed[1].due = 0
  tick(other)
  T.eq(Status.has(other, "flu"), false)
  T.eq(Status.has(other, "fever"), true)
end)

T.test("fever: shivering it off is a chill that cannot become a flu", function()
  local world = newWorld()
  setTime(world, WINTER, 9)
  answer(world, "fever_cold_night", "ignore")
  T.eq(Status.get(world, "chill").left, 3)
  T.near(Status.modifier(world, "workSpeed"), 0.8, 1e-9)
  T.eq(#world.state.events.delayed, 0)
end)

T.test("fever: it needs a cold night, and never comes on a night that already cost cold damage", function()
  local world = newWorld()
  setTime(world, SUMMER, 21.5)
  T.eq(Events.weight(world, "fever_cold_night"), 0, "no cold night in summer")
  setTime(world, WINTER, 21.5)
  T.truthy(Needs.warmthNeeded(world) >= cfg.body.coldNightNeed)
  T.truthy(Events.weight(world, "fever_cold_night") > 0, "a deep winter night")
  -- The night the draw was made for: a cold night noted by the needs system blocks it when it comes due.
  local cold = newWorld()
  setTime(cold, WINTER, 21.5)
  cold.state.events.scheduled = { { id = "fever_cold_night", due = (WINTER + 1) * 24 + 8, depth = 0 } }
  setTime(cold, WINTER + 1, 0.5)
  cold.events:emit("needs.warmed", { shortfall = 0.2, needed = 6, warmth = 4, electric = 0, burned = 2 })
  T.eq(cold.state.events.coldDay, WINTER + 1)
  setTime(cold, WINTER + 1, 9)
  tick(cold)
  T.eq(Events.pending(cold), nil, "the night cost cold damage: no fever")
  T.eq(Events.history(cold)[1].how, "dropped")
  T.eq(Events.history(cold)[1].reason, "conditions")
  -- A cold night that was met brings it, in summer too (the cause was judged at the draw).
  local met = newWorld()
  met.state.events.scheduled = { { id = "fever_cold_night", due = (SUMMER + 1) * 24 + 8, depth = 0 } }
  setTime(met, SUMMER + 1, 9)
  tick(met)
  T.eq(Events.pending(met).id, "fever_cold_night")
end)

T.test("fever: a poor shelter makes it likelier", function()
  local world = newWorld()
  setTime(world, WINTER, 21.5)
  local base = Events.weight(world, "fever_cold_night")
  Ledger.add(world, "smoked_fish", 5) -- a store that draws animals raises exposure
  local ex = Events.exposure(world).multiplier
  T.near(
    Events.weight(world, "fever_cold_night"),
    base * (1 + (ex - 1) * 0.5) / (1 + (Events.exposure(newWorld()).multiplier - 1) * 0.5),
    1e-9
  )
end)

-- Back strain ---------------------------------------------------------------------------------------------------------

T.test(
  "back strain: resting loses a few hours, hauling on halves the carry, stretching out is a little stiff",
  function()
    local world = newWorld()
    setTime(world, AUTUMN, 13)
    answer(world, "back_strain", 1)
    T.near(Status.modifier(world, "workSpeed"), 0.75, 1e-9, "three hours of about twelve")
    T.eq(Status.modifier(world, "carryCapacity"), 1)
    local haul = newWorld()
    setTime(haul, AUTUMN, 13)
    local base = Water.bucketCapacity(haul)
    answer(haul, "back_strain", 2)
    T.eq(Status.get(haul, "back").left, 2)
    T.eq(Status.modifier(haul, "carryCapacity"), 0.5)
    T.truthy(Water.bucketCapacity(haul) < base)
    T.eq(Status.modifier(haul, "workSpeed"), 1, "only the carry suffers")
    local stretch = newWorld()
    setTime(stretch, AUTUMN, 13)
    answer(stretch, "back_strain", "ignore")
    T.eq(Status.modifier(stretch, "carryCapacity"), 0.85)
    T.eq(Status.get(stretch, "stiff").left, 2)
  end
)

-- Burn ----------------------------------------------------------------------------------------------------------------

T.test("stove burn: it needs a stove; a compress costs water, shrugging it off slows the hands", function()
  local world = newWorld()
  setTime(world, AUTUMN, 21.5)
  T.eq(Events.weight(world, "stove_burn"), 0, "no stove, no burn")
  place(world, "wood_stove")
  T.truthy(Events.weight(world, "stove_burn") > 0)
  setTime(world, SUMMER, 21.5)
  T.eq(Events.weight(world, "stove_burn"), 0, "no fire in summer")
  setTime(world, AUTUMN, 9)
  local water = Ledger.get(world, "water")
  answer(world, "stove_burn", 1)
  T.eq(Ledger.get(world, "water"), water + 5 - 1)
  T.eq(Status.count(world), 0, "none")
  setTime(world, AUTUMN + 2, 9)
  world.state.events.last = {}
  answer(world, "stove_burn", 2)
  T.near(Status.modifier(world, "workSpeed"), 0.8, 1e-9)
  T.eq(Status.get(world, "burn").left, 2)
  Status.clear(world, "burn")
  setTime(world, AUTUMN + 4, 9)
  answer(world, "stove_burn", "ignore")
  T.near(Status.modifier(world, "workSpeed"), 0.9, 1e-9)
  T.eq(Status.get(world, "sting").left, 1)
end)

-- Heat exhaustion -----------------------------------------------------------------------------------------------------

T.test("heat exhaustion: summer sun, likelier when dry or in light clothes", function()
  local world = newWorld()
  setTime(world, SUMMER, 13)
  Weather.force(world, "clear")
  local base = Events.weight(world, "heat_exhaustion")
  T.truthy(base > 0)
  Weather.force(world, "cloudy")
  T.eq(Events.weight(world, "heat_exhaustion"), 0, "needs the sun")
  Weather.force(world, "clear")
  world.state.needs.canteen = 0
  T.truthy(Needs.waterOutlook(world).days < cfg.body.thirstyDays)
  T.near(Events.weight(world, "heat_exhaustion"), base * 2, 1e-9, "dehydration")
  world.state.needs.canteen = nil
  world.state.wardrobe.dressed.torso = "tank_top"
  T.near(Events.weight(world, "heat_exhaustion"), base * 1.5, 1e-9, "light clothes")
  setTime(world, WINTER, 13)
  T.eq(Events.weight(world, "heat_exhaustion"), 0, "summer only")
end)

T.test("heat exhaustion: resting costs hours; pushing on needs water and may collapse that afternoon", function()
  local world = newWorld()
  setTime(world, SUMMER, 13)
  answer(world, "heat_exhaustion", 1)
  T.near(Status.modifier(world, "workSpeed"), 0.75, 1e-9)
  T.eq(Status.modifier(world, "waterNeed"), 1)
  cfg.chances.heatCollapse = 1
  local push = newWorld()
  setTime(push, SUMMER, 13)
  push.state.needs.condition = 70
  answer(push, "heat_exhaustion", 2)
  T.eq(Status.modifier(push, "waterNeed"), 1.5, "50 percent more water")
  T.eq(Status.has(push, "collapsed"), false, "not yet")
  setTime(push, SUMMER, 17)
  tick(push)
  T.eq(Status.has(push, "collapsed"), true, "the afternoon is lost")
  T.eq(Needs.condition(push), 60)
  cfg.chances.heatCollapse = 0
  local fine = newWorld()
  setTime(fine, SUMMER, 13)
  fine.state.needs.condition = 70
  answer(fine, "heat_exhaustion", 2)
  setTime(fine, SUMMER, 17)
  tick(fine)
  T.eq(Status.has(fine, "collapsed"), false)
  T.eq(Needs.condition(fine), 70)
  local slow = newWorld()
  setTime(slow, SUMMER, 13)
  answer(slow, "heat_exhaustion", "ignore")
  T.near(Status.modifier(slow, "workSpeed"), 0.7, 1e-9)
  T.eq(#slow.state.events.delayed, 0)
end)

T.test("heat exhaustion: a collapse is never the killing blow", function()
  cfg.chances.heatCollapse = 1
  local world = newWorld()
  setTime(world, SUMMER, 13)
  world.state.needs.condition = 22
  answer(world, "heat_exhaustion", 2)
  setTime(world, SUMMER, 17)
  tick(world)
  T.eq(Needs.condition(world), cfg.mercy.conditionFloor)
end)

-- Bad tooth ------------------------------------------------------------------------------------------------------------

T.test("bad tooth: late-game, a brew and an hour, or study suffers, or a sore tooth", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  T.eq(Events.weight(world, "bad_tooth"), 0, "not in the first year")
  setTime(world, 28 + SPRING, 13)
  T.truthy(Events.weight(world, "bad_tooth") > 0)
  local water = Ledger.get(world, "water")
  answer(world, "bad_tooth", 1)
  T.eq(Ledger.get(world, "water"), water + 5 - 1)
  T.near(Status.modifier(world, "workSpeed"), 0.92, 1e-9)
  T.eq(Status.modifier(world, "studySpeed"), 1)
  local tough = newWorld()
  setTime(tough, 28 + SPRING, 13)
  answer(tough, "bad_tooth", 2)
  T.eq(Status.modifier(tough, "studySpeed"), 0.7)
  T.eq(Status.get(tough, "toothache").left, 3)
  T.eq(Status.modifier(tough, "workSpeed"), 1)
  local nag = newWorld()
  setTime(nag, 28 + SPRING, 13)
  answer(nag, "bad_tooth", "ignore")
  T.eq(Status.modifier(nag, "studySpeed"), 0.9)
end)

-- Mercy ---------------------------------------------------------------------------------------------------------------

T.test("body events: no new one while Footing is slipped, Condition is low or the statuses are full", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  T.truthy(Events.weight(world, "festering_cut") > 0)
  world.state.needs.condition = 20
  T.eq(Events.weight(world, "festering_cut"), 0, "low Condition")
  world.state.needs.condition = 100
  Status.apply(world, "limp")
  Status.apply(world, "tired")
  Status.apply(world, "back")
  T.eq(Status.count(world), 3)
  T.eq(Events.weight(world, "festering_cut"), 0, "the statuses are full")
  local slipped = newWorld()
  setTime(slipped, SPRING, 21.5)
  slipped.state.footing.slipped = true
  T.eq(Events.weight(slipped, "festering_cut"), 0, "Footing is slipped")
end)

T.test("body events: the whole pack ignored, nothing is worse than a few slow days", function()
  -- Every ignore outcome applied in turn: only statuses that cannot escalate, no Condition lost, nothing owed.
  for _, id in ipairs(BODY) do
    local world = newWorld()
    setTime(world, SPRING, 13)
    world.state.needs.condition = 90
    Events.force(world, id)
    Events.ignore(world)
    T.eq(Needs.condition(world), 90, id)
    for _, s in ipairs(Status.active(world)) do
      T.eq(reg:get("statuses", s.id).escalatesTo, nil, id .. " " .. s.id)
    end
    T.eq(#world.state.events.delayed, 0, id)
  end
end)

T.test("body events: a delayed outcome survives a save round trip", function()
  local serialize = require("src.core.serialize")
  local world = newWorld()
  setTime(world, SPRING, 13)
  cfg.chances.festerInfection = 1
  answer(world, "festering_cut", 2)
  local copy = serialize.decode(serialize.encode(world.state))
  local again = World.new({ registry = reg, tuning = tun }, copy)
  T.eq(#again.state.events.delayed, 1)
  setTime(again, SPRING + 2, 9)
  tick(again)
  T.eq(Status.has(again, "infection"), true)
end)

T.test("body events: the dusk draw is not moved by how earlier cards were answered", function()
  local function stream(how)
    local world = newWorld(5)
    setTime(world, SPRING, 13)
    answer(world, "festering_cut", how)
    setTime(world, SPRING + 2, 9)
    tick(world)
    setTime(world, SPRING + 3, 21.5)
    tick(world)
    return world.state.rng.event.s
  end
  T.eq(stream(1), stream(2), "the roll for a delayed outcome has its own stream")
end)

-- The card's words ---------------------------------------------------------------------------------------------------

T.test("the card says a delayed outcome with 'may' and never the odds", function()
  local env = {
    status = function(id)
      return reg:get("statuses", id)
    end,
    name = function(id)
      return reg:get("resources", id).name
    end,
  }
  local leave = EventText.effectWords(reg:get("events", "festering_cut").options[2].effect, env)
  T.eq(#leave, 1)
  T.truthy(leave[1]:find("^Later, it may: Infected cut"), leave[1])
  T.falsy(leave[1]:find("40") or leave[1]:find("percent"), "no odds")
  local power = EventText.effectWords(reg:get("events", "sprained_ankle").options[2].effect, env)
  T.truthy(power[1]:find("^Later: Strained ankle"), power[1])
  local clean = EventText.effectWords(reg:get("events", "festering_cut").options[1].effect, env)
  T.truthy(clean[1]:find("Tending"), clean[1])
end)
