-- The tool wheel (D138, #294): the tool badge opens it sticky, hovering the Hoe shows its ring, a
-- seed packet from the ring, Q at the middle of the view, keys 1-6, a held wheel aimed at a wedge and at
-- the Hoe's ring, and the Hammer with an empty crate.
local function centre(r)
  return r.x + r.w / 2, r.y + r.h / 2
end

-- A point `dist` UI pixels from the wheel's centre at `angle` degrees (0 = right, 90 = down).
local function toward(w, angle, dist)
  local a = math.rad(angle)
  return w.cx + math.cos(a) * dist, w.cy + math.sin(a) * dist
end

local function angleOf(scene, id)
  for _, wedge in ipairs(scene.app.ctx.tuning.ui.wheel.wedges) do
    if wedge.id == id then
      return wedge.angle
    end
  end
  error("no wedge " .. id)
end

return function(d)
  d:newGame()
  d:frames(10)
  local scene = d:scene()
  d:shot("start")

  -- The tool badge opens a sticky wheel with the tool in hand lit.
  d:pressHud("tools")
  assert(scene.wheel and not scene.wheel.held, "the tool badge opens a sticky wheel")
  d:shot("badge_open")

  -- Hovering the Hoe shows its ring (a first tap does on touch); a packet from the ring puts that seed in hand.
  local hx, hy = centre(scene.wheelLayout.wedges.hoe)
  local s = scene.app.view.scale
  d.game.input:mousemoved(hx * s, hy * s, 0, 0, false)
  d:frames(2)
  assert(scene.wheel and scene.wheel.highlight == "hoe", "hovering the Hoe shows its ring")
  d:shot("hoe_ring")
  d:click(centre(scene.wheelLayout.ring[1]))
  assert(not scene.wheel and scene.seed, "a ring packet puts a seed in hand")
  d:shot("seed_in_hand")

  -- Q opens the wheel at the middle of the view; Q again closes it.
  d:key("q")
  assert(scene.wheel, "Q opens the wheel")
  d:shot("key_q")
  d:key("q")
  assert(not scene.wheel, "Q closes the wheel")

  -- Keys 1-6 equip directly.
  d:key("3")
  assert(scene:currentTool() == "pail", "3 takes the Pail")
  d:shot("key_pail")
  d:key("4")
  assert(scene:currentTool() == "axe", "4 takes the Axe")
  d:shot("key_axe")
  d:key("1")
  assert(scene:currentTool() == "hand", "1 takes the Hand")

  -- A held wheel (right press or long-press) aimed at the Rod, then let go.
  local vw, vh = scene.app.view.w, scene.app.view.h
  scene:openWheel(vw / 2, vh / 2, true)
  scene.wheel.at = scene.wheel.at - 1 -- past showDelay: scripted frames carry no wall-clock time
  local sizes = require("src.ui.tool_wheel").sizes(scene.app.ctx.tuning.ui.wheel, scene.app.view)
  scene:aimWheel(toward(scene.wheel, angleOf(scene, "rod"), sizes.radius))
  d:frames(2)
  d:shot("held_aim_rod")
  scene:releaseWheel()
  d:frames(2)
  assert(scene:currentTool() == "rod", "letting go on the Rod takes it")
  d:shot("held_rod_taken")

  -- Held again, past the Hoe into its ring.
  scene:openWheel(vw / 2, vh / 2, true)
  scene.wheel.at = scene.wheel.at - 1
  scene:aimWheel(toward(scene.wheel, angleOf(scene, "hoe"), sizes.radius))
  scene:aimWheel(toward(scene.wheel, angleOf(scene, "hoe"), sizes.ring))
  d:frames(2)
  d:shot("held_hoe_ring")
  -- Back to the middle cancels.
  scene:aimWheel(scene.wheel.cx, scene.wheel.cy)
  scene:releaseWheel()
  d:frames(2)
  assert(scene:currentTool() == "rod", "letting go in the middle keeps the tool in hand")

  -- The Hammer with nothing in the crate says where buildings come from.
  d:key("6")
  d:frames(2)
  d:shot("hammer_empty")
end
