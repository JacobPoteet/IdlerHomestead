-- The roadside stand (GDD §6.4): placed beside the road, a day of sales with the toast, and the
-- object card. The scenario sets the homestead up directly (as if bought and placed), stocks the
-- spare goods (keep 0), then lets the sim run past the stand's opening hour.
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(1)

  -- The free spot beside the road nearest the dead truck.
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, "roadside_stand", i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot beside the road")
  local scene = d:scene()
  local view = d.game.app.view
  local bx, by = Grid.coords(grid, best)
  local cx, cy = scene.camera:tileToWorld(bx + 1, by + 0.5)
  scene.camera:centerOn(cx, cy, view)

  Inventory.addObject(world, "roadside_stand")
  assert(Inventory.place(world, "roadside_stand", best))
  Ledger.add(world, "sunfish", 10)
  Ledger.add(world, "radish", 8)
  Food.setKeep(world, "sunfish", 0)
  Food.setKeep(world, "radish", 0)
  scene.selected = best
  d:frames(2)
  d:shot("placed_card_before")

  -- Let the day run to the opening hour; the stand sells and a toast announces it.
  local hours = 0
  while world.state.stand.last == nil and hours < 14 do
    d:advance(1)
    hours = hours + 1
  end
  assert(world.state.stand.last, "the stand never sold")
  d:frames(2)
  d:shot("sold_toast")
  scene.toast = nil
  d:frames(2)
  d:shot("card_after_sale")
end
