-- Generates a new random homestead plot (GDD §7.3, §4.3): a meandering creek with fords, usually a
-- tributary running into it, still ponds (some of them marshes), a dirt road in from one edge ending
-- at the dead truck, soil quality, and a map of biome regions (oak, pine and birch woods, meadows, scrub,
-- rocky ground) with clearings, and a messy start of brush, rocks, logs and junk around the truck.
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

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- A second, narrower stream from a side edge to the main creek, away from the road row so it never
-- crosses the truck yard. It wanders a row up or down now and then and has a ford to wade across.
local function carveTributary(world, cfg, rng, truckAnchor)
  local grid = world.state.grid
  if not rng:chance(cfg.tributaryChance) then
    return
  end
  local _, truckY = Grid.coords(grid, truckAnchor)
  local roadRow = truckY + 1
  local margin = math.floor(grid.h * cfg.tributaryEdgeMargin)
  local y
  for _ = 1, 20 do
    local try = rng:int(margin + 1, grid.h - margin)
    if math.abs(try - roadRow) >= cfg.tributaryRoadGap then
      y = try
      break
    end
  end
  if not y then
    return
  end
  local width = rng:int(cfg.tributaryMinWidth, cfg.tributaryMaxWidth)
  local x, step = 1, 1
  if rng:chance(0.5) then
    x, step = grid.w, -1
  end
  local columns = {} -- the tiles of each column, in order from the edge
  while Grid.inBounds(grid, x, y) do
    local fromY = y
    if rng:chance(cfg.tributaryWanderChance) then
      y = math.max(3, math.min(grid.h - width - 1, y + (rng:chance(0.5) and 1 or -1)))
    end
    local joined = false
    local column = {}
    -- Cover both the old and the new rows on a step, so the banks of the stream stay joined edge to edge.
    for row = math.min(fromY, y), math.max(fromY, y) + width - 1 do
      local i = Grid.index(grid, x, row)
      local terrain = grid.terrain[i]
      if terrain == "water" or terrain == "ford" then
        joined = true
      elseif terrain == "grass" and Grid.distance(grid, i, truckAnchor) > cfg.truckClearRadius + 1 then
        column[#column + 1] = i
      end
    end
    if joined then
      break
    end
    for _, i in ipairs(column) do
      Grid.setTerrain(world, i, "water")
    end
    columns[#columns + 1] = column
    x = x + step
  end
  -- Fords in the middle stretch (not the mouth or the source), so the far side stays reachable.
  local count = #columns
  for _ = 1, cfg.tributaryFords do
    local column = columns[rng:int(math.max(1, math.floor(count / 4)), math.max(1, math.ceil(count * 3 / 4)))]
    for _, i in ipairs(column or {}) do
      Grid.setTerrain(world, i, "ford")
    end
  end
end

-- True when every tile in the box (clamped to the map) is plain grass, so a pond has open bank all round.
local function openGround(world, x0, y0, x1, y1)
  local grid = world.state.grid
  if x0 < 1 or y0 < 1 or x1 > grid.w or y1 > grid.h then
    return false
  end
  for y = y0, y1 do
    for x = x0, x1 do
      if grid.terrain[Grid.index(grid, x, y)] ~= "grass" then
        return false
      end
    end
  end
  return true
end

-- Ponds: lumpy still-water blobs. Each needs open grass all round (cfg.pondWaterGap), and sits between
-- pondTruckMin and pondTruckMax tiles from the truck. A marsh gets shallows (ford) round its rim.
-- Returns the tiles of each marsh's water, for the brush that grows on its banks.
local function placePonds(world, cfg, rng, truckAnchor)
  local grid = world.state.grid
  local marshes = {}
  local gap = cfg.pondWaterGap
  for _ = 1, rng:int(cfg.pondMin, cfg.pondMax) do
    for _ = 1, cfg.pondAttempts do
      local rx = rng:range(cfg.pondMinRadius, cfg.pondMaxRadius)
      local ry = math.max(cfg.pondMinRadius, rx * rng:range(cfg.pondSquash, 1))
      if rng:chance(0.5) then
        rx, ry = ry, rx -- some are tall, some are wide
      end
      local reachX, reachY = math.ceil(rx * (1 + cfg.pondLobes)), math.ceil(ry * (1 + cfg.pondLobes))
      local cx = rng:int(reachX + gap + 1, grid.w - reachX - gap)
      local cy = rng:int(reachY + gap + 1, grid.h - reachY - gap)
      local lobes, phase, amp = rng:int(2, 4), rng:range(0, math.pi * 2), cfg.pondLobes * rng:float()
      local fromTruck = Grid.distance(grid, Grid.index(grid, cx, cy), truckAnchor)
      if
        fromTruck >= cfg.pondTruckMin
        and fromTruck <= cfg.pondTruckMax
        and openGround(world, cx - reachX - gap, cy - reachY - gap, cx + reachX + gap, cy + reachY + gap)
      then
        local tiles, set = {}, {}
        for y = cy - reachY, cy + reachY do
          for x = cx - reachX, cx + reachX do
            local nx, ny = (x - cx) / rx, (y - cy) / ry
            local angle = math.atan2(ny, nx)
            if math.sqrt(nx * nx + ny * ny) <= 1 + amp * math.sin(lobes * angle + phase) then
              local i = Grid.index(grid, x, y)
              tiles[#tiles + 1] = i
              set[i] = true
            end
          end
        end
        if #tiles >= 8 then
          for _, i in ipairs(tiles) do
            Grid.setTerrain(world, i, "water")
          end
          if rng:chance(cfg.marshChance) then
            for _, i in ipairs(tiles) do
              local x, y = Grid.coords(grid, i)
              for _, d in ipairs(NEIGHBOURS) do
                local nx, ny = x + d[1], y + d[2]
                if Grid.inBounds(grid, nx, ny) then
                  local n = Grid.index(grid, nx, ny)
                  if not set[n] and grid.terrain[n] == "grass" and rng:chance(cfg.marshShallowChance) then
                    Grid.setTerrain(world, n, "ford")
                  end
                end
              end
            end
            marshes[#marshes + 1] = tiles
          end
          break
        end
      end
    end
  end
  return marshes
end

-- Every tile within `reach` of one of `tiles`, as a set (Chebyshev distance).
local function within(grid, tiles, reach)
  local set = {}
  for _, t in ipairs(tiles) do
    local tx, ty = Grid.coords(grid, t)
    for dy = -reach, reach do
      for dx = -reach, reach do
        if Grid.inBounds(grid, tx + dx, ty + dy) then
          set[Grid.index(grid, tx + dx, ty + dy)] = true
        end
      end
    end
  end
  return set
end

-- Round clearings in the woods. Each is { x, y, r }; `ok(x, y)` says whether a centre may go there.
local function pickCircles(world, rng, count, minR, maxR, ok)
  local grid = world.state.grid
  local list = {}
  for _ = 1, count do
    for _ = 1, 40 do
      local r = rng:range(minR, maxR)
      local x, y = rng:int(1, grid.w), rng:int(1, grid.h)
      if ok(x, y) then
        list[#list + 1] = { x = x, y = y, r = r }
        break
      end
    end
  end
  return list
end

--- 0..1 how deep (x, y) is inside the nearest circle of `list` (1 at the centre, 0 outside), and that circle.
local function depthIn(list, x, y)
  local best, which = 0, nil
  for _, c in ipairs(list) do
    local d = math.sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2)
    local t = 1 - d / c.r
    if t > best then
      best, which = t, c
    end
  end
  return best, which
end

-- Cut the map into biome regions: cells round random points (edges bent by noise), each given a biome. Every
-- biome gets a region before the spare ones are drawn by weight, and the truck's region is the start biome.
-- Returns biomeAt[i] = { id, def = the biome's tuning table, species = its tree odds as a sorted list }.
local function planBiomes(world, cfg, rng, truckAnchor)
  local grid = world.state.grid
  local ids = {}
  for id in pairs(cfg.biomes) do
    ids[#ids + 1] = id
  end
  table.sort(ids) -- pairs() order isn't stable; sort so the same seed gives the same land
  local byId = {}
  for _, id in ipairs(ids) do
    local def = cfg.biomes[id]
    local species = {}
    for kind, weight in pairs(def.species) do
      species[#species + 1] = { id = kind, weight = weight }
    end
    table.sort(species, function(l, r)
      return l.id < r.id
    end)
    byId[id] = { id = id, def = def, species = species }
  end
  local function weightOf(id)
    return cfg.biomes[id].weight
  end
  local cells = {}
  for n = 1, rng:int(cfg.biomeCellsMin, cfg.biomeCellsMax) do
    cells[n] = { x = rng:int(1, grid.w), y = rng:int(1, grid.h) }
  end
  -- The first cells take one of each biome (in a shuffled order); the rest are weighted draws.
  local order = {}
  for _, id in ipairs(ids) do
    order[#order + 1] = id
  end
  for n = #order, 2, -1 do
    local k = rng:int(1, n)
    order[n], order[k] = order[k], order[n]
  end
  for n, cell in ipairs(cells) do
    cell.biome = byId[order[n] or rng:weighted(ids, weightOf)]
  end
  local warpX = Noise.value(rng, grid.w, grid.h, cfg.biomeWarpScale)
  local warpY = Noise.value(rng, grid.w, grid.h, cfg.biomeWarpScale)
  local function nearest(x, y)
    local wx = x + (warpX(x, y) - 0.5) * 2 * cfg.biomeWarp
    local wy = y + (warpY(x, y) - 0.5) * 2 * cfg.biomeWarp
    local first, second, d1, d2
    for _, cell in ipairs(cells) do
      local d = math.sqrt((wx - cell.x) ^ 2 + (wy - cell.y) ^ 2)
      if not d1 or d < d1 then
        second, d2 = first, d1
        first, d1 = cell, d
      elseif not d2 or d < d2 then
        second, d2 = cell, d
      end
    end
    return first, second, d1, d2
  end
  local truckX, truckY = Grid.coords(grid, truckAnchor)
  local startCell = nearest(truckX, truckY)
  startCell.biome = byId[cfg.startBiome]
  local biomeAt = {}
  for y = 1, grid.h do
    for x = 1, grid.w do
      local first, second, d1, d2 = nearest(x, y)
      local pick = first
      -- A soft edge: close to a border, a tile may belong to the next region, more often the closer it is.
      if second and d2 - d1 < cfg.biomeEdgeBlend and rng:chance(0.5 * (1 - (d2 - d1) / cfg.biomeEdgeBlend)) then
        pick = second
      end
      biomeAt[Grid.index(grid, x, y)] = pick.biome
    end
  end
  return biomeAt
end

-- The shape of the land cover, drawn once so soil() and scatter() agree.
local function planCover(world, cfg, rng, truckAnchor, marshes)
  local grid = world.state.grid
  local biomeAt = planBiomes(world, cfg, rng, truckAnchor)
  local plan = {
    biomeAt = biomeAt,
    clearings = pickCircles(
      world,
      rng,
      rng:int(cfg.clearingMin, cfg.clearingMax),
      cfg.clearingMinRadius,
      cfg.clearingMaxRadius,
      function(x, y)
        return biomeAt[Grid.index(grid, x, y)].def.wood == true
      end
    ),
    marshBank = {},
  }
  for _, tiles in ipairs(marshes) do
    for i in pairs(within(grid, tiles, cfg.marshBrushReach)) do
      plan.marshBank[i] = true
    end
  end
  return plan
end

local function soil(world, cfg, rng, plan)
  local grid = world.state.grid
  local sample = Noise.value(rng, grid.w, grid.h, cfg.soilNoiseScale)
  for y = 1, grid.h do
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      local q = sample(x, y) + plan.biomeAt[i].def.soil
      for _, d in ipairs(NEIGHBOURS) do
        local nx, ny = x + d[1], y + d[2]
        if Grid.inBounds(grid, nx, ny) and grid.terrain[Grid.index(grid, nx, ny)] == "water" then
          q = q + cfg.soilCreekBonus
          break
        end
      end
      if depthIn(plan.clearings, x, y) > 0 then
        q = q + cfg.clearingSoilBonus
      end
      grid.soil[i] = math.floor(math.max(0, math.min(1, q)) * 100 + 0.5) / 100
    end
  end
end

local function scatter(world, cfg, rng, truckAnchor, plan)
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
          local biome = plan.biomeAt[i]
          local def = biome.def
          local clearing, circle = depthIn(plan.clearings, x, y)
          local grove = false
          if d >= cfg.treeMinDistance and clearing == 0 then
            if def.treeThreshold < 1 and trees(x, y) > def.treeThreshold then
              grove = rng:chance(def.density)
            else
              grove = rng:chance(def.lone) -- a lone tree standing in the open
            end
          end
          if grove then
            Grid.placeObject(world, rng:weighted(biome.species, weight).id, x, y)
          elseif rng:chance(def.rocks) then
            Grid.placeObject(world, "rock", x, y)
          elseif (plan.marshBank[i] and rng:chance(cfg.marshBrushChance)) or rng:chance(def.brush) then
            Grid.placeObject(world, "brush", x, y)
          elseif clearing > 0 and clearing < 1 / circle.r and rng:chance(cfg.clearingLogChance) then
            Grid.placeObject(world, "log", x, y) -- the clearing's rim (within a tile of its edge)
          elseif clearing == 0 then
            local falloff = math.max(0, 1 - (d - cfg.truckClearRadius) / (cfg.messRadius - cfg.truckClearRadius))
            local chance = (cfg.backgroundClutter + (cfg.messDensity - cfg.backgroundClutter) * falloff) * def.clutter
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
  carveTributary(world, cfg, rng, truckAnchor)
  local marshes = placePonds(world, cfg, rng, truckAnchor)
  local plan = planCover(world, cfg, rng, truckAnchor, marshes)
  soil(world, cfg, rng, plan)
  scatter(world, cfg, rng, truckAnchor, plan)

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
