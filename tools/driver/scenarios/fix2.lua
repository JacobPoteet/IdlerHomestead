-- Small-fix bundle two (D94): the Plan latch (a double tap keeps Plan on, shown with a second ring and a
-- "kept on" caption) and the Routine list on the shared scroll kit, shrunk to a short window so it scrolls:
-- Page Down, End, Home and a flick that coasts. Taps, keys and drags are the real ones.
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
  dismissFinds(d)
  local winW, winH = love.graphics.getDimensions()

  -- Plan: one tap is on, a second quick tap latches it.
  d:pick("Plan field")
  d:pick("Plan field")
  assert(d:scene().planLatch, "the second quick tap should latch Plan")
  d:shot("plan-latched")
  d:pick("Plan field")
  assert(d:scene().mode == "act" and not d:scene().planLatch, "a tap while latched turns Plan off")

  -- Routine list in a short window: it scrolls.
  d:resize(winW, 230)
  d:pick("Routine")
  d:frames(3)
  local routine = d:scene()
  assert(routine.list.overflow, "the routine list should scroll in a short window")
  d:shot("routine-top")
  d:key("pagedown")
  assert(routine.list.offset > 0, "Page Down scrolls")
  d:shot("routine-pagedown")
  d:key("end")
  d:shot("routine-end")
  d:key("home")
  assert(routine.list.offset == 0, "Home goes back to the top")
  local v = routine.list.view
  d:drag(v.x + 40, v.y + v.h - 10, v.x + 40, v.y + 10, 4)
  d:frames(30)
  assert(routine.list.offset > 0, "a flick moves the list")
  d:shot("routine-flicked")
  d:resize(winW, winH)
end
