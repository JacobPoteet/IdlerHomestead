-- Misfortune events (D169, #347, docs/PLAN_DEPTH.md §6, src/sim/systems/events.lua): the content audit, the dusk draw (seeded,
-- the quiet start, the budget, the pity timer, the shared night slot), the ignore window (a real-seconds floor, waiting while
-- the player is away), the mercy rules, the effect vocabulary, the save round trip and the sprained ankle end to end.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Events = require("src.sim.systems.events")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")
local Status = require("src.sim.systems.status")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24
local cfg = tun.events

-- Tests change tuning to force a case; every test starts from the shipped values.
local shipped = {}
for k, v in pairs(cfg) do
  if type(v) ~= "table" then
    shipped[k] = v
  end
end
local shippedMercy, shippedYear = {}, cfg.yearScale[1]
for k, v in pairs(cfg.mercy) do
  shippedMercy[k] = v
end
-- The event definitions are shared content (every registry in the process requires the same tables, so another test file
-- sees what this one leaves), and tests edit them to force a case. Every test runs between a deep copy and a restore that
-- always happens, whether or not an assertion failed half way (a failed test used to leave its edit behind).
local function deepCopy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, x in pairs(v) do
    out[k] = deepCopy(x)
  end
  return setmetatable(out, getmetatable(v))
end
local pristine = {}
for _, d in ipairs(reg:all("events")) do
  pristine[d] = deepCopy(d)
end
local function restoreContent()
  for d, copy in pairs(pristine) do
    for k in pairs(d) do
      rawset(d, k, nil) -- (definitions are strict: they refuse a new field)
    end
    for k, v in pairs(deepCopy(copy)) do
      rawset(d, k, v)
    end
  end
end
local test = T.test
T.test = function(name, fn)
  test(name, function()
    restoreContent()
    local ok, err = xpcall(fn, debug.traceback)
    restoreContent()
    if not ok then
      error(err, 0)
    end
  end)
end
local rawTest = T.test
T.test = function(name, fn)
  rawTest(name, function()
    for k, v in pairs(shipped) do
      cfg[k] = v
    end
    for k, v in pairs(shippedMercy) do
      cfg.mercy[k] = v
    end
    cfg.yearScale[1] = shippedYear
    return fn()
  end)
end

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true -- bad events wait for Footing (or day 10); most tests are about the events
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

local function tick(world, n)
  for _ = 1, n or 1 do
    world:tick(STEP)
  end
end

-- Play the days from..to the way the draw sees them: a tick after dusk, one the next morning, one at midday, and one at
-- bedtime; every card is ignored at once. Returns the ids offered with their days.
local function drive(world, from, to)
  local seen = {}
  world.events:on("event.offered", function(e)
    seen[#seen + 1] = e.day .. ":" .. e.id
    Events.ignore(world)
  end)
  for day = from, to do
    for _, hour in ipairs({ 21.5, 23.5 }) do
      setTime(world, day, hour)
      tick(world)
    end
    for _, hour in ipairs({ 9, 14 }) do
      setTime(world, day + 1, hour)
      tick(world)
    end
  end
  return seen
end

-- Content ---------------------------------------------------------------------------------------------

T.test("events: the content audit finds no problem, and catches an unsafe ignore", function()
  local world = newWorld()
  T.same(Events.audit(world), {})
  local d = reg:get("events", "sprained_ankle")
  local safe = d.ignore.effect
  d.ignore.effect = { status = "ankle_1" } -- a status that can escalate
  T.truthy(#Events.audit(world) > 0, "an ignore that can escalate is caught")
  d.ignore.effect = { condition = -5 }
  T.truthy(#Events.audit(world) > 0, "an ignore that costs Condition is caught")
  d.ignore.effect = { status = "limp", chain = { id = "sprained_ankle", afterDays = 1 } }
  T.truthy(#Events.audit(world) > 0, "an ignore with a chain is caught")
  d.ignore.effect = safe
  d.options[1].effect = { capital = true }
  T.truthy(#Events.audit(world) > 0, "a capital outcome with no lesser form is caught")
  d.options[1].effect = { status = "ankle_1" }
  T.same(Events.audit(world), {})
end)

T.test("events: the audit applies each ignore status on every active status of its family", function()
  local world = newWorld()
  local chill = reg:get("statuses", "chill")
  local d = reg:get("events", "sprained_ankle")
  local severity = chill.severity
  d.ignore.effect = { status = "chill" }
  T.same(Events.audit(world), {}, "the chill renews and changes nothing")
  chill.severity = 2 -- a one-off that outranks the infected cut would worsen it
  local problems = Events.audit(world)
  chill.severity = severity
  T.truthy(#problems > 0, "an ignore status that would worsen an active one is caught")
  T.truthy(table.concat(problems, " "):find("on infection", 1, true), "the infected cut is named")
  T.same(Events.audit(world), {})
end)

T.test("events: the demo is the sprained ankle with a free, non-escalating ignore", function()
  local d = reg:get("events", "sprained_ankle")
  T.eq(#d.options, 2)
  T.eq(d.options[1].cost.wood, 2)
  T.eq(d.ignore.effect.status, "limp")
  T.eq(reg:get("statuses", "limp").escalatesTo, nil)
  T.eq(d.ignore.cost, nil)
end)

-- The draw ---------------------------------------------------------------------------------------------

T.test("events: the draw is deterministic by seed and differs between seeds", function()
  local function run(seed)
    local world = newWorld(seed)
    return table.concat(drive(world, 3, 40), ",")
  end
  T.eq(run(7), run(7), "the same seed offers the same events on the same days")
  local differs = false
  for seed = 1, 5 do
    differs = differs or run(seed) ~= run(seed + 1)
  end
  T.truthy(differs, "other seeds draw other nights")
  T.truthy(#run(7) > 0, "events do come over a few weeks")
end)

T.test("events: the draw uses its own stream and takes the same rolls whatever the homestead has", function()
  local a, b = newWorld(3), newWorld(3)
  Ledger.add(b, "smoked_fish", 5)
  setTime(a, 3, 21.5)
  setTime(b, 3, 21.5)
  tick(a)
  tick(b)
  T.eq(a.state.rng.event.s, b.state.rng.event.s, "two rolls whatever the exposure")
  T.eq(a.state.rng.weather ~= nil, true)
  local fresh = newWorld(3)
  T.eq(fresh.state.rng.event, nil, "the stream is created by its first draw")
end)

T.test("events: the quiet start, and no bad event before Footing or the cutoff day", function()
  local world = newWorld()
  cfg.chancePerNight, cfg.maxChance, cfg.yearScale[1] = 1, 1, 1
  setTime(world, 2, 21.5)
  tick(world)
  T.eq(world.state.events.rollDay, 2)
  T.eq(#world.state.events.scheduled, 0, "nothing is drawn before the first night")
  setTime(world, 3, 21.5)
  tick(world)
  T.eq(#world.state.events.scheduled, 1, "from the third night a bad event may come once Footing is held")
  -- Without Footing a bad event waits for the cutoff day.
  local bare = World.new({ registry = reg, tuning = tun }, World.newState(1))
  for day = 3, cfg.badFromDay - 1 do
    setTime(bare, day, 21.5)
    tick(bare)
    T.eq(#bare.state.events.scheduled, 0, "no bad event on day " .. day .. " before Footing")
  end
  setTime(bare, cfg.badFromDay, 21.5)
  tick(bare)
  T.eq(#bare.state.events.scheduled, 1, "the cutoff day lets it come")
  -- A mild event is not held back by it.
  local mild = World.new({ registry = reg, tuning = tun }, World.newState(1))
  reg:get("events", "sprained_ankle").bad = false
  setTime(mild, 3, 21.5)
  tick(mild)
  T.eq(#mild.state.events.scheduled, 1, "a mild event comes from the third night")
  reg:get("events", "sprained_ankle").bad = true
end)

T.test("events: the chance follows exposure, the year and the pity timer", function()
  local world = newWorld()
  local x = tun.night.exposure
  local base = Events.exposure(world)
  T.eq(base.points, x.neutral + x.shelter.truck, "the truck gives a night the most to work with")
  T.near(Events.chance(world), cfg.chancePerNight * cfg.yearScale[1] * base.multiplier, 1e-9)
  Ledger.add(world, "smoked_fish", 1)
  Ledger.add(world, "cheese", 1)
  T.truthy(Events.exposure(world).points > base.points, "stores that attract animals raise it")
  Ledger.add(world, "hay", 40)
  Ledger.add(world, "chicken_feed", 40)
  T.truthy(Events.exposure(world).points <= x.max, "clamped")
  T.near(
    world.tuning.night.exposure.chanceAtMin + (x.chanceAtMax - x.chanceAtMin) * 0.5,
    (x.chanceAtMin + x.chanceAtMax) / 2,
    1e-9
  )
  local before = Events.chance(world)
  world.state.events.quiet = cfg.pityNights - 1
  T.near(Events.chance(world), before, 1e-9, "no pity yet")
  world.state.events.quiet = cfg.pityNights
  T.near(
    Events.chance(world),
    math.min(cfg.maxChance, before + cfg.pityBoost),
    1e-9,
    "the pity timer starts to lift it"
  )
  world.state.events.quiet = 100
  T.eq(Events.chance(world), cfg.maxChance, "never certain")
  setTime(world, 30, 12) -- year 1 still; a later year is not gentler
  world.state.calendar.elapsed = world.state.calendar.elapsed + 4 * 28 * tun.time.dayLength
  T.truthy(Calendar.now(world).year >= 2)
  world.state.events.quiet = 0
  T.near(
    Events.chance(world),
    cfg.chancePerNight * cfg.yearScale[#cfg.yearScale] * Events.exposure(world).multiplier,
    1e-9
  )
end)

T.test("events: no backlog builds up while the player is away or a card is open", function()
  local world = newWorld()
  cfg.chancePerNight, cfg.yearScale[1], cfg.maxChance = 1, 1, 1
  Events.setAway(world, true)
  for day = 12, 17 do
    setTime(world, day, 21.5)
    tick(world)
    T.eq(world.state.events.rollDay, day, "the dusk is still marked done")
  end
  T.eq(#world.state.events.scheduled, 0, "six dusks away, nothing queued")
  T.eq(#world.state.events.pending, 0)
  T.eq(world.state.events.quiet, 0, "the pity timer did not move while nothing was drawn")
  -- Back: the next dusk draws as usual (one event, not a pile).
  Events.setAway(world, false)
  setTime(world, 18, 21.5)
  tick(world)
  T.eq(#world.state.events.scheduled + #world.state.events.pending, 1)
  -- A card left open holds the draw too.
  local queued = #world.state.events.scheduled + #world.state.events.pending
  Events.force(world, "sprained_ankle")
  setTime(world, 19, 21.5)
  tick(world)
  T.eq(#world.state.events.scheduled + #world.state.events.pending, queued + 1, "only the forced card was added")
end)

T.test("events: the pity timer counts quiet nights and resets on an occurrence", function()
  local world = newWorld()
  cfg.chancePerNight, cfg.yearScale[1] = 0, 0
  cfg.pityBoost = 0
  for day = 3, 6 do
    setTime(world, day, 21.5)
    tick(world)
  end
  T.eq(world.state.events.quiet, 4, "four quiet nights")
  cfg.chancePerNight, cfg.yearScale[1], cfg.maxChance = 1, 1, 1
  setTime(world, 7, 21.5)
  tick(world)
  T.eq(world.state.events.quiet, 0, "an event resets it")
end)

T.test("events: a bad outcome starts a cooldown, a turned-away threat uses the slot but starts none", function()
  local world = newWorld()
  cfg.chancePerNight, cfg.maxChance, cfg.yearScale[1] = 1, 1, 1
  setTime(world, 3, 21.5)
  Events.force(world, "sprained_ankle")
  Events.ignore(world)
  T.eq(world.state.events.coolUntil, 3 + cfg.badCooldownNights)
  for day = 4, 5 do
    setTime(world, day, 21.5)
    tick(world)
    T.eq(#world.state.events.scheduled, 0, "the cooldown holds the draw on day " .. day)
  end
  -- A threat claims the night's slot first: the event draw skips the night.
  local w2 = newWorld()
  cfg.chancePerNight = 1
  setTime(w2, 8, 21.5)
  T.truthy(Events.claimSlot(w2, "threat", "fox"))
  T.falsy(Events.claimSlot(w2, "event", "x"), "one slot a night")
  w2.state.events.quiet = 3
  tick(w2)
  T.eq(#w2.state.events.scheduled, 0, "no event on a night a threat took the slot")
  Events.slotOutcome(w2, "turned")
  T.eq(w2.state.events.quiet, 0, "a turned-away threat resets the pity timer")
  T.eq(w2.state.events.coolUntil, 0, "and starts no cooldown")
  Events.slotOutcome(w2, "landed")
  T.eq(w2.state.events.coolUntil, 8 + cfg.badCooldownNights, "a landed one does")
  T.errors(function()
    Events.slotOutcome(w2, "maybe")
  end)
end)

T.test("events: the day's budget holds a second event for the next day", function()
  local world = newWorld()
  setTime(world, 9, 13)
  local s = world.state.events
  s.scheduled = {
    { id = "sprained_ankle", due = 9 * 24 + 12, depth = 0 },
    { id = "sprained_ankle", due = 9 * 24 + 12, depth = 0 },
  }
  tick(world)
  T.eq(#s.pending, 1)
  Events.ignore(world)
  tick(world)
  T.eq(#s.pending, 0, "the budget is spent for the day")
  T.eq(#s.scheduled, 1)
  T.eq(s.scheduled[1].due, 9 * 24 + 12 + 24, "it waits a day")
  setTime(world, 10, 13)
  tick(world)
  T.eq(#s.pending, 1)
end)

-- The ignore window ---------------------------------------------------------------------------------------

T.test(
  "events: the ignore window needs game time and a real-seconds floor, and waits while the player is away",
  function()
    local world = newWorld()
    local ignored = collect(world, "event.ignored")
    setTime(world, 5, 13)
    Events.force(world, "sprained_ankle")
    -- Game time alone (a fast speed) is not enough.
    for _ = 1, math.ceil(cfg.ignoreHours * HOUR / STEP) + 5 do
      tick(world)
    end
    T.eq(#ignored, 0, "the real-seconds floor has not passed")
    T.truthy(Events.pending(world).hoursLeft <= 0)
    -- Real time alone is not enough either.
    local other = newWorld()
    setTime(other, 5, 13)
    Events.force(other, "sprained_ankle")
    Events.advanceReal(other, cfg.ignoreMinSeconds + 5)
    tick(other)
    T.eq(#other.state.events.pending, 1, "the game-time half has not passed")
    -- Away: neither half runs, and no new event is offered behind the card.
    local away = newWorld()
    setTime(away, 5, 13)
    Events.force(away, "sprained_ankle")
    Events.setAway(away, true)
    local h = Events.pending(away).hoursLeft
    Events.advanceReal(away, 1000)
    for _ = 1, 400 do
      tick(away)
    end
    T.eq(Events.pending(away).hoursLeft, h, "game time waits")
    T.eq(Events.pending(away).realLeft, cfg.ignoreMinSeconds, "real time waits")
    away.state.events.scheduled = { { id = "sprained_ankle", due = 0, depth = 0 } }
    tick(away)
    T.eq(#away.state.events.pending, 1, "nothing is offered behind it")
    Events.setAway(away, false)
    Events.advanceReal(away, cfg.ignoreMinSeconds)
    for _ = 1, math.ceil(cfg.ignoreHours * HOUR / STEP) + 5 do
      tick(away)
    end
    T.eq(Status.has(away, "limp"), true, "back, the window runs out and the ignore outcome applies")
    -- Both halves spent: the ignore outcome.
    Events.advanceReal(world, cfg.ignoreMinSeconds)
    tick(world)
    T.eq(#ignored, 1)
    T.eq(ignored[1].reason, "expired")
    T.eq(Status.has(world, "limp"), true)
    T.eq(Status.get(world, "limp").left, 2, "today and tomorrow")
    T.eq(Events.pending(world), nil)
  end
)

T.test("events: the ignore path is free, writes the journal note and never escalates", function()
  local world = newWorld()
  Ledger.add(world, "wood", 10)
  local wood = Ledger.get(world, "wood")
  setTime(world, 5, 13)
  Events.force(world, "sprained_ankle")
  T.truthy(Events.ignore(world))
  T.eq(Ledger.get(world, "wood"), wood, "costs nothing")
  T.truthy(Journal.hasNote(world, "limped_on"))
  T.truthy(Journal.hasNote(world, "ankle_sprain"))
  T.eq(Status.inFamily(world, "limp").id, "limp")
  Status.apply(world, "limp")
  T.eq(Status.get(world, "limp").severity, 1, "a second one only renews it")
  T.eq(Events.history(world)[1].how, "ignored")
end)

-- Choosing -------------------------------------------------------------------------------------------------

T.test("events: choosing pays the cost, applies the effect and reports it", function()
  local world = newWorld()
  local chosen = collect(world, "event.chosen")
  local offered = collect(world, "event.offered")
  setTime(world, 5, 13)
  T.eq(select(2, Events.choose(world, 1)), "no event")
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Events.force(world, "sprained_ankle")
  T.eq(offered[1].id, "sprained_ankle")
  local view = Events.pending(world)
  T.eq(view.options[1].affordable, false)
  T.eq(view.options[1].lacking, "wood")
  T.eq(view.options[1].careful, true)
  T.eq(view.options[2].bold, true)
  T.eq(view.ignore.label, "Limp on")
  T.eq(select(2, Events.choose(world, 1)), "lacks wood")
  T.eq(select(2, Events.choose(world, 3)), "no such option")
  Ledger.add(world, "wood", 5)
  T.truthy(Events.choose(world, 1))
  T.eq(Ledger.get(world, "wood"), 3)
  T.eq(Status.has(world, "ankle_1"), true)
  T.eq(chosen[1].option, 1)
  T.eq(Events.pending(world), nil)
  -- Power through: no cost, no slowdown today, and the strained ankle tomorrow morning.
  Status.clear(world, "ankle_1")
  setTime(world, 12, 13)
  world.state.events.budget.day = 0
  Events.force(world, "sprained_ankle")
  T.truthy(Events.choose(world, 2))
  T.eq(Status.count(world), 0, "fine today")
  setTime(world, 13, 8)
  tick(world)
  T.eq(Status.get(world, "ankle_2").severity, 2, "strained tomorrow")
  T.eq(Events.force(world, "sprained_ankle"), true)
  T.eq(Events.force(world, "sprained_ankle"), false, "one card at a time")
end)

-- Mercy -------------------------------------------------------------------------------------------------------

T.test("events: mercy keys on Footing, Condition and the statuses", function()
  local world = newWorld()
  setTime(world, 12, 13)
  local d = reg:get("events", "sprained_ankle")
  T.truthy(Events.weight(world, "sprained_ankle") > 0)
  world.state.footing.slipped = true
  T.eq(Events.blocked(world, d), "slipped")
  T.eq(Events.weight(world, "sprained_ankle"), 0, "no new bad events while Footing is slipped")
  world.state.footing.slipped = false
  world.state.needs.condition = cfg.mercy.lowCondition - 1
  T.eq(Events.blocked(world, d), "low condition")
  world.state.needs.condition = 100
  Status.apply(world, "fever")
  Status.apply(world, "back")
  Status.apply(world, "burn")
  T.eq(Events.blocked(world, d), "statuses full")
  -- A scheduled event is dropped, not offered, when the rules no longer allow it.
  world.state.events.scheduled = { { id = "sprained_ankle", due = 0, depth = 0 } }
  tick(world)
  T.eq(#world.state.events.pending, 0)
  T.eq(Events.history(world)[1].how, "dropped")
  -- A mild event still comes while slipped; a low Condition stops every event.
  local fresh = newWorld()
  setTime(fresh, 12, 13)
  d.bad = false
  fresh.state.footing.slipped = true
  T.truthy(Events.weight(fresh, "sprained_ankle") > 0, "luck that costs nothing can come")
  fresh.state.needs.condition = 1
  T.eq(Events.weight(fresh, "sprained_ankle"), 0, "but not to someone near collapse")
  d.bad = true
end)

T.test("events: an outcome never takes Condition under the floor, and Fever skips a cold night", function()
  local world = newWorld()
  setTime(world, 12, 13)
  local d = reg:get("events", "sprained_ankle")
  d.options[2].effect = { condition = -90 }
  Events.force(world, "sprained_ankle")
  Events.choose(world, 2)
  T.eq(Needs.condition(world), cfg.mercy.conditionFloor)
  T.eq(Needs.injure(world, 50, cfg.mercy.conditionFloor), 0, "already at the floor")
  world.state.needs.condition = 100
  world.state.events.last = {}
  d.conditions.noColdNight = true
  world.state.events.coldDay = Calendar.now(world).day
  T.eq(Events.weight(world, "sprained_ankle"), 0, "the night already cost cold damage")
  world.state.events.coldDay = 0
  T.truthy(Events.weight(world, "sprained_ankle") > 0)
  d.conditions.noColdNight = nil
  -- A cold night noted by the needs system.
  local cold = newWorld()
  cold.events:emit("needs.warmed", { shortfall = 0.3, needed = 5, warmth = 2, electric = 0, burned = 1 })
  T.eq(cold.state.events.coldDay, Calendar.now(cold).day)
end)

T.test("events: capital outcomes are swapped while slipped, and damage is capped", function()
  local world = newWorld()
  local effect = { capital = true, status = "burn", lesser = { lose = { wood = 1 } } }
  T.eq(Events.effective(world, effect), effect)
  world.state.footing.slipped = true
  T.eq(Events.effective(world, effect), effect.lesser, "the lesser form while slipped")
  T.same(Events.effective(world, { capital = true }), {}, "or nothing")
  world.state.footing.slipped = false
  local dmg = { damage = { "torn_canvas" }, lesser = { lose = { wood = 1 } } }
  T.eq(Events.effective(world, dmg), dmg)
  world.state.events.damage.torn_canvas = true
  world.state.events.damage.wrecked_fence = true
  T.eq(#Events.openDamage(world), cfg.mercy.maxOpenDamage)
  T.eq(Events.effective(world, dmg), dmg, "a flag already open adds nothing")
  T.eq(Events.effective(world, { damage = { "clogged_flue" }, lesser = dmg.lesser }), dmg.lesser, "at the cap")
  T.truthy(Events.repair(world, "torn_canvas"))
  T.falsy(Events.hasDamage(world, "torn_canvas"))
  T.eq(Events.effective(world, { damage = { "clogged_flue" }, lesser = dmg.lesser }).damage[1], "clogged_flue")
end)

T.test("events: the warmth need has a ceiling on bad luck and is exactly as before with none", function()
  local world = newWorld()
  local winter = 3 * tun.time.daysPerSeason + 3
  setTime(world, winter, 12)
  world.state.calendar.day = winter
  T.truthy(Weather.isFrozen(world))
  local natural = Weather.warmthNeed(world) * Shelter.nightInsulation(world)
  T.near(Needs.warmthNeeded(world), natural, 1e-9, "nothing active: unchanged")
  Status.apply(world, "fever")
  cfg.mercy.maxWarmthMultiplier = 100
  T.near(Needs.warmthNeeded(world), natural * 1.15, 1e-9, "a fever asks for more")
  cfg.mercy.maxWarmthMultiplier = 0.01
  T.near(Needs.warmthNeeded(world), natural, 1e-9, "the ceiling never lowers what the weather already asks")
  cfg.mercy.maxWarmthMultiplier = 2.0
end)

-- Effects ------------------------------------------------------------------------------------------------------

T.test("events: the effect vocabulary - resources, flags, tiles, notes and chains", function()
  local world = newWorld()
  setTime(world, 12, 13)
  world.state.crops[10] = { id = "radish", growth = 0.5 }
  world.state.crops[11] = { id = "radish", growth = 0.5 }
  local d = reg:get("events", "sprained_ankle")
  cfg.maxChainDepth = 1
  d.options[2].effect = {
    gain = { stone = 3 },
    lose = { wood = 5 },
    flags = { limped_recently = 2, sticky = true },
    lockTiles = { count = 1, days = 2 },
    damageTiles = { count = 2, setback = 0.2 },
    note = "limped_on",
    chain = { id = "sprained_ankle", afterDays = 1 },
  }
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Ledger.add(world, "wood", 2)
  local stone = Ledger.get(world, "stone")
  Events.force(world, "sprained_ankle")
  Events.choose(world, 2)
  T.eq(Ledger.get(world, "stone"), stone + 3)
  T.eq(Ledger.get(world, "wood"), 0, "a loss takes at most what is there")
  T.truthy(Events.flag(world, "limped_recently"))
  T.truthy(Events.flag(world, "sticky"))
  T.near(world.state.crops[10].growth, 0.3, 1e-9)
  T.truthy(Journal.hasNote(world, "limped_on"))
  world.state.crops[10], world.state.crops[11] = nil, nil -- (the stand-ins would trip the crop tick)
  local locked = Events.tileLocked(world, 10) or Events.tileLocked(world, 11)
  T.truthy(locked, "one planted tile is locked")
  T.eq(#Events.scheduled(world), 1, "a follow-up is queued")
  -- Days pass: the flag and the lock run out, the follow-up comes with its depth spent.
  setTime(world, 14, 12)
  world.events:emit("calendar.newDay", { day = 14, season = "spring", year = 1 })
  T.falsy(Events.flag(world, "limped_recently"))
  T.truthy(Events.flag(world, "sticky"), "until cleared")
  T.falsy(Events.tileLocked(world, 10) or Events.tileLocked(world, 11))
  tick(world)
  T.eq(#world.state.events.pending, 1)
  Events.choose(world, 2)
  T.eq(#Events.scheduled(world), 0, "the chain ends at the depth limit")
  cfg.maxChainDepth = 2
end)

T.test("events: one wake a night", function()
  local world = newWorld()
  local d = reg:get("events", "sprained_ankle")
  d.wake = true
  setTime(world, 12, 23)
  Events.force(world, "sprained_ankle")
  Events.ignore(world)
  world.state.events.budget.count = 0
  world.state.events.scheduled = { { id = "sprained_ankle", due = 0, depth = 0 } }
  tick(world)
  T.eq(#world.state.events.pending, 0, "a second wake the same night is dropped")
  T.eq(Events.history(world)[2].reason, "one wake a night")
  d.wake = false
end)

-- Journal API -----------------------------------------------------------------------------------------------------

T.test("journal: Journal.write and the once-per-run flag", function()
  local world = newWorld()
  local notes = collect(world, "journal.note")
  T.truthy(Journal.write(world, "limped_on"))
  T.falsy(Journal.write(world, "limped_on"), "already written")
  T.eq(#notes, 1)
  T.errors(function()
    Journal.write(world, "no_such_note")
  end)
  T.eq(world.state.journal, nil, "no run state until a flag is asked")
  T.truthy(Journal.once(world, "stray_dog"))
  T.falsy(Journal.once(world, "stray_dog"))
  T.truthy(Journal.once(world, "other"))
  T.truthy(Journal.once(newWorld(), "stray_dog"), "a new run asks again")
end)

-- Save ----------------------------------------------------------------------------------------------------------------

T.test("events: a save round trip keeps the queue, the window and the draw", function()
  local world = newWorld(5)
  setTime(world, 12, 13)
  Events.force(world, "sprained_ankle")
  world.state.events.scheduled[1] = { id = "sprained_ankle", due = 400, depth = 1 }
  Events.advanceReal(world, 10)
  tick(world, 20)
  world.state.events.damage.torn_canvas = true
  world.state.events.flags.sticky = true
  local copy = serialize.decode(serialize.encode(world.state))
  local loaded = World.new({ registry = reg, tuning = tun }, copy)
  T.same(loaded.state.events, world.state.events)
  local view = Events.pending(loaded)
  T.eq(view.id, "sprained_ankle")
  T.near(view.realLeft, cfg.ignoreMinSeconds - 10, 1e-9)
  T.eq(Events.hasDamage(loaded, "torn_canvas"), true)
  Events.advanceReal(loaded, 100)
  for _ = 1, math.ceil(cfg.ignoreHours * HOUR / STEP) do
    tick(loaded)
  end
  T.eq(Status.has(loaded, "limp"), true, "the loaded card still runs out into its ignore outcome")
  -- The draw continues from the saved stream.
  local a, b = newWorld(9), newWorld(9)
  setTime(a, 3, 21.5)
  tick(a)
  local c = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  setTime(b, 3, 21.5)
  tick(b)
  setTime(c, 4, 21.5)
  setTime(b, 4, 21.5)
  tick(b)
  tick(c)
  T.eq(c.state.rng.event.s, b.state.rng.event.s)
end)

T.test("events: a loaded save drops an event the content no longer has", function()
  local world = newWorld()
  world.state.events.scheduled[1] = { id = "gone", due = 1, depth = 0 }
  world.state.events.pending[1] = { id = "gone", day = 1, hoursLeft = 1, realLeft = 1, depth = 0 }
  local loaded = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(#loaded.state.events.scheduled, 0)
  T.eq(#loaded.state.events.pending, 0)
end)

-- End to end -----------------------------------------------------------------------------------------------------------

T.test("events: the sprained ankle, end to end through the real clock", function()
  local world = newWorld(2)
  cfg.chancePerNight, cfg.maxChance, cfg.yearScale[1] = 1, 1, 1
  local offered = collect(world, "event.offered")
  local ignored = collect(world, "event.ignored")
  setTime(world, 4, 20.9)
  local steps = 0
  while #offered == 0 and steps < 3 * tun.time.dayLength / STEP do
    tick(world)
    steps = steps + 1
  end
  T.eq(#offered, 1, "the draw hit and the event came at its hour")
  T.eq(offered[1].id, "sprained_ankle")
  T.truthy(Journal.hasNote(world, "ankle_sprain"), "the first occurrence writes the note")
  T.eq(Events.pending(world).id, "sprained_ankle")
  -- Nobody answers: time never waited, and after the window the ankle is the free "limped on".
  Events.advanceReal(world, cfg.ignoreMinSeconds)
  for _ = 1, math.ceil(cfg.ignoreHours * HOUR / STEP) + 2 do
    tick(world)
  end
  T.eq(#ignored, 1)
  T.eq(Status.has(world, "limp"), true)
  T.eq(Events.pending(world), nil)
  -- Two midnights later the limp is gone.
  world.events:emit("calendar.newDay", { day = 6, season = "spring", year = 1 })
  T.eq(Status.has(world, "limp"), true)
  world.events:emit("calendar.newDay", { day = 7, season = "spring", year = 1 })
  T.eq(Status.has(world, "limp"), false)
end)

T.test("events: switched off, nothing is drawn or offered", function()
  local world = newWorld()
  cfg.enabled = false
  cfg.chancePerNight, cfg.maxChance, cfg.yearScale[1] = 1, 1, 1
  T.eq(#drive(world, 3, 12), 0)
  T.eq(world.state.rng.event, nil)
  cfg.enabled = true
end)
