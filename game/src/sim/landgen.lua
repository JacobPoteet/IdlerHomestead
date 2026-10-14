-- Generates a new random homestead plot (GDD §7.3, §4.3): a meandering creek with fords,
-- a dirt road in from one edge ending at the dead truck, soil quality, tree clusters, and a
-- messy start of brush, rocks, logs and junk concentrated around the truck.
--
-- Uses the world's "land" random stream, so the same seed always makes the same plot.

local Grid = require("src.sim.grid")
local Noise = require("src.sim.noise")
local Pathfind = require("src.sim.pathfind")

local Landgen = {}

local function carveCreek(world, cfg, rng)
  local grid = world.state.grid
  local x = rng:int(math.floor(grid.w * cfg.creekMinX), math.floor(grid.w * cfg.creekMaxX))
  local width = rng:int(cfg.creekMinWidth, cfg.creekMaxWidth)
  local rows = {} -- rows[y] = { left, right }
  for y = 1, grid.h do
    if rng:chance(cfg.creekWanderChance) then
      x = x + (rng:chance(0.5) and 1 or -1)
    end
    if rng:chance(cfg.creekWidthChangeChance) then
      width = math.max(cfg.creekMinWidth, math.min(cfg.creekMaxWidth, width + (rng:chance(0.5) and 1 or -1)))
    end
    x = math.max(3, math.min(grid.w - width - 2, x))
    rows[y] = { x, x + width - 1 }
    for cx = x, x + width - 1 do
      Grid.setTerrain(world, Grid.index(grid, cx, y), "water")
    end
  end
  -- Fords: shallow crossings spread along the creek.
  for f = 1, cfg.fordCount do
    local band = grid.h / cfg.fordCount
    local y =
      rng:int(math.floor((f - 1) * band) + 3, math.max(math.floor((f - 1) * band) + 3, math.floor(f * band) - 3))
    for cx = rows[y][1], rows[y][2] do
      Grid.setTerrain(world, Grid.index(grid, cx, y), "ford")
    end
  end
  return rows
end

local function placeRoadAndTruck(world, cfg, rng, creekRows)
  local grid = world.state.grid
  local midY = math.floor(grid.h / 2)
  -- The truck goes on the wider side of the creek.
  local creekX = creekRows[midY][1]
  local fromLeft = creekX > grid.w / 2
  local y = rng:int(math.floor(grid.h * cfg.roadMinRow), math.floor(grid.h * cfg.roadMaxRow))
  -- The road runs in from the edge until the truck is a short walk from the creek, however wide the map is.
  local gap = rng:int(cfg.truckCreekGapMin, cfg.truckCreekGapMax)
  local length
  if fromLeft then
    length = creekRows[y][1] - gap
  else
    length = grid.w - creekRows[y][2] - gap
  end
  length = math.max(cfg.roadMinLength, length)
  local x, step = fromLeft and 1 or grid.w, fromLeft and 1 or -1
  for _ = 1, length do
    Grid.setTerrain(world, Grid.index(grid, x, y), "road")
    if rng:chance(cfg.roadWobbleChance) then
      local ny = y + (rng:chance(0.5) and 1 or -1)
      if ny > 2 and ny < grid.h - 1 then
        Grid.setTerrain(world, Grid.index(grid, x, ny), "road")
        y = ny
      end
    end
    x = x + step
  end
  local roadEnd = Grid.index(grid, x - step, y)
  -- Park the truck just past the end of the road, one row up (it's two tiles wide).
  local truckX = fromLeft and x or x - 1
  local anchor = Grid.placeObject(world, "truck", truckX, y - 1)
  assert(anchor, "landgen: could not place the truck")
  return roadEnd, anchor
end

local function soil(world, cfg, rng)
  local grid = world.state.grid
  local sample = Noise.value(rng, grid.w, grid.h, cfg.soilNoiseScale)
  for y = 1, grid.h do
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      local q = sample(x, y)
      for dx = -1, 1 do
        local nx = x + dx
        if dx ~= 0 and Grid.inBounds(grid, nx, y) and grid.terrain[Grid.index(grid, nx, y)] == "water" then
          q = q + cfg.soilCreekBonus
          break
        end
      end
      grid.soil[i] = math.floor(math.max(0, math.min(1, q)) * 100 + 0.5) / 100
    end
  end
end

local function scatter(world, cfg, rng, truckAnchor)
  local grid = world.state.grid
  local registry = world.registry
  local trees = Noise.value(rng, grid.w, grid.h, cfg.treeNoiseScale)
  local clutter = {}
  for id, weight in pairs(cfg.clutterWeights) do
    clutter[#clutter + 1] = { id = id, weight = weight }
  end
  table.sort(clutter, function(a, b)
    return a.id < b.id -- pairs() order isn't stable; sort so the same seed gives the same land
  end)
  local function weight(c)
    return c.weight
  end
  local junkClutter = {}
  for _, c in ipairs(clutter) do
    if c.id ~= "junk" then
      junkClutter[#junkClutter + 1] = c
    end
  end
  for y = 1, grid.h do
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      local terrainDef = registry:get("terrain", grid.terrain[i])
      if terrainDef.tillable and not world.occupancy[i] then
        local d = Grid.distance(grid, i, truckAnchor)
        if d > cfg.truckClearRadius then
          if d >= cfg.treeMinDistance and trees(x, y) > cfg.treeThreshold then
            Grid.placeObject(world, "tree", x, y)
          else
            local falloff = math.max(0, 1 - (d - cfg.truckClearRadius) / (cfg.messRadius - cfg.truckClearRadius))
            local chance = cfg.backgroundClutter + (cfg.messDensity - cfg.backgroundClutter) * falloff
            if rng:chance(chance) then
              local pool = d <= cfg.junkRadius and clutter or junkClutter
              Grid.placeObject(world, rng:weighted(pool, weight).id, x, y)
            end
          end
        end
      end
    end
  end
end

-- Water is essential from minute one, so make sure the spawn can walk to the creek: find the
-- shortest route ignoring objects, then remove anything blocking along it (except the truck).
local function ensureWaterAccess(world, spawn)
  local grid = world.state.grid
  local targets = {}
  for i = 1, #grid.terrain do
    if grid.terrain[i] == "water" then
      targets[i] = false
    end
  end
  if Pathfind.nearest(world, spawn, targets) then
    return
  end
  local saved = world.occupancy
  world.occupancy = {}
  local path = Pathfind.nearest(world, spawn, targets)
  world.occupancy = saved
  local function clear(i)
    local def, anchor = Grid.object(world, i)
    if def and def.blocks and def.clearable ~= false then
      Grid.removeObject(world, anchor)
    end
  end
  local prev = spawn
  for _, i in ipairs(path or {}) do
    clear(i)
    -- Diagonal steps also need both corner tiles open (no cutting corners).
    local px, py = Grid.coords(grid, prev)
    local x, y = Grid.coords(grid, i)
    if px ~= x and py ~= y then
      clear(Grid.index(grid, x, py))
      clear(Grid.index(grid, px, y))
    end
    prev = i
  end
end

--- Fill grid.waterTable[i] (0..1: how close groundwater is to the surface) from the seed. It uses
--- its own random stream ("watertable"), so it never disturbs the plot and runs saved before the
--- water table existed can gain the same table for their seed (Land.init calls this when missing).
function Landgen.waterTable(world)
  local cfg = world.tuning.water.table
  local grid = world.state.grid
  local sample = Noise.value(world:rng("watertable"), grid.w, grid.h, cfg.noiseScale)
  local reach = cfg.creekReach
  local creek = {}
  for i = 1, #grid.terrain do
    if grid.terrain[i] == "water" then
      creek[#creek + 1] = i
    end
  end
  -- Nearness to the creek (0..1) by a bounded spread from each creek tile.
  local near = {}
  for _, c in ipairs(creek) do
    local cx, cy = Grid.coords(grid, c)
    for dy = -reach, reach do
      for dx = -reach, reach do
        if Grid.inBounds(grid, cx + dx, cy + dy) then
          local i = Grid.index(grid, cx + dx, cy + dy)
          local closeness = 1 - math.max(math.abs(dx), math.abs(dy)) / reach
          if closeness > (near[i] or 0) then
            near[i] = closeness
          end
        end
      end
    end
  end
  grid.waterTable = {}
  for y = 1, grid.h do
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      local value = sample(x, y) * (1 - cfg.creekWeight) + (near[i] or 0) * cfg.creekWeight
      grid.waterTable[i] = math.floor(math.max(0, math.min(1, value)) * 100 + 0.5) / 100
    end
  end
end

--- Fill world.state.grid and world.state.land for a fresh run.
function Landgen.generate(world)
  local tuning = world.tuning
  local cfg = tuning.landgen
  local rng = world:rng("land")
  local w, h = tuning.world.mapWidth, tuning.world.mapHeight
  local grid = { w = w, h = h, terrain = {}, soil = {}, objects = {} }
  for i = 1, w * h do
    grid.terrain[i] = "grass" -- a fresh array no cache has seen; later writes use Grid.setTerrain
  end
  world.state.grid = grid
  world.occupancy = {}
  world.objectIndex = nil

  local creekRows = carveCreek(world, cfg, rng)
  local roadEnd, truckAnchor = placeRoadAndTruck(world, cfg, rng, creekRows)
  soil(world, cfg, rng)
  scatter(world, cfg, rng, truckAnchor)

  local tx, ty = Grid.coords(grid, truckAnchor)
  ensureWaterAccess(world, Grid.index(grid, tx, ty + 1))
  world.state.land = {
    truck = truckAnchor,
    dropoff = roadEnd, -- where deliveries arrive (GDD §6.3)
    spawn = Grid.index(grid, tx, ty + 1), -- the homesteader starts beside the truck
    flowX = 0, -- direction the creek flows, for the water shader
    flowY = 1,
  }
end

return Landgen
