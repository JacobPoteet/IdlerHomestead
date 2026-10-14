-- Shelter ladder (D82, #198): placing a camp (preview with the heater slot), the object card with
-- insulation and heater slot, a wood stove beside the camp, the shack, and the night view.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Calendar = require("src.sim.systems.calendar")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(4)
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  local scene, view = d:scene(), d.game.app.view

  -- Tidy the clutter around the truck so the shots show only the ladder.
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if
      world.registry:get("objects", obj.id).clearable ~= false
      and math.abs(x - tx) <= 12
      and math.abs(y - ty) <= 10
    then
      Grid.removeObject(world, anchor)
    end
  end
  local function look(x, y)
    local cx, cy = scene.camera:tileToWorld(x, y)
    scene.camera:centerOn(cx, cy, view)
    d:frames(3)
  end
  --- First tile at or after (x0, y0), scanning right then down, where `id` can be placed at once.
  local function spot(id, x0, y0)
    Inventory.addObject(world, id)
    for y = y0, y0 + 8 do
      for x = x0, x0 + 8 do
        if Grid.inBounds(grid, x, y) and Inventory.canPlace(world, id, Grid.index(grid, x, y)) then
          return x, y
        end
      end
    end
    error("no spot for " .. id)
  end
  --- Place `id` (already in the inventory) through the Place tool at (x, y), showing the preview first.
  local function build(id, label, x, y, shotName)
    scene:layout()
    d:pick("Place " .. label)
    scene.hover = Grid.index(grid, x, y)
    d:frames(2)
    d:shot(shotName)
    d:clickTile(x, y)
    d:frames(3)
    assert(grid.objects[Grid.index(grid, x, y)], id .. " went up")
    scene.mode = "act"
  end

  -- A camp: the preview shows the heater slot (a stove inside it counts in full).
  local cx, cy = spot("camp", tx + 2, ty + 2)
  look(cx + 2, cy + 1)
  build("camp", "camp", cx, cy, "camp_preview")

  -- A stove beside it: placing a heat source shows the sleeping shelter's slot.
  local sx, sy = spot("wood_stove", cx + 3, cy)
  build("wood_stove", "wood stove", sx, sy, "stove_preview")

  -- The camp's card: insulation, rest and heater slot.
  scene.selected = Grid.index(grid, cx, cy)
  d:frames(2)
  d:shot("camp_card")

  -- The shack and its card. (A shack goes over a standing camp, D115, and the shack scenario shows that; here the camp is
  -- cleared first so this one still shows a shack on open ground.)
  Grid.removeObject(world, Grid.index(grid, cx, cy))
  local hx, hy = spot("shack", tx + 2, cy + 4)
  look(hx + 2, hy)
  build("shack", "shack", hx, hy, "shack_preview")
  scene.selected = Grid.index(grid, hx, hy)
  d:frames(2)
  d:shot("shack_card")

  -- Night.
  scene.selected = nil
  local dayLength = world.tuning.time.dayLength
  local _, sunset = Calendar.daylight(world)
  local now = Calendar.now(world)
  world.state.calendar.elapsed = world.state.calendar.elapsed + ((sunset + 1.5 - now.hour) % 24) / 24 * dayLength
  d:frames(30, 0.05)
  d:shot("night")
end
