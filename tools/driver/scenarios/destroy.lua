-- Destroy (D110, #255) through the Hammer's Demolish mode (D139) and planning over growing crops (D110, #257): a
-- crop demolished and its confirmation, a full woodshed and the confirmation that names lost stock, and the plan
-- preview marking the tiles whose crop will be replaced, then the replace confirmation.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local scene = d:scene()
  d:advance(0.1)
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local bx, by = math.min(grid.w - 12, sx + 5), math.min(grid.h - 8, sy + 2)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - bx) <= 9 and math.abs(y - by) <= 8 then
      Grid.removeObject(world, anchor)
    end
  end
  local function at(dx, dy)
    return Grid.index(grid, bx + dx, by + dy)
  end
  -- A small potato field, partly ripe, and a woodshed full of wood.
  for dx = 0, 3 do
    for dy = 0, 1 do
      world.state.fields.tilled[at(dx, dy)] = true
      world.state.fields.plan[at(dx, dy)] = "potato"
      world.state.crops[at(dx, dy)] = { id = "potato", growth = dx == 0 and 1 or 0.4, moisture = 0.5 }
    end
  end
  Inventory.addObject(world, "woodshed")
  assert(Inventory.place(world, "woodshed", at(5, 4)), "place woodshed")
  Ledger.add(world, "wood", Ledger.capacity(world, "wood"))
  local view = d.game.app.view
  local cx, cy = scene.camera:tileToWorld(bx + 3, by + 2)
  scene.camera:centerOn(cx, cy, view)
  d:frames(3)

  -- Demolish a crop.
  d:pick("Demolish")
  d:frames(2)
  d:shot("demolish_mode")
  d:clickTile(bx + 1, by)
  d:frames(2)
  d:shot("crop_confirm")
  d:press("Destroy")
  d:frames(2)
  assert(not world.state.crops[at(1, 0)], "the crop was destroyed")
  assert(world.state.fields.tilled[at(1, 0)], "the soil stays tilled")

  -- Demolish a full woodshed.
  d:clickTile(bx + 5, by + 4)
  d:frames(2)
  d:shot("object_confirm")
  d:press("Destroy")
  d:frames(2)
  assert(not world.state.grid.objects[at(5, 4)], "the woodshed was destroyed")

  -- Plan radish over the potatoes: the preview marks the tiles that will be replaced.
  scene.selected = nil
  scene.seedButtons.radish.onPress()
  d:frames(3)
  d:pick("Plan field")
  d:clickTile(bx, by)
  scene.hover = at(3, 1)
  d:frames(3)
  d:shot("plan_preview")
  d:clickTile(bx + 3, by + 1)
  d:frames(2)
  d:shot("plan_confirm")
  d:press("Replace")
  d:frames(3)
  assert(not world.state.crops[at(0, 0)], "the old crop was replaced")
  assert(world.state.fields.plan[at(0, 0)] == "radish", "and the new crop is planned")
  d:shot("plan_replaced")
end
