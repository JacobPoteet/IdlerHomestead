-- The small-fix UX bundle (D93): Pantry rows with no overlapping buttons (#174), a station's waiting
-- output with its Discard action and a "Full" pill that lists only blocking stores (#135), and the idle
-- nudge that survives a panel and the pulsing Routine button (#119, #120).
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)

  -- 1. Pantry: plain rows (wood, scrap, smoked fish, canned food) sit a touch target apart.
  for id, n in pairs({ wood = 12, scrap = 5, smoked_fish = 4, canned_food = 3 }) do
    Ledger.add(world, id, n)
  end
  d:pick("Pantry")
  d:frames(3)
  d:shot("pantry_top")
  d:wheel(-10, d:scene().box.x + 100, d:scene().box.y + 150)
  d:frames(3)
  d:shot("pantry_bottom")
  d:key("escape")
  d:frames(2)

  -- 2. A smoker holding finished fish for room: the card offers Discard, only that store is "Full".
  Ledger.add(world, "firewood", Ledger.capacity(world, "firewood")) -- full, but nothing waits on it
  Inventory.addObject(world, "smoker")
  local tx, ty = d:freeTileNear(2, 2)
  local i = Grid.index(world.state.grid, tx, ty)
  assert(Inventory.place(world, "smoker", i), "could not place the smoker")
  local _, anchor = Grid.object(world, i)
  Ledger.setCapacity(world, "smoked_fish", Ledger.get(world, "smoked_fish"))
  world.state.processing[anchor] = { recipe = "smoke_fish", count = 4, remaining = 0, blocked = true }
  d:frames(40)
  d:clickTile(tx, ty)
  d:frames(5)
  d:shot("station_card")
  d:press("Discard waiting output")
  d:frames(3)
  d:shot("discard_confirm")
  d:press("Discard")
  d:frames(3)
  assert(world.state.processing[anchor] == nil, "the batch was not discarded")
  d:shot("discarded")

  -- 3. The idle nudge: held while a panel is open, shown when the world returns, button pulsing.
  local routine = world.state.routine
  d:scene().toast, d:scene().toastQueue = nil, {}
  d:pick("Catalog")
  d:frames(2)
  routine.idleFor, routine.cooldown = world.tuning.idle.hintAfter - 0.2, 0
  d:frames(120) -- a couple of game seconds pass behind the panel
  assert(d:scene().name == "catalog", "the panel should still be up")
  d:shot("hint_behind_panel")
  d:key("escape")
  d:frames(4)
  d:shot("hint_after_panel")
end
