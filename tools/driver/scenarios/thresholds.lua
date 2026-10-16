-- Routine thresholds (GDD D66, #43): the routine panel with per-category conditions, and one
-- condition being edited with the stepper buttons.
local Tasks = require("src.sim.systems.tasks")

--- Press the nth visible "If" button (rows are in priority order; they live in the scene's scrolling
--- `rowButtons`, and rows outside the view have none).
local function pressIf(d, n)
  local scene = d:scene()
  scene.list:reveal((n - 1) * 26, 26) -- the book's page is shorter than the old panel: scroll the row into view
  scene:layout()
  local row = scene.rows[n]
  for _, b in ipairs(scene.rowButtons.list) do
    if b.label == "If" and b.y == row.y then
      d:click(b.x + b.w / 2, b.y + b.h / 2)
      return
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
  d:pick("Routine")
  d:frames(2)
  d:shot("list")

  -- Pick the fish row (last, below the fold: scroll the list by wheel first), choose "Food below",
  -- step it up twice.
  local v = d:scene().list.view
  d:wheel(-6, v.x + v.w / 2, v.y + v.h / 2)
  d:frames(3)
  pressIf(d, #world.state.priorities)
  d:press("Always")
  d:press("+")
  d:press("+")
  d:shot("editing")

  -- A different kind: each press of the kind button cycles to the next one (Food at least, then Wood below).
  d:press("Food below")
  d:press("Food at least")
  d:shot("kind")
end
