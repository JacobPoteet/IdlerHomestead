-- The event card (D172, #348): the card where the player answers a misfortune event. An affordable choice (a tap on an
-- option pays its cost and applies its effect), an option the player cannot pay (disabled, with the reason; the free
-- option and the ignore outcome stay open; Tab and Enter), an event ignored (the timer runs out into the free outcome,
-- waits behind a panel and while the player is away), and the one-card-at-a-time notice queue (Tonight first, the event
-- waits behind it with a stamp). The event is offered through the Events debug path (the dusk draw cannot be waited
-- for); the card, the taps and the keys are the real ones. Desktop, phone and landscape.
local Events = require("src.sim.systems.events")
local Ledger = require("src.sim.systems.ledger")
local Status = require("src.sim.systems.status")

local function quiet(d)
  local scene = d:scene()
  scene.toast, scene.toastQueue = nil, {}
end

--- The card's block with this label (an option, or the ignore block), or nil.
local function block(scene, prefix)
  for _, b in ipairs(scene.eventCard.blocks.list) do
    if b.label:sub(1, #prefix) == prefix then
      return b
    end
  end
  return nil
end

local function tap(d, b)
  d:click(b.x + b.w / 2, b.y + b.h / 2)
  d:frames(3)
end

local function setWood(world, n)
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  if n > 0 then
    Ledger.add(world, "wood", n)
  end
end

local function clearAnkles(world)
  for _, id in ipairs({ "ankle_1", "ankle_2", "ankle_3", "limp" }) do
    Status.clear(world, id)
  end
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local view = scene.app.view
  local touch = world.tuning.input.minTouchTarget
  d:frames(30)
  quiet(d)

  -- 1. An affordable choice: the card names both options, what each costs and does, how safe it is, the ignore outcome
  -- and a timer; a tap on Splint it pays two wood and applies Hobbling.
  setWood(world, 6)
  assert(Events.force(world, "sprained_ankle"))
  d:frames(10)
  quiet(d)
  assert(scene.noticeOwner == "event" and scene:eventShown(), "the event card is up")
  local r = scene.eventRect
  assert(r.x >= 0 and r.x + r.w <= view.w and r.y >= 0 and r.y + r.h <= view.h, "inside the view")
  local splint, power, wait = block(scene, "Splint"), block(scene, "Power"), block(scene, "If you do nothing")
  assert(splint and power and wait, "two options and the ignore outcome are all there")
  for _, b in ipairs({ splint, power, wait }) do
    assert(b.h >= touch and b.w >= touch, "touch-sized: " .. b.label)
    assert(b.x >= r.x and b.x + b.w <= r.x + r.w, "inside the card: " .. b.label)
  end
  assert(splint.enabled and power.enabled and wait.enabled, "all three can be chosen")
  d:shot("card_affordable")
  local before = Events.pending(world).realLeft
  d:frames(40)
  assert(Events.pending(world).realLeft < before, "the ignore window runs down while the card is up")
  tap(d, splint)
  assert(Events.waiting(world) == 0, "the card is answered")
  assert(Ledger.get(world, "wood") == 4, "Splint it cost two wood")
  assert(Status.active(world)[1].id == "ankle_1", "and Hobbling is on")
  assert(not scene:eventShown(), "the card is put away")
  d:frames(10)
  d:shot("splint_done")
  quiet(d)
  clearAnkles(world)

  -- 2. An option the player cannot pay: disabled with the reason, a tap does nothing; the free option and the ignore
  -- outcome stay open. Tab then Enter on the keyboard.
  setWood(world, 0)
  assert(Events.force(world, "sprained_ankle"))
  d:frames(10)
  quiet(d)
  splint, power = block(scene, "Splint"), block(scene, "Power")
  assert(not splint.enabled and power.enabled, "no wood: the splint is off, the free option is on")
  assert(scene.eventCard.model.options[1].reason:find("Needs wood"), "and the card says why")
  d:shot("card_unaffordable")
  tap(d, splint)
  assert(Events.waiting(world) == 1, "a tap on a disabled option answers nothing")
  d:key("tab")
  assert(scene.eventCard:focused() == power, "Tab rings the first open option, not the disabled one")
  d:shot("card_keyboard")
  d:key("return")
  d:frames(3)
  assert(Events.waiting(world) == 0, "Enter answers it")
  assert(Status.active(world)[1].id == "ankle_2", "Power through: Strained ankle")
  d:frames(10)
  quiet(d)
  clearAnkles(world)

  -- 3. An ignored event: a panel in front (Progress, P) stops the window and hides the card; closing it brings the card
  -- back; then the window runs out into the free outcome and nothing else happens to the player.
  setWood(world, 6)
  assert(Events.force(world, "sprained_ankle"))
  d:frames(10)
  quiet(d)
  d:key("p")
  assert(d:scene().name == "progress", "the Progress panel is up")
  local held = Events.pending(world).realLeft
  d:frames(60)
  assert(Events.pending(world).realLeft == held, "behind a panel the ignore window waits")
  assert(not scene:eventShown(), "and the card does not stack with it")
  d:key("p")
  d:frames(10)
  assert(scene:eventShown(), "closing the panel brings the card back")
  d:setSpeed(4)
  d:frames(120, 0.1)
  local timer = scene.eventCard.model.timer
  assert(timer.fraction < 1, "the bar drains")
  d:shot("card_running_out")
  for _ = 1, 40 do
    if Events.waiting(world) == 0 then
      break
    end
    d:frames(10, 0.1) -- the real-seconds floor (45 s) must pass as well as the game hours
  end
  assert(Events.waiting(world) == 0, "the window ran out")
  local last = Events.history(world)
  assert(last[#last].how == "ignored" and last[#last].reason == "expired", "into the ignore outcome")
  assert(Ledger.get(world, "wood") == 6, "free: no wood spent")
  assert(Status.active(world)[1].id == "limp", "Limping, which never gets worse")
  d:setSpeed(1)
  d:frames(10)
  d:shot("ignored_done")
  quiet(d)
  clearAnkles(world)

  -- 4. One card at a time: Tonight is open (T), so the event waits behind it with a stamp and its window waits; closing
  -- Tonight brings the event card up.
  if not scene.tonight.open then -- (the evening may have opened it by itself)
    d:key("t")
  end
  d:frames(5)
  assert(scene.tonight.open, "T opens the Tonight card")
  assert(
    scene:tonightShown(),
    "the Tonight card is up: " .. tostring(scene.noticeOwner) .. tostring(scene.card) .. tostring(scene.lens:active())
  )
  assert(Events.force(world, "sprained_ankle"))
  d:frames(10)
  quiet(d)
  assert(scene.noticeOwner == "tonight" and not scene:eventShown(), "Tonight is first in the rank: the event waits")
  assert(d:hudButton("event"), "a stamp says an event is waiting")
  held = Events.pending(world).realLeft
  d:frames(60)
  assert(Events.pending(world).realLeft == held, "and its window waits")
  d:shot("waits_behind_tonight")
  d:press("Close")
  d:frames(10)
  assert(scene:eventShown() and not scene:tonightShown(), "closing Tonight gives the screen to the event")
  assert(not d:hudButton("event"), "the stamp is gone")
  d:shot("event_after_tonight")
  tap(d, block(scene, "If you do nothing"))
  assert(Events.waiting(world) == 0, "a tap on the ignore outcome takes it now")
  assert(Status.active(world)[1].id == "limp")
  d:frames(10)
  quiet(d)
end
