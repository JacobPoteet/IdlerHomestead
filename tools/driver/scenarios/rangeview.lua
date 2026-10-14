-- Placement range preview (#268, D108): placing a third auto-harvester shows its own 7x7 reach, the dimmed
-- reaches of the two already placed, and the overlap tiles highlighted. Shots with the mouse hovering, with a
-- finger held (touch, no hover), and a drip line's preview next to a placed one.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")

-- Place `id` with its anchor on tile (x, y); returns the anchor index.
local function placeAt(world, id, x, y)
  local grid = world.state.grid
  local i = Grid.index(grid, x, y)
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, i), "cannot place " .. id .. " at " .. x .. "," .. y)
  return i
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  d:advance(4)

  -- Tidy a patch beside the spawn so the capture shows ranges, not clutter.
  local cx, cy = sx + 8, sy
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - cx) <= 12 and math.abs(y - cy) <= 8 then
      Grid.removeObject(world, anchor)
    end
  end
  local scene, view = d:scene(), d.game.app.view
  local wx, wy = scene.camera:tileToWorld(cx, cy)
  scene.camera:centerOn(wx, wy, view)

  placeAt(world, "auto_harvester", cx - 5, cy)
  placeAt(world, "auto_harvester", cx + 4, cy)

  -- Mouse: the ghost under the pointer overlaps both.
  Inventory.addObject(world, "auto_harvester")
  scene.mode, scene.placing = "place", "auto_harvester"
  scene.hover = Grid.index(grid, cx, cy + 1)
  scene.selected = nil
  scene:layout()
  d:frames(2)
  d:shot("harvester_hover")

  -- Touch: no hover, the finger held on a tile shows the same preview.
  scene.hover = nil
  scene.pressTile = Grid.index(grid, cx, cy + 1)
  d:frames(2)
  d:shot("harvester_held")
  scene.pressTile = nil

  -- Far enough from both: its own range and the dimmed two, no overlap.
  scene.hover = Grid.index(grid, cx, cy + 9)
  d:frames(2)
  d:shot("harvester_clear")

  -- Another kind of range: a drip line beside a placed one.
  world.state.inventory.objects.auto_harvester = nil
  Inventory.addObject(world, "drip_line")
  scene.placing, scene.hover = "drip_line", Grid.index(grid, cx - 3, cy - 5)
  placeAt(world, "drip_line", cx - 6, cy - 5)
  local dx, dy = scene.camera:tileToWorld(cx - 4, cy - 4)
  scene.camera:centerOn(dx, dy, view)
  scene:layout()
  d:frames(2)
  d:shot("drip")
end
