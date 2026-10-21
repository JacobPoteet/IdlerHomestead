-- The event card (D172, #348, docs/PLAN_DEPTH.md §4, §6.2, §6.3): the ranked notice queue (one card at a time, the order in
-- one place), the card's words (cost, effect, risk, the disabled reason, the ignore line, the timer), the card's buttons
-- (touch-sized, Tab and Enter, a tap outside is not the card's), and the ignore window's rules the card relies on.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Events = require("src.sim.systems.events")
local Ledger = require("src.sim.systems.ledger")
local EventCard = require("src.ui.event_card")
local EventText = require("src.ui.event_text")
local Notices = require("src.ui.notices")
local Tonight = require("src.ui.tonight")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

local function newWorld()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(3))
  world.state.footing.held = true
  return world
end

local function env(world, extra)
  local e = {
    name = function(id)
      return reg:get("resources", id).name
    end,
    have = function(id)
      return Ledger.get(world, id)
    end,
    status = function(id)
      return reg:get("statuses", id)
    end,
    away = false,
    speed = 1,
    hourSeconds = HOUR,
    ignoreHours = tun.events.ignoreHours,
    ignoreMinSeconds = tun.events.ignoreMinSeconds,
  }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  return e
end

local function model(world, extra)
  return EventText.build(Events.pending(world), env(world, extra))
end

-- The notice queue ------------------------------------------------------------------------------------------------

T.test("notices: one rank in tuning, Tonight before events, and the first waiting is up", function()
  local rank = tun.ui.notices.rank
  local at = {}
  for i, id in ipairs(rank) do
    at[id] = i
  end
  T.truthy(at.tonight and at.event, "Tonight and events are ranked")
  T.truthy(at.tonight < at.event, "Tonight comes first (PLAN_DEPTH principle 8)")
  T.eq(Notices.pick(rank, { event = true }, nil), "event")
  T.eq(Notices.pick(rank, { event = true, tonight = true }, nil), "tonight", "the higher rank wins a tie")
  T.eq(Notices.pick(rank, {}, nil), nil, "nothing waiting, nothing up")
  T.eq(Notices.pick(rank, { levy = true, contract = true }, nil), "contract")
end)

T.test("notices: a card that is up keeps its place until it is answered", function()
  local rank = tun.ui.notices.rank
  T.eq(
    Notices.pick(rank, { event = true, tonight = true }, "event"),
    "event",
    "Tonight does not push an open event out"
  )
  T.eq(Notices.pick(rank, { event = true, tonight = true }, "tonight"), "tonight", "nor the other way round")
  T.eq(Notices.pick(rank, { tonight = true }, "event"), "tonight", "an answered card gives the screen to the next")
end)

-- The words ---------------------------------------------------------------------------------------------------------

T.test("event text: the cost and the effect of each option in plain words, and the ignore outcome always", function()
  local world = newWorld()
  Ledger.add(world, "wood", 5)
  Events.force(world, "sprained_ankle")
  local m = model(world)
  T.eq(m.title, "Sprained ankle")
  T.eq(#m.options, 2)
  T.eq(m.options[1].cost, "Costs 2 wood")
  T.eq(m.options[2].cost, "Free")
  T.truthy(m.options[1].effects[1]:find("Hobbling"), "the splint says what it does: " .. m.options[1].effects[1])
  T.truthy(m.options[1].effects[1]:find("1 day"), "and for how long")
  T.truthy(m.options[2].effects[1]:find("Strained"))
  T.truthy(m.options[1].risk:find("Safe") and m.options[2].risk:find("Risky"), "the qualitative risk, in words")
  T.truthy(m.options[1].enabled and m.options[2].enabled)
  T.eq(m.options[1].reason, nil)
  T.truthy(m.ignore.head:find("Limp on"), "the ignore outcome is named: " .. m.ignore.head)
  T.eq(m.ignore.cost, "Free", "the ignore outcome is free")
  T.truthy(m.ignore.effects[1]:find("Limping"))
  T.truthy(m.ignore.risk:find("Safe"), "and safe")
end)

T.test("event text: an option the player cannot pay is disabled with the reason", function()
  local world = newWorld()
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Ledger.add(world, "wood", 1)
  Events.force(world, "sprained_ankle")
  local m = model(world)
  T.falsy(m.options[1].enabled, "two wood is not one")
  T.eq(m.options[1].reason, "Needs wood: you have 1")
  T.truthy(m.options[2].enabled, "the free option is always open")
  T.truthy(m.ignore, "and so is the ignore outcome")
  -- The engine agrees with the card.
  local ok, why = Events.choose(world, 1)
  T.falsy(ok)
  T.eq(why, "lacks wood")
  Ledger.add(world, "wood", 1)
  T.truthy(model(world).options[1].enabled, "the card follows the stock")
end)

T.test("event text: effect words cover the vocabulary and say nothing for what the player cannot see", function()
  local e = env(newWorld())
  local words = EventText.effectWords({
    gain = { wood = 2 },
    lose = { water = 1 },
    condition = -10,
    lockTiles = { count = 3, days = 2 },
    damageTiles = { count = 1, setback = 1 },
    damage = { "torn_canvas" },
    note = "ankle_sprain",
    flags = { x = true },
  }, e)
  T.eq(#words, 6)
  T.eq(words[1], "Gain 2 wood")
  T.eq(words[2], "Lose 1 water")
  T.eq(words[3], "Condition -10")
  T.truthy(words[4]:find("3 planted tiles locked for 2 days"))
  T.truthy(words[5]:find("1 planted tile set back"))
  T.truthy(words[6]:find("torn canvas"))
  T.eq(#EventText.effectWords(nil, e), 0)
  T.eq(EventText.costLine({ wood = 2, water = 1 }, e.name), "Costs 1 water, 2 wood")
end)

-- The timer ---------------------------------------------------------------------------------------------------------

T.test("event text: the timer needs both clocks to run out, pauses with the game and waits while away", function()
  T.eq(EventText.remaining(10, 0, HOUR, 1), 10, "the real floor leads when the hours are spent")
  T.eq(EventText.remaining(0, 2, HOUR, 1), 2 * HOUR)
  T.eq(EventText.remaining(0, 2, HOUR, 4), 2 * HOUR / 4, "a faster game runs the hours down sooner")
  T.eq(EventText.remaining(30, 2, HOUR, 8), 30, "but never under the real-seconds floor (8x cannot skip a card unseen)")
  T.eq(EventText.remaining(5, 1, HOUR, 0), nil, "a paused game does not count the hours down")
  T.eq(EventText.remaining(0, 0, HOUR, 0), 0)
  T.eq(EventText.timerLine(34.2, false), "Settles itself in 35 s")
  T.eq(EventText.timerLine(75, false), "Settles itself in 1:15")
  T.eq(EventText.timerLine(nil, false), EventText.paused)
  T.eq(EventText.timerLine(10, true), EventText.waiting, "away: the card says it is waiting")
  T.eq(EventText.fraction(45, 4, 45, 4), 1)
  T.eq(EventText.fraction(0, 0, 45, 4), 0)
  T.eq(EventText.fraction(45, 0, 45, 4), 1, "the bar drains only when both are spent")
end)

T.test("the card's timer follows the engine: time never waits, the window waits while the player is away", function()
  local world = newWorld()
  Events.force(world, "sprained_ankle")
  local before = model(world).timer
  T.eq(before.fraction, 1)
  for _ = 1, 20 do
    Events.advanceReal(world, 1)
  end
  for _ = 1, math.ceil(2 * HOUR / STEP) do
    Events.tick(world, STEP)
  end
  local mid = model(world).timer
  T.truthy(mid.fraction < 1 and mid.fraction > 0, "the bar drains while the player is present")
  Events.setAway(world, true)
  local held = Events.pending(world).realLeft
  for _ = 1, 20 do
    Events.advanceReal(world, 1)
  end
  T.eq(Events.pending(world).realLeft, held, "away: the real clock waits")
  T.eq(model(world, { away = true }).timer.text, EventText.waiting)
  Events.setAway(world, false)
  -- A window run out into ignore: nothing was decided for the player but the free outcome.
  for _ = 1, 3 * math.ceil(tun.events.ignoreMinSeconds) do
    Events.advanceReal(world, 1)
  end
  for _ = 1, math.ceil(tun.events.ignoreHours * HOUR / STEP) + 5 do
    Events.tick(world, STEP)
  end
  T.eq(Events.pending(world), nil, "the card answered itself")
  T.eq(Events.history(world)[1].how, "ignored")
  T.eq(Events.waiting(world), 0)
end)

-- The card ----------------------------------------------------------------------------------------------------------

local function build(world)
  local card = EventCard.new({ tuning = tun })
  local m = model(world)
  local rect = { x = 300, y = 40, w = 300, h = 330 }
  local chosen, ignored = {}, 0
  card:setup(m, rect, function(i)
    chosen[#chosen + 1] = i
  end, function()
    ignored = ignored + 1
  end)
  return card, rect, chosen, function()
    return ignored
  end
end

T.test("event card: every option is a button a finger can hit and a tap answers it", function()
  local world = newWorld()
  Ledger.add(world, "wood", 4)
  Events.force(world, "sprained_ankle")
  local card, rect, chosen, ignored = build(world)
  local touch = tun.input.minTouchTarget
  T.eq(#card.blocks.list, 3, "two options and the ignore outcome")
  for _, b in ipairs(card.blocks.list) do
    T.truthy(b.h >= touch and b.w >= touch)
    T.truthy(b.x >= rect.x and b.x + b.w <= rect.x + rect.w, "inside the card")
  end
  local b1, b2, b3 = card.blocks.list[1], card.blocks.list[2], card.blocks.list[3]
  T.truthy(card:action("select", { x = b1.x + 2, y = b1.y + 2 }))
  T.truthy(card:action("select", { x = b2.x + 2, y = b2.y + 2 }))
  T.truthy(card:action("select", { x = b3.x + 2, y = b3.y + 2 }))
  T.eq(chosen[1], 1)
  T.eq(chosen[2], 2)
  T.eq(ignored(), 1)
  T.falsy(card:action("select", { x = 5, y = 5 }), "the world stays tappable around it")
  T.falsy(card:action("press", { x = 5, y = 5 }))
  T.falsy(card:action("pan", { dx = 3, dy = 3 }))
end)

T.test("event card: an option that cannot be paid does nothing when tapped, and the keyboard skips it", function()
  local world = newWorld()
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Events.force(world, "sprained_ankle")
  local card, _, chosen, ignored = build(world)
  local b1 = card.blocks.list[1]
  T.falsy(b1.enabled)
  card:action("select", { x = b1.x + 2, y = b1.y + 2 })
  T.eq(#chosen, 0, "a disabled option is not pressed")
  T.eq(#card.order, 2, "the keyboard walks the open option and the ignore block")
  card:moveFocus(1)
  T.truthy(card:focused(), "Tab shows the ring")
  T.truthy(card:activate())
  T.eq(chosen[1], 2, "on the free option")
  card:moveFocus(1)
  T.truthy(card:activate())
  T.eq(ignored(), 1, "then the ignore block")
  card:moveFocus(1)
  T.eq(card.focus, 1, "Tab wraps")
  card:action("press", { x = 5, y = 5 })
  T.eq(card:focused(), nil, "a pointer press puts the ring away")
end)

T.test("event card: it fits a phone sheet and a desktop side card, scrolling what does not fit", function()
  local world = newWorld()
  Ledger.add(world, "wood", 4)
  Events.force(world, "sprained_ankle")
  local m = model(world)
  local card = EventCard.new({ tuning = tun })
  local cfg = tun.ui.eventCard
  local touch = tun.input.minTouchTarget
  for _, view in ipairs({ { w = 390, h = 844 }, { w = 844, h = 390 }, { w = 640, h = 360 } }) do
    local bounds = { top = 60, bottom = view.h - 50 }
    local first = Tonight.place(cfg, view, bounds, 0, touch)
    local contentH = card:measure(m, first.rect.w - 2 * cfg.pad) + card:timerHeight() + 4
    local spec = Tonight.place(cfg, view, bounds, contentH, touch)
    local r = spec.rect
    T.truthy(r.x >= 0 and r.x + r.w <= view.w, "inside the view width " .. view.w)
    T.truthy(r.y >= bounds.top and r.y + r.h <= bounds.bottom, "inside the free band at " .. view.w .. "x" .. view.h)
    card:setup(m, r, function() end, function() end)
    T.eq(#card.blocks.list, 3)
    T.truthy(card.list.view.h >= touch * 2, "a window to scroll in")
  end
end)

-- The engine side the card relies on ---------------------------------------------------------------------------------

T.test("events: waiting counts the queue and an answered card leaves it", function()
  local world = newWorld()
  T.eq(Events.waiting(world), 0)
  Events.force(world, "sprained_ankle")
  T.eq(Events.waiting(world), 1)
  T.truthy(Events.ignore(world, "ignored"))
  T.eq(Events.waiting(world), 0)
end)
