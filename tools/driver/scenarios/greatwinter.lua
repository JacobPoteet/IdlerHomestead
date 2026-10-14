-- The Great Winter and the Established card (D117, #277): the autumn of the Great Winter year with its
-- full, named forecast and warning toast, the winter itself, and the one-time card on the first thaw.
-- The clock is set through the sim (a scenario cannot wait for three years); the screens are real.
local Established = require("src.sim.systems.established")

--- Put the clock at `hour` on the day before `day`, so the next frames roll over into `day` and announce it.
local function approach(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 2 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day - 1
end

--- A random find can pop up after a long jump of the clock: take it so the homestead is on top again.
local function dismissFinds(d)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1]
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
  local time = world.tuning.time
  local DPS = time.daysPerSeason
  local DPY = DPS * #time.seasons
  local GREAT = world.tuning.progress.greatWinterYear
  world.state.ledger.amounts.wood = 60
  world.state.ledger.amounts.canned_food = 20

  -- 1. The first day of autumn in the Great Winter's year: everything is announced at once.
  approach(world, (GREAT - 1) * DPY + 2 * DPS + 1, 23.9)
  d:frames(240)
  dismissFinds(d)
  assert(d:scene().name == "homestead", "the homestead is on top")
  local f = require("src.sim.systems.weather").forecast(world)
  assert(f.great and f.severity and f.snapStart and f.snapDays, "the full forecast is known on day one of autumn")
  d:tryPress("Got it") -- the morning report
  scene.toast, scene.toastQueue = nil, {}
  d:frames(5)
  d:shot("autumn_forecast")

  -- 2. The winter itself: the pill reads "This winter: the Great Winter ...".
  approach(world, (GREAT - 1) * DPY + 3 * DPS + 2, 10)
  d:frames(240)
  dismissFinds(d)
  d:tryPress("Got it")
  scene.toast, scene.toastQueue = nil, {}
  d:frames(5)
  d:shot("winter")

  -- 3. The first thaw: the card. Surviving marks the slot, and the card waits for the homestead to be on top.
  assert(Established.mark(world.meta) == nil, "not yet")
  approach(world, GREAT * DPY + 1, 23.9)
  d:frames(240)
  dismissFinds(d)
  assert(Established.mark(world.meta) and Established.mark(world.meta).year == GREAT, "the slot is marked")
  assert(d:scene().name == "notice", "the Established card is up, not: " .. tostring(d:scene().name))
  d:shot("established_card")
  d:press(world.tuning.ui.greatWinter.cardOk)
  d:frames(10)
  assert(d:scene().name == "homestead", "play continues")
  assert(not Established.cardDue(world.meta), "the card is shown once")
  d:shot("after_card")
end
