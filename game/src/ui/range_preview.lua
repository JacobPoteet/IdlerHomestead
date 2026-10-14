-- Range preview for placement (#268, D108): where an item with a range would reach if it stood on a tile, the
-- ranges of the items of the same kind already placed, and where the two overlap. Presentation only: it reads
-- sim state and the content definitions (`machine.radius`, `drip.radius`) and never changes them. The tiles
-- of placed items come from the same sim helpers the systems use (Machines.areaTiles, Water.dripTiles), so
-- what is drawn is what the sim does.

local Grid = require("src.sim.grid")
local Machines = require("src.sim.systems.machines")
local Water = require("src.sim.systems.water")

local RangePreview = {}

-- Object fields that give an item a square reach, in a fixed order, and how to read a placed item's tiles.
local KINDS = {
  { field = "machine", tiles = Machines.areaTiles },
  { field = "drip", tiles = Water.dripTiles },
}

--- The range kind of an object definition and its radius in tiles, or nil when it has no range.
function RangePreview.spec(def)
  for _, kind in ipairs(KINDS) do
    local value = def[kind.field]
    if value then
      return kind.field, value.radius
    end
  end
  return nil
end

--- Square of `radius` tiles around `tile`, clipped to the map (ascending indices).
function RangePreview.square(grid, tile, radius)
  local tx, ty = Grid.coords(grid, tile)
  local tiles = {}
  for y = ty - radius, ty + radius do
    for x = tx - radius, tx + radius do
      if Grid.inBounds(grid, x, y) then
        tiles[#tiles + 1] = Grid.index(grid, x, y)
      end
    end
  end
  return tiles
end

--- The preview for placing object `objectId` with its anchor on `tile`. `skip` is an anchor to leave out (the
--- object being moved, which is about to leave its old spot). Returns nil for an item with no range, else
--- { kind, radius, mine = { tile }, others = { { anchor, tiles } }, overlap = { tile } }.
function RangePreview.build(world, objectId, tile, skip)
  local def = world.registry:get("objects", objectId)
  local kind, radius = RangePreview.spec(def)
  if not kind then
    return nil
  end
  local grid = world.state.grid
  local mine = RangePreview.square(grid, tile, radius)
  local others, covered = {}, {}
  local tilesOf
  for _, k in ipairs(KINDS) do
    if k.field == kind then
      tilesOf = k.tiles
    end
  end
  for _, anchor in ipairs(Grid.anchorsWith(world, kind)) do
    if anchor ~= skip then
      local tiles = tilesOf(world, anchor)
      others[#others + 1] = { anchor = anchor, tiles = tiles }
      for _, i in ipairs(tiles) do
        covered[i] = true
      end
    end
  end
  local overlap = {}
  for _, i in ipairs(mine) do
    if covered[i] then
      overlap[#overlap + 1] = i
    end
  end
  return { kind = kind, radius = radius, mine = mine, others = others, overlap = overlap }
end

return RangePreview
