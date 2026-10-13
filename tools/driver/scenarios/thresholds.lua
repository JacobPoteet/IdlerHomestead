-- Routine thresholds (GDD D66, #43): the routine panel with per-category conditions, and one
-- condition being edited with the stepper buttons.
local Tasks = require("src.sim.systems.tasks")

--- Press the nth "If" button (rows are in priority order).
local function pressIf(d, n)
  local seen = 0
  for _, b in ipairs(d:scene().buttons.list) do
    if b.label == "If" then
      seen = seen + 1
      if seen == n then
        d:click(b.x + b.w / 2, b.y + b.h / 2)
        return
      end
    end
  end
  error("no If button #" .. n)
end

return function(d)
  d:newGame()
  local world = d:world()
  Tasks.setCondition(world, "harvest", "hour_after")
  Tasks.setCondition(world, "clear", "wood_below")
  d:advance(0.5)
  d:pick("Routine list")
  d:frames(2)
  d:shot("list")

  -- Pick the fish row (last), choose "Food below", step it up twice.
  pressIf(d, #world.state.priorities)
  d:press("Always")
  d:press("+")
  d:press("+")
  d:shot("editing")

  -- A different kind: cycle on to the season rule.
  d:press("Food below")
  d:press("Food at least")
  d:shot("kind")
end
