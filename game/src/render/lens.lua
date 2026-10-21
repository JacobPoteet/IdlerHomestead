-- The lens pass (GDD §9.4, D141, D145): the graded frame goes through shaders/lens.glsl into a second canvas, which
-- the homestead then uses in its place (so the frosted HUD plates look through the lens too). Connections, reach
-- rings and gauges are drawn over it in world space. Presentation only: the data comes from
-- src/render/lens_fields.lua, which reads the sim and never changes it. One full-screen pass, and only while a
-- lens is on (docs/PERF.md); the data texture is rebuilt a few times a second, not every frame.

local Dither = require("src.render.dither")
local Fields = require("src.render.lens_fields")
local Shaders = require("src.render.shaders")

local Lens = {}
Lens.__index = Lens

local MODES = { power = 1, water = 2, soil = 3 } -- shaders/lens.glsl `mode`

function Lens.new(world)
  return setmetatable({ world = world, since = math.huge, key = nil }, Lens)
end

--- Advance the rebuild timer by real seconds.
function Lens:tick(dt)
  self.since = self.since + dt
end

local function previewKey(preview)
  return preview and (preview.id .. ":" .. tostring(preview.tile) .. ":" .. tostring(preview.skip)) or ""
end

-- Rebuild the data texture when the lens or the preview changed, or the refresh time is up.
function Lens:refresh(id, preview)
  local cfg = self.world.tuning.visuals.lens
  local key = id .. "/" .. previewKey(preview)
  if key == self.key and self.since < cfg.refreshSeconds then
    return
  end
  self.key, self.since = key, 0
  local fields
  if id == "power" then
    fields = Fields.power(self.world, cfg.power)
  elseif id == "soil" then
    fields = Fields.soil(self.world)
  else
    fields = Fields.water(self.world, cfg.water, preview)
  end
  local grid = self.world.state.grid
  if not self.data or self.data:getWidth() ~= grid.w or self.data:getHeight() ~= grid.h then
    self.data = love.image.newImageData(grid.w, grid.h)
    self.image = love.graphics.newImage(self.data)
    self.image:setFilter("nearest", "nearest")
  end
  local data, w = self.data, grid.w
  for y = 0, grid.h - 1 do
    for x = 0, w - 1 do
      local i = y * w + x + 1
      data:setPixel(x, y, fields.r[i], fields.g[i], fields.b[i], fields.a[i])
    end
  end
  self.image:replacePixels(data)
  self.fields = fields
end

local function dots(conn, cfg, time, color)
  local dx, dy = conn.x2 - conn.x1, conn.y2 - conn.y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len <= 0 then
    return
  end
  local tile = cfg.tile
  local px = len * tile
  local gap = cfg.dotSpacing
  local shift = conn.live and (time * cfg.dotSpeed) % gap or 0
  local alpha = conn.live and 1 or 0.4
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  local s = shift
  while s < px do
    local f = s / px
    love.graphics.rectangle("fill", math.floor((conn.x1 + dx * f) * tile), math.floor((conn.y1 + dy * f) * tile), 1, 1)
    s = s + gap
  end
end

local function dashedRect(r, tile, dash, color)
  love.graphics.setColor(color[1], color[2], color[3], r.live and 0.9 or 0.4)
  local x1, y1, x2, y2 = r.x1 * tile, r.y1 * tile, r.x2 * tile, r.y2 * tile
  for x = x1, x2 - 1 do
    if math.floor((x - x1) / dash) % 2 == 0 then
      love.graphics.rectangle("fill", x, y1, 1, 1)
      love.graphics.rectangle("fill", x, y2 - 1, 1, 1)
    end
  end
  for y = y1, y2 - 1 do
    if math.floor((y - y1) / dash) % 2 == 0 then
      love.graphics.rectangle("fill", x1, y, 1, 1)
      love.graphics.rectangle("fill", x2 - 1, y, 1, 1)
    end
  end
end

-- A small tank: an outline, filled from the bottom in alternate pixel rows so it reads as a stipple.
local function gauge(g, tile, size, color, line)
  local w, h = size.gaugeW, size.gaugeH
  local x = math.floor(g.x * tile - w / 2)
  local y = math.floor(g.y * tile - h / 2)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
  love.graphics.setColor(line[1], line[2], line[3], 1)
  love.graphics.rectangle("line", x - 0.5, y - 0.5, w + 1, h + 1)
  local rows = math.floor(h * math.max(0, math.min(1, g.frac)) + 0.5)
  love.graphics.setColor(color[1], color[2], color[3], 1)
  for r = 0, rows - 1 do
    local ry = y + h - 1 - r
    if r == rows - 1 or r % 2 == 0 then
      love.graphics.rectangle("fill", x, ry, w, 1)
    end
  end
end

--- Run `graded` through the lens into `target` (a canvas the size of `graded`). `args` = { id, camera, view,
--- origin = { x, y } (the grade's grid origin), pixelSize, daylight, time (the effect clock, 0 when still),
--- preview }. Returns false (and leaves `target` alone) when the shader is missing.
function Lens:pass(graded, target, args)
  local shader = Shaders.get("lens")
  if not shader then
    return false
  end
  local world = self.world
  local tuning = world.tuning
  local cfg, paint, wash = tuning.visuals.lens, tuning.visuals.lens.paint, tuning.visuals.lens.wash
  self:refresh(args.id, args.preview)
  local grid, tile = world.state.grid, tuning.display.tileSize
  Shaders.send(shader, {
    dataMap = self.image,
    mapTiles = { grid.w, grid.h },
    tileSize = tile,
    gridOrigin = args.origin,
    pixelSize = args.pixelSize,
    mode = MODES[args.id] or 2,
    washTint = wash.tint,
    washKeep = wash.keepColor,
    washAmount = wash.amount,
    washDarken = wash.darken,
    dim = 1 - wash.nightDim * (1 - math.max(0, math.min(1, args.daylight))),
    alpha = paint.alpha,
    edgeAlpha = paint.edgeAlpha,
    cSource = paint.source,
    cSink = paint.sink,
    cShort = paint.short,
    cTable = paint.table,
    cCover = paint.cover,
    cDry = paint.dry,
    cSpot = paint.spot,
    cLine = paint.line,
    cRich = paint.rich,
    cPoor = paint.poor,
    cWeed = paint.weed,
    weedDensity = cfg.soil.weedDensity,
    soilMin = cfg.soil.minLevel,
    wildShare = cfg.soil.wildShare,
    soilDensity = cfg.soil.density,
    coverDensity = cfg.water.coverDensity,
    spotDensity = cfg.water.spotDensity,
    tableFloor = cfg.water.tableFloor,
  })
  Dither.send(shader, tuning, { dither = "lens" })
  love.graphics.push("all")
  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(graded, 0, 0)
  love.graphics.setShader()
  args.camera:attach(args.view)
  local markers = self.fields.markers
  local pcfg = cfg.power
  if args.id == "power" then
    local conf = { tile = tile, dotSpacing = pcfg.dotSpacing, dotSpeed = pcfg.dotSpeed }
    for _, c in ipairs(markers.connections) do
      dots(c, conf, args.time, paint.line)
    end
    for _, r in ipairs(markers.reach) do
      dashedRect(r, tile, pcfg.reachDash, paint.line)
    end
  end
  for _, g in ipairs(markers.gauges) do
    local power = g.kind == "battery"
    local size = power and pcfg or cfg.water
    gauge(g, tile, size, power and paint.store or paint.table, paint.line)
  end
  love.graphics.pop()
  love.graphics.pop()
  return true
end

return Lens
