-- The water ladder (GDD §5.3): a dug well, hand pump, solar pump, cistern and drip lines beside a
-- planted patch; the object cards for each; and a drip zone gone dry. The scenario sets the
-- homestead up directly (as if bought and placed), then lets the sim run so the pump and drip
-- lines do real work before each capture.
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

-- Place `id` on the free tile nearest `near` where it fits. Returns its anchor tile index.
local function place(world, id, near)
  local grid = world.state.grid
  local nx, ny = Grid.coords(grid, near)
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - nx) ^ 2 + (y - ny) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot for " .. id)
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, best))
  return best
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local site = Grid.index(grid, math.min(grid.w - 12, sx + 3), math.max(4, sy - 1))
  d:advance(5) -- up to late morning, so the sun is up and the pump has power

  -- Tidy the clutter around the site so the capture shows the equipment, not the messy start.
  local siteX, siteY = Grid.coords(grid, site)
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - siteX) <= 8 and math.abs(y - siteY) <= 9 then
      Grid.removeObject(world, anchor)
    end
  end

  local well = place(world, "well", site)
  local wx, wy = Grid.coords(grid, well)
  place(world, "hand_pump", Grid.index(grid, wx + 2, wy))
  local cistern = place(world, "cistern", Grid.index(grid, wx + 1, wy + 2))
  local px, py = Grid.coords(grid, cistern)
  place(world, "solar_array", Grid.index(grid, px + 3, py + 1))
  local pump = place(world, "dc_pump", Grid.index(grid, px, py - 2))
  local drip = place(world, "drip_line", Grid.index(grid, px + 1, py + 3))
  assert(drip)
  local dx, dy = Grid.coords(grid, drip)
  -- A sprinkler beside the drip line (D118): the same patch size, a full unit of water per crop.
  local sprinkler = place(world, "sprinkler", Grid.index(grid, dx - 4, dy))

  -- A small planted patch around the drip line: tilled, planted, some of it thirsty.
  local patch = 0
  for y = dy - 2, dy + 2 do
    for x = dx - 2, dx + 2 do
      local i = Grid.index(grid, x, y)
      if Grid.inBounds(grid, x, y) and Grid.terrain(world, i).tillable and not world.occupancy[i] and not Crops.tileInUse(world, i) then
        world.state.fields.tilled[i] = true
        world.state.fields.plan[i] = "radish"
        patch = patch + 1
        if patch % 3 ~= 0 then
          world.state.crops[i] = { id = "radish", growth = 0.3, moisture = (patch % 2) * 0.8 }
        end
      end
    end
  end
  Ledger.add(world, "water", 38)

  local scene = d:scene()
  local view = d.game.app.view
  local cx, cy = scene.camera:tileToWorld(px, py + 0.5)
  scene.camera:centerOn(cx, cy, view)
  d:advance(1)
  d:shot("homestead")

  -- Object cards (a tap on the pump would open the power panel, so inspect by selecting).
  local function card(name, tile)
    scene.selected = tile
    d:frames(2)
    d:shot(name)
  end
  card("card_cistern", cistern)
  card("card_drip_zone", drip)
  card("card_sprinkler_zone", sprinkler)
  card("card_pump", pump)
  card("card_well", well)

  -- Placing a well: the tiles with a high water table are tinted.
  scene.selected = nil
  Inventory.addObject(world, "well")
  scene.mode, scene.placing = "place", "well"
  d:frames(2)
  d:shot("placing_well")
  scene.mode, scene.placing = "act", nil
  world.state.inventory.objects.well = nil -- the spare well was only there to show the placement tint
  scene:layout()

  -- The cistern runs dry while crops are thirsty: the drip line shows red and says so.
  Ledger.remove(world, "water", Ledger.get(world, "water"))
  for _, crop in pairs(world.state.crops) do
    crop.moisture = 0
  end
  d:frames(4)
  scene.selected = drip
  d:frames(2)
  d:shot("drip_dry")
  scene.selected = sprinkler
  d:frames(2)
  d:shot("sprinkler_dry")
end
