-- Untill and placing over clutter and crops (D79, #197): the Untill tool and its caption, a tilled tile
-- turning back to grass, the placement preview over a tree (green/amber ghost and outlines), the
-- confirmation card, the queued order working, the card over a ripe crop with its warning, and the
-- finished building. The scenario sets the field up directly, then plays through taps.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Placement = require("src.sim.systems.placement")
local PlaceCard = require("src.ui.place_card")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local bx, by = math.min(grid.w - 9, sx + 5), math.min(grid.h - 7, sy + 2)
  d:advance(4)

  -- Tidy the clutter so the capture shows only what the scenario sets out.
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - bx) <= 8 and math.abs(y - by) <= 7 then
      Grid.removeObject(world, anchor)
    end
  end
  local function at(dx, dy)
    return Grid.index(grid, bx + dx, by + dy)
  end
  -- A little field: radishes (one ripe), a tilled strip left over, and a tree and two rocks on the grass.
  for dx = 3, 6 do
    for dy = 0, 1 do
      local i = at(dx, dy)
      world.state.fields.tilled[i] = true
      world.state.fields.plan[i] = "radish"
      world.state.crops[i] = { id = "radish", growth = dx == 6 and dy == 0 and 1 or 0.5, moisture = 1 }
    end
  end
  for dx = 3, 5 do
    world.state.fields.tilled[at(dx, 3)] = true
  end
  world.state.fields.plan[at(3, 3)] = "potato"
  Grid.placeObject(world, "tree", bx, by)
  Grid.placeObject(world, "rock", bx + 1, by + 2)
  Grid.placeObject(world, "rock", bx - 1, by + 1)

  local scene = d:scene()
  local view = d.game.app.view
  local cx, cy = scene.camera:tileToWorld(bx + 3, by + 1)
  scene.camera:centerOn(cx, cy, view)
  d:frames(3)

  -- Untill: the tool in hand, its caption, then a tap on a tilled tile.
  d:pick("Untill")
  d:frames(2)
  d:shot("untill_tool")
  d:clickTile(bx + 4, by + 3)
  d:frames(2)
  for _ = 1, 30 do
    d:frames(10)
    if not world.state.fields.tilled[at(4, 3)] then
      break
    end
  end
  assert(not world.state.fields.tilled[at(4, 3)], "the tile was untilled")
  d:shot("untilled")
  d:pick("Untill") -- back to the empty hand

  -- Placing a smoker on the tree: green where free, amber with outlines where something must go first.
  Inventory.addObject(world, "smoker")
  scene:layout()
  d:pick("Place smoker")
  scene.hover = at(0, 0)
  d:frames(2)
  d:shot("preview_tree")
  d:clickTile(bx, by)
  d:frames(2)
  d:shot("confirm_tree")
  d:press("Go ahead")
  d:frames(3)
  -- The homesteader works through the order.
  for _ = 1, 40 do
    d:frames(10)
    if world.state.grid.objects[at(0, 0)] and world.state.grid.objects[at(0, 0)].id ~= "tree" then
      break
    end
    if world.occupancy[at(0, 0)] and Placement.orderAt(world, at(0, 0)) and world.state.actors[1].job then
      local progress = require("src.sim.systems.actors").progress(world, world.state.actors[1])
      if progress and progress.fraction > 0.5 then
        break
      end
    end
  end
  scene.selected = at(0, 0)
  d:frames(2)
  d:shot("queued")

  -- A tap on the waiting building shows its order; let it finish.
  for _ = 1, 80 do
    d:frames(10)
    if #Placement.orders(world) == 0 then
      break
    end
  end
  scene.selected = nil
  d:frames(2)
  d:shot("built")

  -- A campfire over the ripe radish: the confirmation warns that the harvest is lost.
  Inventory.addObject(world, "campfire")
  scene:layout()
  d:pick("Place campfire")
  scene.hover = at(6, 0)
  d:frames(2)
  d:shot("preview_crop")
  d:clickTile(bx + 6, by)
  d:frames(2)
  d:shot("confirm_crop")
  d:press("Cancel")
  d:frames(2)
  d:shot("cancelled")
  assert(world.state.crops[at(6, 0)], "cancelling keeps the ripe crop (D86)")

  -- A target near the bottom of the view (#206): the camera pans so the card never covers the footprint.
  scene:setHand(nil, nil)
  d:pick("Place campfire") -- the campfire from above is still in the inventory
  local lowTree = at(0, 5)
  Grid.placeObject(world, "tree", bx, by + 5)
  local wx, wy = scene.camera:tileToWorld(bx, by + 5)
  local z = scene.camera:zoom()
  scene.camera.x = wx + 8
  scene.camera.y = wy + 8 - (view.h - scene.bottomH - 30 - view.h / 2) / z -- the tile sits just above the toolbar
  scene.camera:clamp(view)
  scene.toast = nil -- the "Tap where the campfire should go" toast sits on this row and a tap on it opens the log (D90)
  d:frames(2)
  d:clickTile(bx, by + 5)
  d:frames(3)
  d:shot("confirm_bottom")
  assert(
    world.state.grid.objects[lowTree] and scene.card and scene.placeCard,
    string.format(
      "the card is open over a target near the bottom (tree %s card %s placeCard %s, tile %d,%d of %dx%d, terrain %s)",
      tostring(world.state.grid.objects[lowTree] ~= nil),
      tostring(scene.card ~= nil),
      tostring(scene.placeCard ~= nil),
      bx,
      by + 5,
      grid.w,
      grid.h,
      tostring(world.state.grid.terrain[Grid.index(grid, bx, by + 5)])
    )
  )
  -- The pan was a glide (#221, D120): after a drag with the card open the target slides back under it, and
  -- once the player lets go the view eases back so the card never covers the tile.
  assert(not scene.autoPan or scene.autoPan.t < 1, "the fit eased in rather than jumping")
  d:frames(30)
  assert(not scene.autoPan, "the glide finished")
  d:drag(60, 140, 60, 330, 6)
  d:shot("confirm_dragged")
  assert(scene.refitTimer, "the drag armed the re-fit")
  d:frames(12)
  d:shot("confirm_refit_mid")
  d:frames(90)
  d:shot("confirm_refit")
  local rect = scene:placeCardRect()
  assert(rect and not PlaceCard.overlaps(rect, scene.card.y, scene.card.h, 0), "the re-fit cleared the card")
  d:press("Go ahead")
  d:frames(3)
  d:clickTile(bx, by + 5)
  d:frames(3)
  d:shot("order_bottom")
  d:press("Close")
  d:frames(2)
end
