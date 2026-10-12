-- A* pathfinding on the tile grid. 8-directional, no corner cutting, terrain/object walk costs.

local Grid = require("src.sim.grid")

local Pathfind = {}

local SQRT2 = math.sqrt(2)
local DIRS = {
  { 1, 0, 1 },
  { -1, 0, 1 },
  { 0, 1, 1 },
  { 0, -1, 1 },
  { 1, 1, SQRT2 },
  { 1, -1, SQRT2 },
  { -1, 1, SQRT2 },
  { -1, -1, SQRT2 },
}

-- Binary min-heap kept as parallel arrays (nodes, keys) plus a size, so a push allocates nothing.
-- The sift order and comparisons are exactly those of the original table-of-pairs heap, so ties
-- pop in the same order and paths are unchanged (#123).
local function push(nodes, keys, size, node, f)
  size = size + 1
  nodes[size], keys[size] = node, f
  local i = size
  while i > 1 do
    local parent = math.floor(i / 2)
    if keys[parent] <= keys[i] then
      break
    end
    nodes[parent], nodes[i] = nodes[i], nodes[parent]
    keys[parent], keys[i] = keys[i], keys[parent]
    i = parent
  end
  return size
end

local function pop(nodes, keys, size)
  local top = nodes[1]
  local lastNode, lastKey = nodes[size], keys[size]
  nodes[size], keys[size] = nil, nil
  size = size - 1
  if size > 0 then
    nodes[1], keys[1] = lastNode, lastKey
    local i = 1
    while true do
      local l, r, smallest = i * 2, i * 2 + 1, i
      if l <= size and keys[l] < keys[smallest] then
        smallest = l
      end
      if r <= size and keys[r] < keys[smallest] then
        smallest = r
      end
      if smallest == i then
        break
      end
      nodes[smallest], nodes[i] = nodes[i], nodes[smallest]
      keys[smallest], keys[i] = keys[i], keys[smallest]
      i = smallest
    end
  end
  return top, size
end

--- Find a path from tile `start` to any tile where isGoal(i) is true.
--- `target` (a tile index) guides the heuristic; pass noHeuristic = true for a plain Dijkstra
--- search (nearest of many goals). Returns an array of tile indices (excluding start; empty if
--- start is already a goal), or nil if unreachable.
function Pathfind.find(world, start, isGoal, target, noHeuristic)
  local grid = world.state.grid
  if isGoal(start) then
    return {}
  end
  local w, h = grid.w, grid.h
  local tx, ty = Grid.coords(grid, target)
  local function heuristic(i)
    if noHeuristic then
      return 0
    end
    local x, y = Grid.coords(grid, i)
    local dx, dy = math.abs(x - tx), math.abs(y - ty)
    return math.max(dx, dy) + (SQRT2 - 1) * math.min(dx, dy)
  end
  -- Walkability and walk cost cannot change during one search, so each tile is looked up once.
  local walkMemo = {}
  local function walkable(i)
    local v = walkMemo[i]
    if v == nil then
      v = Grid.walkable(world, i)
      walkMemo[i] = v
    end
    return v
  end
  local nodes, keys, size = {}, {}, 0
  local came, g, closed = {}, { [start] = 0 }, {}
  size = push(nodes, keys, size, start, heuristic(start))
  while size > 0 do
    local current
    current, size = pop(nodes, keys, size)
    if not closed[current] then
      if isGoal(current) then
        local path = {}
        while current ~= start do
          table.insert(path, 1, current)
          current = came[current]
        end
        return path
      end
      closed[current] = true
      local cx = (current - 1) % w + 1
      local cy = (current - cx) / w + 1
      local gCurrent = g[current]
      for k = 1, #DIRS do
        local d = DIRS[k]
        local nx, ny = cx + d[1], cy + d[2]
        if nx >= 1 and ny >= 1 and nx <= w and ny <= h then
          local n = (ny - 1) * w + nx
          local ok = not closed[n] and walkable(n)
          if ok and d[3] > 1 then
            -- No cutting corners past blocked tiles.
            ok = walkable((cy - 1) * w + nx) and walkable((ny - 1) * w + cx)
          end
          if ok then
            local cost = gCurrent + d[3] * Grid.walkCost(world, n)
            local old = g[n]
            if not old or cost < old then
              g[n] = cost
              came[n] = current
              size = push(nodes, keys, size, n, cost + heuristic(n))
            end
          end
        end
      end
    end
  end
  return nil
end

--- Dijkstra search for the nearest workable target by walking distance.
--- targets: { [tileIndex] = standOn } — standOn = true means the actor must stand on the tile,
--- otherwise any walkable tile within one step of it will do.
--- Returns path, target (or nil if none is reachable).
function Pathfind.nearest(world, start, targets)
  local grid = world.state.grid
  local function targetFrom(i)
    if not Grid.walkable(world, i) then
      return nil
    end
    if targets[i] ~= nil then
      return i
    end
    local x, y = Grid.coords(grid, i)
    local best
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if Grid.inBounds(grid, nx, ny) then
          local n = Grid.index(grid, nx, ny)
          if targets[n] == false and (not best or n < best) then
            best = n
          end
        end
      end
    end
    return best
  end
  local found
  local path = Pathfind.find(world, start, function(i)
    found = targetFrom(i)
    return found ~= nil
  end, start, true)
  return path, found
end

--- Path to a tile from which `target` can be worked: any walkable tile within one step of it
--- (including the target itself if walkable).
function Pathfind.toWorkSpot(world, start, target)
  local grid = world.state.grid
  return Pathfind.find(world, start, function(i)
    return Grid.distance(grid, i, target) <= 1 and Grid.walkable(world, i)
  end, target)
end

return Pathfind
