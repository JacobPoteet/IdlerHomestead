-- Tile grid helpers: the shared interface for anything that reads or changes the land.
--
-- State (world.state.grid), all plain data:
--   w, h                 size in tiles
--   terrain[i]           terrain id per tile (flat array, i = (y - 1) * w + x)
--   soil[i]              soil quality 0..1
--   objects[anchor]      { id = objectId } keyed by the object's top-left tile index
-- Runtime only (rebuilt on load): world.occupancy[i] = anchor index of the object covering tile i.

local Grid = {}

function Grid.index(grid, x, y)
  return (y - 1) * grid.w + x
end

function Grid.coords(grid, i)
  local x = (i - 1) % grid.w + 1
  return x, (i - x) / grid.w + 1
end

function Grid.inBounds(grid, x, y)
  return x >= 1 and y >= 1 and x <= grid.w and y <= grid.h
end

function Grid.terrain(world, i)
  return world.registry:get("terrain", world.state.grid.terrain[i])
end

--- Object covering tile i: returns def, anchorIndex, objectState (or nil).
function Grid.object(world, i)
  local anchor = world.occupancy[i]
  if not anchor then
    return nil
  end
  local obj = world.state.grid.objects[anchor]
  return world.registry:get("objects", obj.id), anchor, obj
end

local function footprint(def)
  return def.footprintW or 1, def.footprintH or 1
end

--- Tile indices covered by an object of `def` anchored at (x, y).
function Grid.footprintTiles(grid, def, x, y)
  local fw, fh = footprint(def)
  local tiles = {}
  for dy = 0, fh - 1 do
    for dx = 0, fw - 1 do
      if not Grid.inBounds(grid, x + dx, y + dy) then
        return nil
      end
      tiles[#tiles + 1] = Grid.index(grid, x + dx, y + dy)
    end
  end
  return tiles
end

function Grid.rebuildOccupancy(world)
  local grid = world.state.grid
  world.occupancy = {}
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    for _, i in ipairs(Grid.footprintTiles(grid, world.registry:get("objects", obj.id), x, y)) do
      world.occupancy[i] = anchor
    end
  end
end

--- Place an object if its whole footprint is in bounds and free. Returns the anchor index or nil.
function Grid.placeObject(world, id, x, y)
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local tiles = Grid.footprintTiles(grid, def, x, y)
  if not tiles then
    return nil
  end
  for _, i in ipairs(tiles) do
    if world.occupancy[i] then
      return nil
    end
  end
  local anchor = Grid.index(grid, x, y)
  grid.objects[anchor] = { id = id }
  for _, i in ipairs(tiles) do
    world.occupancy[i] = anchor
  end
  return anchor
end

function Grid.removeObject(world, anchor)
  local grid = world.state.grid
  local obj = grid.objects[anchor]
  if not obj then
    return
  end
  local x, y = Grid.coords(grid, anchor)
  for _, i in ipairs(Grid.footprintTiles(grid, world.registry:get("objects", obj.id), x, y)) do
    world.occupancy[i] = nil
  end
  grid.objects[anchor] = nil
end

function Grid.walkable(world, i)
  if not Grid.terrain(world, i).walkable then
    return false
  end
  local def = Grid.object(world, i)
  return not (def and def.blocks)
end

-- Bank tile lists, keyed weakly by the terrain array so a fresh or loaded grid recomputes them.
-- Runtime cache only, never saved. Terrain is fixed after land generation, so it never goes stale.
local bankCache = setmetatable({}, { __mode = "k" })

--- Ascending tile indices of `terrainId` tiles that can be worked from land: the tile itself or
--- one of its eight neighbours is walkable terrain (ignoring objects, which come and go). Water
--- with no such neighbour can never be reached, so idle routines don't need to consider it.
function Grid.bankTiles(world, terrainId)
  local grid = world.state.grid
  local byTerrain = bankCache[grid.terrain]
  if not byTerrain then
    byTerrain = {}
    bankCache[grid.terrain] = byTerrain
  end
  local list = byTerrain[terrainId]
  if list then
    return list
  end
  list = {}
  for i = 1, #grid.terrain do
    if grid.terrain[i] == terrainId then
      local x, y = Grid.coords(grid, i)
      local reachable = false
      for dy = -1, 1 do
        for dx = -1, 1 do
          if not reachable and Grid.inBounds(grid, x + dx, y + dy) then
            local n = Grid.index(grid, x + dx, y + dy)
            reachable = Grid.terrain(world, n).walkable == true
          end
        end
      end
      if reachable then
        list[#list + 1] = i
      end
    end
  end
  byTerrain[terrainId] = list
  return list
end

--- Movement cost multiplier for entering tile i (assumes walkable).
function Grid.walkCost(world, i)
  local cost = Grid.terrain(world, i).walkCost or 1
  local def = Grid.object(world, i)
  if def and def.walkCost then
    cost = cost * def.walkCost
  end
  return cost
end

--- Chebyshev distance between two tiles.
function Grid.distance(grid, a, b)
  local ax, ay = Grid.coords(grid, a)
  local bx, by = Grid.coords(grid, b)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

return Grid
