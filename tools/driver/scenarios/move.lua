-- Picking up and moving placed objects (D98, #15): the object card with Pick up / Move, the move preview over a
-- tree (the object stays put until the way is clear), the finished move, a refusal (a coop with hens), and the
-- confirmation for a battery that holds charge.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Placement = require("src.sim.systems.placement")
local Power = require("src.sim.systems.power")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local bx, by = math.min(grid.w - 9, sx + 5), math.min(grid.h - 7, sy + 2)
  d:advance(4)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - bx) <= 8 and math.abs(y - by) <= 7 then
      Grid.removeObject(world, anchor)
    end
  end
  local function at(dx, dy)
    return Grid.index(grid, bx + dx, by + dy)
  end
  local function build(id, dx, dy)
    Inventory.addObject(world, id)
    assert(Inventory.place(world, id, at(dx, dy)), "place " .. id)
  end
  build("smoker", 0, 0)
  build("battery_bank", 3, 0)
  build("chicken_coop", 0, 3)
  Power.add(world, at(3, 0), 6)
  Ledger.add(world, "hen", 3)
  Grid.placeObject(world, "tree", bx + 4, by + 3)
  Grid.placeObject(world, "rock", bx + 6, by + 1)

  local scene = d:scene()
  local view = d.game.app.view
  local cx, cy = scene.camera:tileToWorld(bx + 3, by + 2)
  scene.camera:centerOn(cx, cy, view)
  d:frames(3)

  -- The object card of a smoker: Pick up and Move.
  scene.selected = at(0, 0)
  d:frames(2)
  d:shot("card")

  -- Move: the ghost over the tree is amber, the smoker stays where it is.
  d:press("Move")
  d:frames(2)
  scene.hover = at(4, 3)
  d:frames(2)
  d:shot("move_preview")
  d:clickTile(bx + 4, by + 3)
  d:frames(2)
  d:shot("move_confirm")
  d:press("Go ahead")
  d:frames(3)
  assert(world.state.grid.objects[at(0, 0)], "the smoker stays until the tree is gone")
  for _ = 1, 80 do
    d:frames(10)
    if #Placement.orders(world) == 0 then
      break
    end
  end
  assert(world.state.grid.objects[at(4, 3)] and world.state.grid.objects[at(4, 3)].id == "smoker", "the smoker moved")
  scene.selected = at(4, 3)
  d:frames(2)
  d:shot("moved")

  -- A coop with hens cannot be picked up.
  scene.selected = at(0, 3)
  d.game:draw() -- the card buttons are laid out while drawing
  d:frames(2)
  d:press("Pick up")
  d:frames(2)
  d:shot("refused")
  assert(world.state.grid.objects[at(0, 3)], "the coop stays")

  -- A battery holding charge asks first.
  scene.toast = nil
  scene.selected = at(3, 0)
  d.game:draw()
  d:frames(2)
  d:press("Pick up")
  d:frames(2)
  d:shot("battery_confirm")
  d:press("Pick up")
  d:frames(3)
  assert(not world.state.grid.objects[at(3, 0)], "the battery was picked up")
  assert(Inventory.objectCount(world, "battery_bank") == 1, "and is in the inventory")
  d:shot("picked_up")
end
