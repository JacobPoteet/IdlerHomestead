-- Standing orders (B5, #349, D174, docs/PLAN_DEPTH.md 6.4): per event class Ask me / Careful / Bold, unlocked by the "Rules of
-- thumb" journal perk. Careful respects keep targets and the winter wood reserve and falls back to ignoring (with a morning-report
-- line) when it cannot pay or would eat a reserve; until the perk is known nothing changes.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Events = require("src.sim.systems.events")
local Food = require("src.sim.systems.food")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Status = require("src.sim.systems.status")
local NightText = require("src.ui.night_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.events

local function newWorld()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(1))
  world.state.footing.held = true
  return world
end

local function withRules(world)
  world.meta.journal.known[cfg.ordersPerk] = true
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

-- Sets the wood stock. The automatic keep target holds a whole winter of wood from the first day, so a test that is not about
-- the reserve sets its own target at zero.
local function setWood(world, n, keep)
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Ledger.add(world, "wood", n)
  if keep then
    Food.setKeep(world, "wood", keep)
  end
end

-- sprained_ankle: option 1 "Splint it" (2 wood, careful), option 2 "Power through" (free, bold), ignore "Limp on".
local function sprain(world)
  setTime(world, 5, 13)
  T.truthy(Events.force(world, "sprained_ankle"))
end

local function morningLine(world, needle)
  local report = world.state.nightly.open
  report.hours, report.conditionFrom, report.conditionTo = 8, 100, 100
  for _, line in ipairs(NightText.morning(world, report)) do
    if line.text:find(needle, 1, true) then
      return line.text
    end
  end
end

T.test("orders: the perk is a journal node and the default is Ask me", function()
  local world = newWorld()
  T.eq(Journal.kindOf(world, cfg.ordersPerk), "perks")
  T.eq(Journal.chapterOf(world, cfg.ordersPerk), "habits")
  T.eq(Events.ordersUnlocked(world), false)
  for _, class in ipairs(Events.CLASSES) do
    T.eq(Events.orderMode(world, class), "ask")
  end
  Events.setOrder(world, "body", "careful")
  T.eq(world.meta.standingOrders.body, "careful", "kept in the slot meta, so a failed run keeps the rules")
  Events.setOrder(world, "body", "ask")
  T.eq(next(world.meta.standingOrders), nil, "Ask me stores nothing")
  T.errors(function()
    Events.setOrder(world, "weather", "careful")
  end, "class")
  T.errors(function()
    Events.setOrder(world, "body", "reckless")
  end, "order")
end)

T.test("orders: without the perk a set rule does nothing and the card waits for its window", function()
  local world = newWorld()
  Events.setOrder(world, "body", "careful")
  sprain(world)
  T.eq(Events.pending(world).id, "sprained_ankle", "the card is still open")
  T.truthy(Events.ignore(world, "expired"))
  T.eq(Status.has(world, "limp"), true, "the ignore outcome applies when the window passes")
  T.eq(Events.history(world)[1].how, "ignored")
end)

T.test("orders: Ask me leaves the card open even with the perk", function()
  local world = withRules(newWorld())
  sprain(world)
  T.eq(Events.pending(world).id, "sprained_ankle")
end)

T.test("orders: Careful pays for the flagged option, at once, and says it was an order", function()
  local world = withRules(newWorld())
  setWood(world, 10, 0)
  Events.setOrder(world, "body", "careful")
  local chosen = collect(world, "event.chosen")
  local fallbacks = collect(world, "event.orderFallback")
  sprain(world)
  T.eq(Events.pending(world), nil, "no card: the rule answered")
  T.eq(#chosen, 1)
  T.eq(chosen[1].option, 1)
  T.eq(chosen[1].order, true)
  T.eq(chosen[1].label, "Splint it")
  T.eq(Ledger.get(world, "wood"), 8, "the cost was paid")
  T.eq(Status.has(world, "ankle_1"), true)
  T.eq(#fallbacks, 0)
  T.truthy(Journal.hasNote(world, "ankle_sprain"), "the Journal note is still written")
  local h = Events.history(world)[1]
  T.eq(h.how, "chosen")
  T.eq(h.reason, "order")
end)

T.test("orders: Bold takes the free flagged option", function()
  local world = withRules(newWorld())
  setWood(world, 10, 0)
  Events.setOrder(world, "body", "bold")
  local chosen = collect(world, "event.chosen")
  sprain(world)
  T.eq(Events.pending(world), nil)
  T.eq(chosen[1].option, 2)
  T.eq(chosen[1].order, true)
  T.eq(Ledger.get(world, "wood"), 10, "Bold costs nothing")
  T.eq(#world.state.events.delayed, 1, "Power through lands later, as when chosen by hand")
  T.truthy(Journal.hasNote(world, "ankle_sprain"))
end)

T.test("orders: an unaffordable Careful option falls back to ignore and tells the morning report", function()
  local world = withRules(newWorld())
  setWood(world, 1, 0)
  Events.setOrder(world, "body", "careful")
  local ignored = collect(world, "event.ignored")
  local chosen = collect(world, "event.chosen")
  local fallbacks = collect(world, "event.orderFallback")
  sprain(world)
  T.eq(Events.pending(world), nil)
  T.eq(#chosen, 0)
  T.eq(ignored[1].reason, "order")
  T.eq(ignored[1].label, "Limp on")
  T.eq(Ledger.get(world, "wood"), 1, "nothing was spent")
  T.eq(Status.has(world, "limp"), true)
  T.eq(Status.has(world, "ankle_1"), false)
  T.eq(fallbacks[1].why, "short")
  T.eq(fallbacks[1].resource, "wood")
  T.eq(world.state.nightly.open.orders[1].why, "short")
  T.eq(morningLine(world, "ignored the sprained ankle"), "No wood to spare, ignored the sprained ankle.")
end)

T.test("orders: Careful will not eat a keep target, and says what it kept", function()
  local world = withRules(newWorld())
  setWood(world, 10)
  Food.setKeep(world, "wood", 10) -- the player keeps all ten
  Events.setOrder(world, "body", "careful")
  local ignored = collect(world, "event.ignored")
  local fallbacks = collect(world, "event.orderFallback")
  sprain(world)
  T.eq(Events.pending(world), nil)
  T.eq(ignored[1].reason, "order")
  T.eq(fallbacks[1].why, "keep")
  T.eq(Ledger.get(world, "wood"), 10, "the wood stays")
  T.eq(morningLine(world, "Kept the wood"), "Kept the wood, ignored the sprained ankle.")
  -- With room to spare above the target, the same rule pays.
  local again = withRules(newWorld())
  setWood(again, 12)
  Food.setKeep(again, "wood", 10)
  Events.setOrder(again, "body", "careful")
  sprain(again)
  T.eq(Ledger.get(again, "wood"), 10, "two above the target: paid, down to the target exactly")
  T.eq(Status.has(again, "ankle_1"), true)
end)

T.test("orders: Careful will not eat the winter wood reserve", function()
  local world = withRules(newWorld())
  setTime(world, 60, 13) -- late autumn: the winter ahead is counted
  setWood(world, 100)
  local keep = Food.keep(world, "wood")
  T.eq(keep > 2, true, "a winter reserve is held for wood")
  T.eq(select(2, Food.keep(world, "wood")), true, "and it is the automatic one, not the player's")
  local stock = Ledger.get(world, "wood")
  Events.setOrder(world, "body", "careful")
  local fallbacks = collect(world, "event.orderFallback")
  T.truthy(Events.force(world, "sprained_ankle"))
  T.eq(Events.pending(world), nil)
  T.eq(fallbacks[1].why, "keep")
  T.eq(Ledger.get(world, "wood"), stock, "the reserve stays")
end)

T.test("orders: a rule applies to its own class only", function()
  local world = withRules(newWorld())
  setWood(world, 10, 0)
  Events.setOrder(world, "home", "bold")
  Events.setOrder(world, "land", "careful")
  sprain(world) -- a body event
  T.eq(Events.pending(world).id, "sprained_ankle", "the body class is still Ask me")
end)

T.test("orders: a standing order answers a scheduled event the same way", function()
  local world = withRules(newWorld())
  setWood(world, 10, 0)
  Events.setOrder(world, "body", "bold")
  local chosen = collect(world, "event.chosen")
  setTime(world, 5, 12)
  world.state.events.scheduled[1] = { id = "sprained_ankle", due = 5 * 24 + 12, depth = 0 }
  for _ = 1, 3 do
    world:tick(STEP)
  end
  T.eq(#chosen, 1)
  T.eq(chosen[1].order, true)
  T.eq(Events.waiting(world), 0)
end)
