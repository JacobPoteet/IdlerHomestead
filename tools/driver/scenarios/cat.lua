-- Mice and the cat (GDD §7.7): a night raid with its toast, then the cat moving in, napping in a
-- sunny spot, and being petted by a tap. The scenario sets the stores and the clock directly (as if
-- days had passed) and forces the raid roll, then lets the sim and input do the rest.
local Cat = require("src.sim.systems.cat")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local view = d.game.app.view
  d:advance(1)

  -- A raid with no cat: the stores shrink and a toast says so.
  Ledger.add(world, "potato", 24)
  world.tuning.cat.mice.chancePerDay = 5 -- certain, whatever the season multiplier
  local t = world.tuning.time -- jump the clock to day 26, early morning
  world.state.calendar.elapsed = (25 + (7 - t.startHour) / 24) * t.dayLength
  world.state.calendar.day = 26
  world.state.finds.rollDay = 26 -- no find offer on the jumped day
  assert(Cat.raid(world) == "raided", "the raid did not happen")
  d:frames(1)
  d:shot("raid_toast")

  -- The cat moves in, and wanders about the homestead.
  Inventory.addEquipment(world, Cat.ITEM)
  d:advance(1)
  assert(Cat.present(world), "the cat never arrived")
  local x, y = world.state.cat.x, world.state.cat.y
  local cx, cy = scene.camera:tileToWorld(math.floor(x + 0.5), math.floor(y + 0.5))
  cx, cy = cx + scene.camera.tileSize / 2, cy + scene.camera.tileSize / 2
  scene.camera:centerOn(cx, cy, view)
  d:frames(2)
  d:shot("arrived")

  -- Let it settle into a nap in the sun.
  local hours = 0
  while world.state.cat.mode ~= "nap" and hours < 12 do
    d:advance(0.25)
    hours = hours + 0.25
  end
  local nx, ny = world.state.cat.x, world.state.cat.y
  cx, cy = scene.camera:tileToWorld(math.floor(nx + 0.5), math.floor(ny + 0.5))
  cx, cy = cx + scene.camera.tileSize / 2, cy + scene.camera.tileSize / 2
  scene.camera:centerOn(cx, cy, view)
  scene.toast = nil
  d:frames(2)
  d:shot("napping")

  -- Tap the cat to pet it.
  d:clickTile(math.floor(nx + 0.5), math.floor(ny + 0.5))
  d:frames(2)
  assert(world.state.cat.pets == 1, "the tap did not pet the cat")
  d:shot("petted")
end
