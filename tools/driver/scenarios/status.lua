-- Status chips and their detail card (D167, #346): a chip per active status under the Condition meter (an icon, the main
-- effect and the days left), a tap or the H key opening its card, the card closing with Close, Esc or H and by itself when
-- the status ends, and the recovery scene naming what hurt the run. Nothing applies a status in play yet (B3 on), so the
-- scenario applies them through the Status API; the chips, taps and keys are the real ones. Desktop, phone and landscape.
local Status = require("src.sim.systems.status")

local function quiet(d)
  local scene = d:scene()
  scene.toast, scene.toastQueue = nil, {}
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local minTouch = world.tuning.input.minTouchTarget

  -- 1. Nothing wrong: no chips, and H says so.
  d:frames(30)
  quiet(d)
  assert(not d:hudButton("status:ankle_1"), "no chip while nothing is wrong")
  d:shot("none")
  d:key("h")
  d:frames(3)
  assert(d:scene().name == "homestead", "H with nothing active opens no card")
  assert(scene.toast, "it says nothing is wrong")
  quiet(d)

  -- 2. Two statuses: a chip each, icon and words, under the Condition meter, touch-sized and inside the view.
  Status.apply(world, "ankle_1")
  Status.apply(world, "fever")
  d:frames(10)
  quiet(d)
  local ankle, fever = d:hudButton("status:ankle_1"), d:hudButton("status:fever")
  assert(ankle and fever, "a chip for each status")
  for _, b in ipairs({ ankle, fever }) do
    assert(b.y >= scene.hud.topH, "under the top plates")
    assert(b.h >= minTouch, "a touch-sized chip")
    assert(b.x >= 0 and b.x + b.w <= scene.app.view.w, "inside the view")
  end
  assert(ankle.label:find("1d"), "the days left are on the chip: " .. ankle.label)
  assert(fever.label:find("3d"), "the days left are on the chip: " .. fever.label)
  d:shot("chips")

  -- 3. A tap on a chip opens its card; Close puts it away.
  d:pressHud("status:ankle_1")
  d:frames(4)
  assert(d:scene().name == "status", "a chip opens the card")
  d:shot("card_ankle")
  d:press("Close")
  d:frames(3)
  assert(d:scene().name == "homestead", "Close returns to the homestead")

  -- 4. The keyboard: H opens the first status's card, H or Esc closes it; Tab-free, nothing is hover-only.
  d:key("h")
  d:frames(3)
  assert(d:scene().name == "status", "H opens the card")
  d:key("h")
  d:frames(3)
  assert(d:scene().name == "homestead", "H closes it again")
  d:pressHud("status:fever")
  d:frames(4)
  d:shot("card_fever")
  d:key("escape")
  d:frames(3)
  assert(d:scene().name == "homestead", "Esc closes it")

  -- 5. Hurt again: the ankle rises a step (one chip, not two), and a third family fills the row of three.
  Status.apply(world, "ankle_1")
  Status.apply(world, "burn")
  d:frames(10)
  quiet(d)
  assert(not d:hudButton("status:ankle_1") and d:hudButton("status:ankle_2"), "the ankle escalated in place")
  assert(d:hudButton("status:burn"), "a third chip")
  d:shot("three_chips")
  d:pressHud("status:burn")
  d:frames(4)
  d:shot("card_burn")

  -- 6. The card closes by itself when its status ends.
  Status.clear(world, "burn")
  d:frames(60, 1 / 30)
  assert(d:scene().name == "homestead", "the card closes when the status is gone")
  assert(not d:hudButton("status:burn"), "and so does the chip")

  -- 7. The run fails: the recovery scene names what hurt it.
  world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
  d:frames(4)
  d:frames(150, 1 / 30)
  d:click(40, 40)
  d:frames(6)
  local recovery = d:scene()
  assert(recovery.name == "recovery", "on to the recovery scene, not " .. tostring(recovery.name))
  assert(
    recovery.hurt and recovery.hurt:find("Hobbling") and recovery.hurt:find("Burn"),
    "the scene lists what hurt the run"
  )
  d:shot("recovery_hurt")
end
