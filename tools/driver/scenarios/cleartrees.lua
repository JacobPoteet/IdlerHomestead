-- "Clear trees" in the routine list (D109, #262): the category is listed, starts Off, is switched On with its
-- On/Off button, can take a "Wood below" condition like any other, and then the routine fells a tree by
-- itself (the wood goes to the store). Shots of the panel Off, On with a condition, and after the felling.
local Actors = require("src.sim.systems.actors")
local Ledger = require("src.sim.systems.ledger")
local Tasks = require("src.sim.systems.tasks")

local function trees(world)
  local n = 0
  for _, obj in pairs(world.state.grid.objects) do
    if obj.id == "tree" then
      n = n + 1
    end
  end
  return n
end

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)

  d:pick("Routine list")
  d:frames(3)
  d:shot("panel_off")
  local scene = d:scene()
  local at
  for i, entry in ipairs(world.state.priorities) do
    if entry.category == "trees" then
      at = i
      assert(entry.enabled == false, "Clear trees should start Off")
    end
  end
  assert(at, "Clear trees is not in the routine list")

  -- Switch it on: the On/Off button on its row.
  local row = scene.rows[at]
  assert(row.visible, "the Clear trees row is scrolled out of view")
  local button
  for _, b in ipairs(scene.rowButtons.list) do
    if b.y == row.y and (b.label == "Off" or b.label == "On") then
      button = b
    end
  end
  d:click(button.x + button.w / 2, button.y + button.h / 2)
  assert(world.state.priorities[at].enabled, "the button did not switch it on")

  -- Its scope: only while wood is low (the "If" button, then the kind button).
  local ifButton
  for _, b in ipairs(scene.rowButtons.list) do
    if b.y == row.y and b.label == "If" then
      ifButton = b
    end
  end
  d:click(ifButton.x + ifButton.w / 2, ifButton.y + ifButton.h / 2)
  for _ = 1, 3 do -- Always -> Food below -> Food at least -> Wood below
    d:click(scene.buttons.list[1].x + 5, scene.buttons.list[1].y + 5)
  end
  d:frames(2)
  d:shot("panel_on_wood_below")
  assert(world.state.priorities[at].cond and world.state.priorities[at].cond.kind == "wood_below", "condition not set")
  d:key("escape")

  -- The routine now fells a tree by itself.
  for i, e in ipairs(world.state.priorities) do
    e.enabled = e.category == "trees"
    if i == at then
      e.cond = { kind = "wood_below", value = Ledger.get(world, "wood") + 20 }
    end
  end
  local before, wood = trees(world), Ledger.get(world, "wood")
  d:press("Start routine")
  local job = Tasks.chooseIdleJob(world, Actors.homesteader(world))
  assert(job == nil or job.task == "fell", "unexpected job " .. tostring(job and job.task))
  d:advance(3)
  assert(trees(world) < before, "the routine felled nothing")
  assert(Ledger.get(world, "wood") > wood, "no wood arrived")
  d:shot("felled")
end
