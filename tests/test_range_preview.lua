-- Placement range preview (#268, D108): the range of the item being placed, the ranges of placed items of the
-- same kind, and their overlap. Pure geometry over sim state; the drawing is in the Homestead scene.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local RangePreview = require("src.ui.range_preview")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(3))
end

-- A free tile with a clear (2r+1) square around it, near the middle of the map.
local function openSpot(world, r, notBefore)
  local grid = world.state.grid
  for y = 4 + r, grid.h - r - 3 do
    for x = (notBefore or 1) + r, grid.w - r - 3 do
      local clear = true
      for dy = -r, r do
        for dx = -r, r do
          local i = Grid.index(grid, x + dx, y + dy)
          if world.occupancy[i] or not Grid.terrain(world, i).tillable then
            clear = false
          end
        end
      end
      if clear then
        return Grid.index(grid, x, y), x, y
      end
    end
  end
end

T.test("range preview: items without a range have no preview", function()
  local world = newWorld()
  T.eq(RangePreview.build(world, "campfire", 1), nil)
  T.eq(RangePreview.spec(reg:get("objects", "campfire")), nil)
end)

T.test("range preview: radius comes from content, placed ones are listed, overlap is the intersection", function()
  local world = newWorld()
  local def = reg:get("objects", "auto_harvester")
  local r = def.machine.radius
  local spot, x, y = openSpot(world, r)
  Inventory.addObject(world, "auto_harvester")
  T.truthy(Inventory.place(world, "auto_harvester", spot))
  local lone = RangePreview.build(world, "auto_harvester", spot)
  T.eq(lone.kind, "machine")
  T.eq(lone.radius, r)
  T.eq(#lone.mine, (2 * r + 1) ^ 2)
  T.eq(#lone.others, 1)
  T.eq(#lone.others[1].tiles, (2 * r + 1) ^ 2)
  T.eq(#lone.overlap, #lone.mine) -- exactly on top of the placed one
  -- Two tiles to the right: they share a strip of (2r+1-2) columns.
  local grid = world.state.grid
  local shifted = RangePreview.build(world, "auto_harvester", Grid.index(grid, x + 2, y))
  T.eq(#shifted.overlap, (2 * r + 1 - 2) * (2 * r + 1))
  -- Far apart: no overlap, but the placed range is still shown.
  local far = RangePreview.build(world, "auto_harvester", Grid.index(grid, math.min(grid.w, x + 2 * r + 3), y))
  T.eq(#far.overlap, 0)
  T.eq(#far.others, 1)
  -- The object being moved does not count against itself.
  T.eq(#RangePreview.build(world, "auto_harvester", spot, spot).others, 0)
end)

T.test("range preview: kinds do not mix (a drip line ignores harvesters)", function()
  local world = newWorld()
  local r = reg:get("objects", "auto_harvester").machine.radius
  local spot = openSpot(world, r)
  Inventory.addObject(world, "auto_harvester")
  T.truthy(Inventory.place(world, "auto_harvester", spot))
  local drip = RangePreview.build(world, "drip_line", spot)
  T.eq(drip.kind, "drip")
  T.eq(drip.radius, reg:get("objects", "drip_line").drip.radius)
  T.eq(#drip.others, 0)
  T.eq(#drip.overlap, 0)
end)
