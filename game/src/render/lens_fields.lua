-- What a lens paints, as data (GDD §9.4, D141, D145). Pure Lua, no drawing: it reads the sim through its
-- accessors and returns one 0..1 value per tile in four channels, plus a few markers (connections, reach rings,
-- gauges) in tile units. src/render/lens.lua uploads the channels as a texture for shaders/lens.glsl and draws the
-- markers; tests read this directly. Never changes the sim.
--
--   Power:  r = source pools, g = sink bands, b = sinks that are short of power, a = unused
--   Soil:   r = fertility, g = the farm (tilled, planned or planted), b = weeds on the farm (D180), a = farmable ground
--   Water:  r = water table, g = irrigation coverage (count / 4), b = ground a well or pump can go on,
--           a = coverage of lines that have run dry (count / 4)
--
-- A field is the strongest of the radial falloffs of the objects that make it, so pools of neighbours join.

local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")
local RangePreview = require("src.ui.range_preview")
local Soil = require("src.sim.systems.soil")
local Water = require("src.sim.systems.water")

local Fields = {}

local function blank(grid)
  local n = grid.w * grid.h
  local markers = { connections = {}, reach = {}, gauges = {} }
  local f = { w = grid.w, h = grid.h, r = {}, g = {}, b = {}, a = {}, markers = markers }
  for i = 1, n do
    f.r[i], f.g[i], f.b[i], f.a[i] = 0, 0, 0, 0
  end
  return f
end

--- Centre of the object at `anchor` in tile units (tile x spans x-1 .. x).
function Fields.centre(world, anchor)
  local grid = world.state.grid
  local def = world.registry:get("objects", grid.objects[anchor].id)
  local ax, ay = Grid.coords(grid, anchor)
  return ax - 1 + (def.footprintW or 1) / 2, ay - 1 + (def.footprintH or 1) / 2, def
end

--- Raise `channel` around (cx, cy) (tile units) to `strength` at the centre, falling to 0 at `radius` tiles.
function Fields.pool(f, channel, cx, cy, radius, strength, falloff)
  local x1, x2 = math.max(1, math.floor(cx - radius)), math.min(f.w, math.ceil(cx + radius) + 1)
  local y1, y2 = math.max(1, math.floor(cy - radius)), math.min(f.h, math.ceil(cy + radius) + 1)
  for y = y1, y2 do
    for x = x1, x2 do
      local d = math.sqrt((x - 0.5 - cx) ^ 2 + (y - 0.5 - cy) ^ 2)
      if d < radius then
        local v = strength * (1 - d / radius) ^ falloff
        local i = (y - 1) * f.w + x
        if v > channel[i] then
          channel[i] = v
        end
      end
    end
  end
end

local function nearest(nodes, from, skip)
  local best, bestD
  for _, n in ipairs(nodes) do
    if n ~= skip then
      local d = (n.x - from.x) ^ 2 + (n.y - from.y) ^ 2
      if not bestD or d < bestD then
        best, bestD = n, d
      end
    end
  end
  return best
end

--- The power lens's fields. `cfg` = tuning.visuals.lens.power.
function Fields.power(world, cfg)
  local f = blank(world.state.grid)
  local sources, sinks, banks = {}, {}, {}
  for _, s in ipairs(Power.sourceList(world)) do
    local cx, cy = Fields.centre(world, s.anchor)
    local live = s.peak > 0 and math.min(1, s.output / s.peak) or 0
    local radius = cfg.sourceBase + cfg.sourcePerKw * s.peak
    Fields.pool(f, f.r, cx, cy, radius, cfg.sourceFloor + (1 - cfg.sourceFloor) * live, cfg.falloff)
    sources[#sources + 1] = { x = cx, y = cy, live = s.output > 0 }
  end
  for _, s in ipairs(Power.sinkList(world)) do
    local cx, cy, def = Fields.centre(world, s.anchor)
    local level = cfg.sinkFloor + (1 - cfg.sinkFloor) * math.min(1, s.draw / cfg.drawFull)
    if s.state == "off" then
      level = level * cfg.offLevel
    elseif s.state == "idle" then
      level = level * cfg.idleLevel
    end
    local radius = cfg.sinkBase + cfg.sinkPerKw * s.draw
    Fields.pool(f, f.g, cx, cy, radius, level, cfg.falloff)
    if s.state == "short" then
      Fields.pool(f, f.b, cx, cy, radius, level, cfg.falloff)
    end
    sinks[#sinks + 1] = { x = cx, y = cy, live = s.state == "ok" or s.state == "short" }
    local reach = def.machine and def.machine.radius
    if reach then
      local ax, ay = Grid.coords(world.state.grid, s.anchor)
      f.markers.reach[#f.markers.reach + 1] =
        { x1 = ax - 1 - reach, y1 = ay - 1 - reach, x2 = ax + reach, y2 = ay + reach, live = s.state ~= "off" }
    end
  end
  for _, anchor in ipairs(Grid.anchorsWith(world, "battery")) do
    local cx, cy = Fields.centre(world, anchor)
    local cap = Power.capacity(world, anchor)
    banks[#banks + 1] = { x = cx, y = cy, live = true }
    local frac = cap > 0 and Power.charge(world, anchor) / cap or 0
    f.markers.gauges[#f.markers.gauges + 1] = { x = cx, y = cy, frac = frac, kind = "battery" }
  end
  -- Connections: every source feeds the nearest battery (or, with none, the nearest sink), every sink is fed by
  -- the nearest battery (or, with none, the nearest source).
  local hubs = #banks > 0 and banks or nil
  local function connect(a, b, live)
    if a and b and #f.markers.connections < cfg.maxConnections then
      f.markers.connections[#f.markers.connections + 1] = { x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y, live = live }
    end
  end
  for _, s in ipairs(sources) do
    connect(s, nearest(hubs or sinks, s), s.live)
  end
  for _, s in ipairs(sinks) do
    connect(nearest(hubs or sources, s), s, s.live)
  end
  return f
end

--- The soil lens's fields (D178): fertility on every farmable tile, with the farm's own tiles marked.
function Fields.soil(world)
  local grid = world.state.grid
  local f = blank(grid)
  for i = 1, grid.w * grid.h do
    if Grid.terrain(world, i).tillable and not world.occupancy[i] then
      f.a[i] = 1
      f.r[i] = Soil.fertility(world, i)
    end
  end
  for _, i in ipairs(Crops.fieldTiles(world)) do
    f.g[i] = 1
    f.b[i] = Soil.weeds(world, i)
  end
  return f
end

--- The water lens's fields. `preview` = { id, tile, skip } for an item being placed (or nil).
function Fields.water(world, cfg, preview)
  local grid = world.state.grid
  local f = blank(grid)
  for i = 1, grid.w * grid.h do
    f.r[i] = Land.waterTable(world, i)
  end
  local function cover(tiles, dry)
    for _, i in ipairs(tiles) do
      f.g[i] = math.min(1, f.g[i] + cfg.coverStep)
      if dry then
        f.a[i] = math.min(1, f.a[i] + cfg.coverStep)
      end
    end
  end
  for _, field in ipairs({ "drip", "sprinkler" }) do
    for _, anchor in ipairs(Grid.anchorsWith(world, field)) do
      if not (preview and preview.skip == anchor) then
        cover(Water.dripTiles(world, anchor), Water.dripState(world, anchor) == "dry")
      end
    end
  end
  if preview then
    local def = world.registry:get("objects", preview.id)
    local kind, radius = RangePreview.spec(def)
    if preview.tile and (kind == "drip" or kind == "sprinkler") then
      cover(RangePreview.square(grid, preview.tile, radius), false)
    end
    if def.placeOn == "waterTable" then
      for i = 1, grid.w * grid.h do
        if Grid.terrain(world, i).tillable and not world.occupancy[i] and Land.hasWaterTable(world, i) then
          f.b[i] = 1
        end
      end
    end
  end
  for _, anchor in ipairs(Grid.anchorsWith(world, "waterSource")) do
    local x, y, def = Fields.centre(world, anchor)
    if def.storage and def.storage.water then
      f.markers.gauges[#f.markers.gauges + 1] = { x = x, y = y, frac = Water.fraction(world), kind = "cistern" }
    end
  end
  return f
end

return Fields
