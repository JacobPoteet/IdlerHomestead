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

-- Binary min-heap of { node, f }.
local function push(heap, node, f)
  heap[#heap + 1] = { node, f }
  local i = #heap
  while i > 1 do
    local parent = math.floor(i / 2)
    if heap[parent][2] <= heap[i][2] then
      break
    end
    heap[parent], heap[i] = heap[i], heap[parent]
    i = parent
  end
end

local function pop(heap)
  local top = heap[1]
  local last = table.remove(heap)
  if #heap > 0 then
    heap[1] = last
    local i = 1
    while true do
      local l, r, smallest = i * 2, i * 2 + 1, i
      if l <= #heap and heap[l][2] < heap[smallest][2] then
        smallest = l
      end
      if r <= #heap and heap[r][2] < heap[smallest][2] then
        smallest = r
      end
      if smallest == i then
        break
      end
      heap[smallest], heap[i] = heap[i], heap[smallest]
      i = smallest
    end
  end
  return top[1]
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
  local tx, ty = Grid.coords(grid, target)
  local function h(i)
    if noHeuristic then
      return 0
    end
    local x, y = Grid.coords(grid, i)
    local dx, dy = math.abs(x - tx), math.abs(y - ty)
    return math.max(dx, dy) + (SQRT2 - 1) * math.min(dx, dy)
  end
  local open, came, g, closed = {}, {}, { [start] = 0 }, {}
  push(open, start, h(start))
  while #open > 0 do
    local current = pop(open)
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
      local cx, cy = Grid.coords(grid, current)
      for _, d in ipairs(DIRS) do
        local nx, ny = cx + d[1], cy + d[2]
        if Grid.inBounds(grid, nx, ny) then
          local n = Grid.index(grid, nx, ny)
          local ok = not closed[n] and Grid.walkable(world, n)
          if ok and d[3] > 1 then
            -- No cutting corners past blocked tiles.
            ok = Grid.walkable(world, Grid.index(grid, nx, cy)) and Grid.walkable(world, Grid.index(grid, cx, ny))
          end
          if ok then
            local cost = g[current] + d[3] * Grid.walkCost(world, n)
            if not g[n] or cost < g[n] then
              g[n] = cost
              came[n] = current
              push(open, n, cost + h(n))
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
