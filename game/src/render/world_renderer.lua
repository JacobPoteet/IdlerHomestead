-- Draws the homestead from sim state (read-only). Presentation only; never changes the world.
--
-- Layers, bottom to top: static ground canvas -> water (shader) -> ford stones -> tilled soil
-- & plan markers -> y-sorted crops, objects and actors. The scene wraps this in the camera
-- transform and the post-process grade.

local Grid = require("src.sim.grid")
local Calendar = require("src.sim.systems.calendar")
local Water = require("src.sim.systems.water")
local Power = require("src.sim.systems.power")
local Processing = require("src.sim.systems.processing")
local Weather = require("src.sim.systems.weather")
local Assets = require("src.render.assets")
local Shaders = require("src.render.shaders")
local Lighting = require("src.render.lighting")

local Renderer = {}
Renderer.__index = Renderer

-- Depth-map value for a water tile `dist` tiles from the nearest bank (land = 0). With linear
-- filtering the bank line itself (halfway between a land and a first water texel) samples at
-- half the first water value; the shader draws foam just past that line.
local function waterDepth(dist)
  return math.min(1, 0.15 + 0.35 * dist)
end
local BANK_DEPTH = waterDepth(1) / 2
local FORD_DEPTH = 0.3

function Renderer.new(world)
  local self = setmetatable({
    world = world,
    tile = world.tuning.display.tileSize,
    time = 0,
  }, Renderer)
  self:buildGround()
  self:buildWater()
  return self
end

--- Status light on a powered device or generator: green running, red short, amber idle, grey off.
function Renderer:drawPowerLamp(anchor, def, x, y)
  local world, v = self.world, self.world.tuning.visuals.powerLamp
  local state
  if def.sink then
    state = Power.sinkState(world, anchor)
  elseif not Power.isEnabled(world, anchor) then
    state = "off"
  else
    state = Power.outputOf(world, anchor) > 0 and "ok" or "idle" -- a generator runs only when needed
  end
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - 1, y - 1, v.size + 2, v.size + 2)
  love.graphics.setColor(v[state])
  love.graphics.rectangle("fill", x, y, v.size, v.size)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Status light on a drip line: blue while the cistern can feed it, red when the zone is dry.
function Renderer:drawDripLamp(anchor, x, y)
  local world, v = self.world, self.world.tuning.visuals
  local size = v.powerLamp.size
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - 1, y - 1, size + 2, size + 2)
  love.graphics.setColor(v.waterLamp[Water.dripState(world, anchor)])
  love.graphics.rectangle("fill", x, y, size, size)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Level bar over a cistern: how full the shared water stock is.
function Renderer:drawCisternGauge(x, y)
  local world, g = self.world, self.world.tuning.visuals.waterGauge
  local fraction = Water.fraction(world)
  love.graphics.setColor(g.back)
  love.graphics.rectangle("fill", x - 1, y - 1, g.width + 2, g.height + 2)
  love.graphics.setColor(fraction < world.tuning.water.lowFraction and g.low or g.fill)
  love.graphics.rectangle("fill", x, y, math.floor(g.width * fraction + 0.5), g.height)
  love.graphics.setColor(1, 1, 1, 1)
end

local function variantFor(i, count)
  -- Stable per-tile variant without touching the sim RNG.
  local h = (i * 2654435761) % 4294967296
  return math.floor(h / 65536) % count + 1
end

function Renderer:buildGround()
  local grid, tile = self.world.state.grid, self.tile
  local canvas = love.graphics.newCanvas(grid.w * tile, grid.h * tile)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, grid.w * grid.h do
    local x, y = Grid.coords(grid, i)
    local terrain = grid.terrain[i]
    local id
    if terrain == "road" then
      id = "road_" .. variantFor(i, 2)
    elseif terrain == "grass" then
      id = "grass_" .. variantFor(i, 4)
    end
    if id then
      Assets.draw(id, (x - 1) * tile, (y - 1) * tile)
    end
  end
  love.graphics.pop()
  self.ground = canvas
end

function Renderer:buildWater()
  local world, grid, tile = self.world, self.world.state.grid, self.tile
  -- Depth: distance (in tiles) from each water tile to the nearest bank, via multi-source BFS.
  local dist, queue, head = {}, {}, 1
  for i = 1, grid.w * grid.h do
    if not Grid.terrain(world, i).water then
      dist[i] = 0
      queue[#queue + 1] = i
    end
  end
  while head <= #queue do
    local i = queue[head]
    head = head + 1
    local x, y = Grid.coords(grid, i)
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if Grid.inBounds(grid, nx, ny) then
          local n = Grid.index(grid, nx, ny)
          if not dist[n] then
            dist[n] = dist[i] + 1
            queue[#queue + 1] = n
          end
        end
      end
    end
  end
  local data = love.image.newImageData(grid.w, grid.h)
  local white = love.image.newImageData(1, 1)
  white:setPixel(0, 0, 1, 1, 1, 1)
  self.waterBatch = love.graphics.newSpriteBatch(love.graphics.newImage(white), grid.w * 4)
  self.fords = {}
  for i = 1, grid.w * grid.h do
    local x, y = Grid.coords(grid, i)
    local terrain = grid.terrain[i]
    local depth = 0
    if terrain == "water" then
      depth = waterDepth(dist[i])
    elseif terrain == "ford" then
      depth = FORD_DEPTH
      self.fords[#self.fords + 1] = i
    end
    data:setPixel(x - 1, y - 1, depth, depth, depth, 1)
    if Grid.terrain(world, i).water then
      self.waterBatch:add((x - 1) * tile, (y - 1) * tile, 0, tile, tile)
    end
  end
  self.depthMap = love.graphics.newImage(data)
  self.depthMap:setFilter("linear", "linear")
end

function Renderer:update(dt)
  self.time = (self.time + dt) % 3600
end

--- Lighting for the current in-game hour: tint, light, daylight. The authored keyframes are
--- stretched to the season's sunrise and sunset, then tinted for the season.
function Renderer:lighting()
  local world, v = self.world, self.world.tuning.visuals
  local now = Calendar.now(world)
  local sunrise, sunset = Calendar.daylight(world)
  local hour = Lighting.remap(now.hour, sunrise, sunset, v.lightKeysSunrise, v.lightKeysSunset)
  local tint, light, daylight = Lighting.at(hour, v.lightKeys)
  local season = v.seasonGrade[now.season].tint
  return { tint[1] * season[1], tint[2] * season[2], tint[3] * season[3] }, light, daylight
end

--- How white the ground is (0..1) and how frozen the creek is: ramps in after the freeze and
--- melts away after the thaw. Purely visual, derived from the calendar.
function Renderer:winterAmounts()
  local world, v = self.world, self.world.tuning.visuals
  local now = Calendar.now(world)
  local days = now.dayOfSeason - 1 + now.timeOfDay
  if Weather.isFrozen(world) then
    return math.min(1, days / v.snowRampDays), math.min(1, days / v.iceRampDays)
  end
  local seasons = world.tuning.time.seasons
  local previous = seasons[(now.seasonIndex - 2) % #seasons + 1]
  if now.year > 1 or now.seasonIndex > 1 then
    if Weather.isFrozenSeason(world, previous) then
      return math.max(0, 1 - days / v.snowMeltDays), math.max(0, 1 - days / v.iceRampDays)
    end
  end
  return 0, 0
end

function Renderer:drawWater(daylight, ice)
  local shader = Shaders.get("water")
  local v = self.world.tuning.visuals
  local land = self.world.state.land
  local grid = self.world.state.grid
  if shader then
    Shaders.send(shader, {
      time = self.time,
      depthMap = self.depthMap,
      mapPixels = { grid.w * self.tile, grid.h * self.tile },
      flow = { land.flowX * v.waterFlowSpeed, land.flowY * v.waterFlowSpeed },
      shallowColor = v.waterShallow,
      deepColor = v.waterDeep,
      foamColor = v.waterFoam,
      highlightColor = v.waterHighlight,
      rippleScale = v.waterRippleScale,
      sparkle = v.waterSparkle,
      foamWidth = v.waterFoamWidth,
      bankDepth = BANK_DEPTH,
      daylight = daylight,
      ice = ice,
      iceColor = v.iceColor,
      iceDeepColor = v.iceDeepColor,
    })
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(v.waterDeep) -- shader failed to compile: flat fallback
  end
  love.graphics.draw(self.waterBatch)
  love.graphics.setShader()
end

--- Puffs of smoke rising from (x, y), pixel-snapped.
function Renderer:drawSmoke(x, y)
  for n = 0, 3 do
    local t = (self.time * 0.6 + n / 4) % 1
    local px = x + math.sin((t + n) * 5) * 2 * t
    local py = y - t * 14
    love.graphics.setColor(0.85, 0.85, 0.82, 0.55 * (1 - t))
    local size = 1 + math.floor(t * 3)
    love.graphics.rectangle("fill", math.floor(px), math.floor(py), size, size)
  end
end

local function cropStage(crop)
  if crop.growth >= 1 then
    return 3
  elseif crop.growth >= 0.4 then
    return 2
  end
  return 1
end

--- Draw the world in world-pixel space. `alpha` interpolates actor movement between ticks.
--- `visible` = { x1, y1, x2, y2 } tile range to draw.
function Renderer:draw(alpha, visible, daylight)
  local world, grid, tile = self.world, self.world.state.grid, self.tile
  local x1, y1, x2, y2 = visible[1] - 1, visible[2] - 1, visible[3] + 1, visible[4] + 2
  local function onScreen(i)
    local x, y = Grid.coords(grid, i)
    return x >= x1 and x <= x2 and y >= y1 and y <= y2
  end

  local snow, ice = self:winterAmounts()
  local v = world.tuning.visuals
  local snowShader = snow > 0 and Shaders.get("snow")
  if snowShader then
    Shaders.send(snowShader, {
      amount = snow,
      snowColor = v.snowColor,
      shadeColor = v.snowShade,
      clumpScale = v.snowClumpScale,
    })
    love.graphics.setShader(snowShader)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.ground, 0, 0)
  love.graphics.setShader()
  self:drawWater(daylight, ice)
  -- Ice holes: dark open water in the frozen creek.
  love.graphics.setColor(v.iceHoleColor)
  for i in pairs(ice > 0 and world.state.weather.holes or {}) do
    if onScreen(i) then
      local x, y = Grid.coords(grid, i)
      love.graphics.ellipse("fill", (x - 0.5) * tile, (y - 0.5) * tile, 4, 3)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  for _, i in ipairs(self.fords) do
    if onScreen(i) then
      local x, y = Grid.coords(grid, i)
      Assets.draw("ford_stones", (x - 1) * tile, (y - 1) * tile)
    end
  end

  -- Fields
  local fields, crops = world.state.fields, world.state.crops
  for i in pairs(fields.tilled) do
    if onScreen(i) then
      local x, y = Grid.coords(grid, i)
      local crop = crops[i]
      local wet = crop and crop.moisture > 0
      Assets.draw(wet and "tilled_wet" or "tilled_dry", (x - 1) * tile, (y - 1) * tile)
    end
  end
  for i in pairs(fields.plan) do
    if not crops[i] and onScreen(i) then
      local x, y = Grid.coords(grid, i)
      Assets.draw("plan_marker", (x - 1) * tile, (y - 1) * tile)
    end
  end

  -- Y-sorted sprites: { sortY, draw function }
  local items = {}
  for i, crop in pairs(crops) do
    if onScreen(i) then
      local x, y = Grid.coords(grid, i)
      items[#items + 1] = {
        y * tile - 0.5,
        function()
          if crop.moisture <= 0 and crop.growth < 1 then
            love.graphics.setColor(0.86, 0.80, 0.58, 1) -- thirsty
          else
            love.graphics.setColor(1, 1, 1, 1)
          end
          Assets.draw(crop.id .. "_" .. cropStage(crop), (x - 1) * tile, (y - 1) * tile)
        end,
      }
    end
  end
  for anchor, obj in pairs(grid.objects) do
    local def = world.registry:get("objects", obj.id)
    local x, y = Grid.coords(grid, anchor)
    local fh = def.footprintH or 1
    if x + (def.footprintW or 1) >= x1 and x <= x2 and y + fh >= y1 and y <= y2 then
      local sprite = Assets.sprite(obj.id)
      local bottom = (y - 1 + fh) * tile
      local batch = def.station and Processing.batch(world, anchor)
      local smoking = batch and world.registry:get("recipes", batch.recipe).fuel ~= nil
      items[#items + 1] = {
        bottom,
        function()
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(sprite.image, sprite.quad, (x - 1) * tile, bottom - sprite.h)
          if smoking then
            self:drawSmoke((x - 1) * tile + 8, bottom - sprite.h + 2)
          end
          if def.sink or (def.source and def.source.curve == "fuel") then
            self:drawPowerLamp(anchor, def, (x - 1) * tile + sprite.w - 4, bottom - sprite.h + 1)
          end
          if def.drip then
            self:drawDripLamp(anchor, (x - 1) * tile + sprite.w - 4, bottom - sprite.h + 1)
          end
          if def.waterSource and def.waterSource.stored then
            self:drawCisternGauge((x - 1) * tile + 2, bottom - sprite.h + 1)
          end
        end,
      }
    end
  end
  for _, actor in ipairs(world.state.actors) do
    local ax = actor.prevX + (actor.x - actor.prevX) * alpha
    local ay = actor.prevY + (actor.y - actor.prevY) * alpha
    local feetX, feetY = (ax - 0.5) * tile, (ay - 0.5) * tile + 6
    items[#items + 1] = {
      feetY,
      function()
        if actor.asleep then
          self:drawSleep(feetX, feetY - 10)
          return
        end
        local sprite = Assets.sprite(actor.kind)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sprite.image, sprite.quad, math.floor(feetX - sprite.w / 2 + 0.5), math.floor(feetY - sprite.h + 0.5))
        if actor.bucket and actor.bucket > 0 then
          -- Tiny water gauge beside the homesteader while carrying water.
          local frac = math.min(1, actor.bucket / Water.bucketCapacity(world))
          local gx, gy = math.floor(feetX + 6), math.floor(feetY - 12)
          love.graphics.setColor(0.1, 0.1, 0.1, 0.7)
          love.graphics.rectangle("fill", gx, gy, 3, 8)
          love.graphics.setColor(0.45, 0.72, 0.92, 1)
          local fill = math.max(1, math.floor(6 * frac + 0.5))
          love.graphics.rectangle("fill", gx + 1, gy + 7 - fill, 1, fill)
        end
      end,
    }
  end
  table.sort(items, function(a, b)
    return a[1] < b[1]
  end)
  for _, item in ipairs(items) do
    item[2]()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- A tiny pixel "z" (4x4).
local function pixelZ(x, y)
  love.graphics.rectangle("fill", x, y, 4, 1)
  love.graphics.rectangle("fill", x + 2, y + 1, 1, 1)
  love.graphics.rectangle("fill", x + 1, y + 2, 1, 1)
  love.graphics.rectangle("fill", x, y + 3, 4, 1)
end

--- Rising z's where the homesteader sleeps (inside the shelter, so no sprite).
function Renderer:drawSleep(x, y)
  for n = 0, 1 do
    local t = (self.time * 0.5 + n * 0.5) % 1
    love.graphics.setColor(0.92, 0.92, 1, 1 - t)
    pixelZ(math.floor(x + n * 3 + t * 4), math.floor(y - t * 10))
  end
end

--- Apply the colour grade while drawing `canvas` (the rendered world) to the screen.
function Renderer:drawGraded(canvas, tint, light, pixelSize)
  local v = self.world.tuning.visuals
  local shader = Shaders.get("grade")
  if shader then
    Shaders.send(shader, {
      tint = tint,
      light = light,
      saturation = v.saturation * v.seasonGrade[Calendar.now(self.world).season].saturation,
      vignette = v.vignette,
      grain = v.grain,
      time = self.time,
      pixelSize = pixelSize,
    })
    love.graphics.setShader(shader)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  love.graphics.setShader()
end

return Renderer
