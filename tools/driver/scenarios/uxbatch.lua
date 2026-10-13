-- The beginner-UX batch (D70): a scrolling Pantry (#170), low-stock warnings on the chips and as
-- toasts (#157), the bedtime notice and morning report card (#159), the won't-ripen warning on a plan
-- (#165) and the winter-readiness pill and card (#166). Stock and the clock are set through the sim
-- (a scenario cannot wait for a season); the screens, taps and drags are the real ones.
local Actors = require("src.sim.systems.actors")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")

--- Jump the sim clock to a day and hour (the calendar's day marker with it, so no day is announced).
local function jumpTo(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- Keep only the toasts (showing and waiting) that contain one of the plain patterns, restarting the
--- one on screen so a screenshot catches it. Staging for a screenshot, not game behaviour.
local function keepOnly(scene, patterns)
  local function wanted(text)
    for _, p in ipairs(patterns) do
      if text:find(p, 1, true) then
        return true
      end
    end
    return false
  end
  local list = {}
  if scene.toast then
    list[#list + 1] = scene.toast.text
  end
  for _, text in ipairs(scene.toastQueue) do
    list[#list + 1] = text
  end
  scene.toast, scene.toastQueue = nil, {}
  for _, text in ipairs(list) do
    if wanted(text) then
      scene:queueToast(text)
    end
  end
end

--- A random find can pop up after a long jump of the clock: take it so the homestead is on top again.
local function dismissFinds(d)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1] -- pick the first offer, then take it
      d:click(first.x + first.w / 2, first.y + first.h / 2)
      d:press("Take it")
      d:frames(3)
    end
  end
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local DPS = world.tuning.time.daysPerSeason

  -- Pantry (#170): more goods than fit; drag, wheel, and a rule button still works scrolled.
  for _, id in ipairs({ "creek_chub", "sunfish", "brook_trout", "smallmouth_bass", "channel_catfish", "rainbow_trout", "golden_trout" }) do
    Ledger.add(world, id, 2)
  end
  Ledger.add(world, "radish", 6)
  Ledger.add(world, "potato", 5)
  Ledger.add(world, "egg", 8)
  Ledger.add(world, "smoked_fish", 3)
  Ledger.add(world, "wood", 12)
  Ledger.add(world, "scrap", 4)
  d:frames(5)
  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_top")
  local pantry = d:scene()
  local v = pantry.view
  -- (A tall phone window holds every row; the short ones overflow and scroll.)
  if pantry.overflow then
    d:drag(v.x + 80, v.y + v.h - 20, v.x + 80, v.y + 10) -- finger drags up: later rows
    assert(pantry.scroll > 0, "dragging scrolls")
    d:shot("pantry_dragged")
    d:wheel(-30, v.x + 80, v.y + 40) -- wheel down to the end
    assert(pantry.scroll == pantry.contentH - v.h, "the wheel reaches the end of the list")
    d:shot("pantry_bottom")
    local before = pantry.scroll
    d:press("Auto") -- fixed controls still answer while the list is scrolled
    assert(pantry.scroll <= before and pantry.scroll > 0, "pressing a button keeps the list scrolled (re-clamped if the footer grew or shrank)")
  end
  d:key("escape")
  d:frames(3)

  -- Warnings (#157): food, fuel and health run low.
  scene = d:scene()
  world.state.ledger.amounts.canned_food = 2
  world.state.ledger.amounts.radish, world.state.ledger.amounts.potato = nil, nil
  for _, id in ipairs({ "creek_chub", "sunfish", "brook_trout", "smallmouth_bass", "channel_catfish", "rainbow_trout", "golden_trout", "egg", "smoked_fish" }) do
    world.state.ledger.amounts[id] = nil
  end
  jumpTo(world, 2 * DPS + 3, 10) -- a cold autumn day
  world.state.ledger.amounts.wood = 4
  world.state.needs.condition = 35
  d:frames(30) -- the first look (once a second) raises the warnings
  dismissFinds(d)
  keepOnly(scene, { "low", "Not enough", "Out of" }) -- the time jump also caused other news; this shot is about the warnings
  d:frames(2)
  d:shot("warning_chips_toast")
  d:frames(60)
  d:shot("warning_next_toast")

  -- Winter readiness (#166): the pill, and the card behind it.
  jumpTo(world, 2 * DPS + 1, 10)
  world.state.ledger.amounts.canned_food = 6
  world.state.ledger.amounts.wood = 16
  world.state.needs.condition = 90
  d:frames(60)
  dismissFinds(d)
  scene.toast, scene.toastQueue = nil, {} -- (news the time jump caused)
  local hit = scene.readinessHit
  assert(hit, "the readiness pill is up in autumn")
  d:shot("readiness_pill")
  d:click(hit.x + 20, hit.y + hit.h / 2)
  d:frames(3)
  d:shot("readiness_card")
  d:press("Got it")
  d:frames(3)
  -- Stocked up: the pill says ready.
  Ledger.setCapacity(world, "wood", 999) -- (what a woodshed does)
  world.state.ledger.amounts.wood = 999
  world.state.ledger.amounts.smoked_fish = 40
  d:frames(3)
  d:shot("readiness_ready")
  world.state.ledger.amounts.smoked_fish = nil

  -- Won't ripen (#165): two days before the freeze, plan potatoes.
  jumpTo(world, 3 * DPS - 2, 10)
  world.state.ledger.amounts.seed_potato = 6
  d:frames(10)
  dismissFinds(d)
  scene.seedButtons.potato.onPress()
  d:frames(3)
  d:shot("seed_warning")
  dismissFinds(d)
  d:pick("Plan field")
  local x1, y1 = d:freeTileNear(2, 2)
  d:clickTile(x1, y1)
  d:clickTile(d:freeTileNear(5, 3))
  d:frames(5)
  d:shot("plan_tinted")
  d:frames(62) -- the "Planned" toast runs out and the warning behind it shows
  dismissFinds(d)
  d:shot("plan_warning_toast")
  d:pick("Plan field")
  d:press("Hand")
  d:clickTile(x1, y1) -- a planned corner
  d:frames(3)
  d:shot("planned_tile_card")

  -- Bedtime and the morning (#159): real sleep, a study queued, fish that will spoil.
  jumpTo(world, 3 * DPS - 2, 12)
  for _, def in ipairs(world.registry:all("catalog")) do
    if def.studyNights and not def.starter then
      world.meta.journal.queue = { def.id }
      break
    end
  end
  Ledger.add(world, "creek_chub", 8)
  d:setSpeed(4)
  local guard = 0
  while not Actors.homesteader(world).asleep do
    d:advance(0.25)
    guard = guard + 1
    assert(guard < 200, "the homesteader never went to bed")
  end
  d:shot("bedtime_toast")
  dismissFinds(d)
  d:press("Skip night")
  guard = 0
  while Actors.homesteader(world).asleep do
    d:frames(10)
    guard = guard + 1
    assert(guard < 3000, "the skip never reached morning")
  end
  d:frames(5)
  d:shot("morning_report")
  assert(scene.cardKind == "report", "the morning report card is up")
  d:press("Got it")
  d:frames(5)
  d:shot("morning_after")
end
