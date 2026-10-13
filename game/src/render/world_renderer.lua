-- Draws the homestead from sim state (read-only). Presentation only; never changes the world.
--
-- Layers, bottom to top: static ground canvas -> water (shader) -> ford stones -> tilled soil
-- & plan markers -> y-sorted crops, objects and actors. The scene wraps this in the camera
-- transform and the post-process grade.

local Grid = require("src.sim.grid")
local Animals = require("src.sim.systems.animals")
local Calendar = require("src.sim.systems.calendar")
local Cat = require("src.sim.systems.cat")
local Crops = require("src.sim.systems.crops")
local Machines = require("src.sim.systems.machines")
local Market = require("src.sim.systems.market")
local TripMarker = require("src.render.trip_marker")
local CropCues = require("src.render.crop_cues")
local Water = require("src.sim.systems.water")
local Power = require("src.sim.systems.power")
local Processing = require("src.sim.systems.processing")
local Weather = require("src.sim.systems.weather")
local Assets = require("src.render.assets")
local Shaders = require("src.render.shaders")
local Lighting = require("src.render.lighting")
local WeatherFx = require("src.render.weather_fx")
local Lights = require("src.render.lights")
local EffectClock = require("src.render.effect_clock")
local Ambient = require("src.render.ambient")
local Settings = require("src.core.settings")

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
local MAX_REACH = 31 -- tiles: the farthest distance from the creek the mist map stores (the shader scales it)

function Renderer.new(world)
  local self = setmetatable({
    world = world,
    tile = world.tuning.display.tileSize,
    time = 0, -- effect clock, game time (D97)
    uiTime = 0, -- effect clock, real time
    clock = EffectClock.new(world.tuning.visuals.effectClock),
    fx = WeatherFx.new(world),
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

--- A machine's status light (working, slow, unpowered, full, idle, off) and, while it works, its arm
--- reaching to the target tile (D65). (tx, ty) is the machine's tile; (lx, ly) the light's spot.
function Renderer:drawMachine(anchor, tx, ty, lx, ly)
  local world, v = self.world, self.world.tuning.visuals
  local unit = Machines.at(world, anchor)
  local status = unit and unit.status or "idle"
  if unit and unit.job then
    local tile = self.tile
    local gx, gy = Grid.coords(world.state.grid, unit.job.target)
    local sprite = Assets.sprite(unit.kind)
    local grip = v.machine.grip -- the gripper's pixel on the sprite, from its top-left
    local sx, sy = (tx - 1) * tile + grip[1], ty * tile - sprite.h + grip[2]
    local wobble = math.sin(self.time * v.machine.armWobbleSpeed) * v.machine.armWobble
    love.graphics.setColor(v.machine.arm)
    love.graphics.setLineWidth(v.machine.armWidth)
    love.graphics.line(sx, sy, (gx - 0.5) * tile, (gy - 0.5) * tile + wobble)
  end
  local size = v.powerLamp.size
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", lx - 1, ly - 1, size + 2, size + 2)
  love.graphics.setColor(v.machine.lamp[status])
  love.graphics.rectangle("fill", lx, ly, size, size)
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
  -- Reach of the morning mist: 1 on the creek, falling to 0 `mist.reach` tiles inland (BFS from the water over land).
  local reach, inland, qhead = {}, {}, 1
  for i = 1, grid.w * grid.h do
    if Grid.terrain(world, i).water then
      reach[i] = 0
      inland[#inland + 1] = i
    end
  end
  while qhead <= #inland do
    local i = inland[qhead]
    qhead = qhead + 1
    local x, y = Grid.coords(grid, i)
    for dy = -1, 1 do
      for dx = -1, 1 do
        if Grid.inBounds(grid, x + dx, y + dy) then
          local n = Grid.index(grid, x + dx, y + dy)
          if not reach[n] then
            reach[n] = reach[i] + 1
            inland[#inland + 1] = n
          end
        end
      end
    end
  end
  self.reach = reach -- tiles from the creek per tile, kept for the fireflies and dust (render/ambient.lua)
  local mistData = love.image.newImageData(grid.w, grid.h)
  for i = 1, grid.w * grid.h do
    local x, y = Grid.coords(grid, i)
    local near = math.min(reach[i] or MAX_REACH, MAX_REACH) / MAX_REACH -- tiles from the creek, 0 = on it (mist.reach is applied in the shader, so F6 can retune it)
    mistData:setPixel(x - 1, y - 1, near, near, near, 1)
  end
  self.reachMap = love.graphics.newImage(mistData)
  self.reachMap:setFilter("linear", "linear")

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

--- Falling rain over the graded world (call after drawGraded; `view` is the virtual screen).
function Renderer:drawRain(view, grid)
  if not Settings.read("ambientFx", true) then
    return
  end
  self.fx:drawRain(view, grid)
end

--- `speed` = the session's effective game speed (0 paused, held by a tip card or in town; nil = 1).
--- World effects run on `self.time` (game time, capped, D97); UI pulses on `self.uiTime` (real time).
function Renderer:update(dt, speed)
  self.clock.cfg = self.world.tuning.visuals.effectClock -- F6 swaps the tuning tables
  local step = self.clock:advance(dt, speed)
  self.time, self.uiTime = self.clock.world, self.clock.real
  self.fx:update(dt, step)
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
  local sky, skyLight = self.fx:grade() -- cloud and rain darken and cool the scene
  return {
    tint[1] * season[1] * sky[1],
    tint[2] * season[2] * sky[2],
    tint[3] * season[3] * sky[3],
  },
    light * skyLight,
    daylight
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
      rain = (self.fx:rainAndWet()),
      rainCell = v.weather.waterRain.cell,
      rainSeconds = v.weather.waterRain.seconds,
      rainRadius = v.weather.waterRain.radius,
      rainDensity = v.weather.waterRain.density,
      rainAlpha = v.weather.waterRain.alpha,
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
  local _, wet = self.fx:rainAndWet()
  local frost = ice -- the creek's freeze brings the frost in from its banks, and it melts away with the ice
  local groundShader = (snow > 0 or wet > 0 or frost > 0) and Shaders.get("ground")
  if groundShader then
    local w = v.weather.wet
    Shaders.send(groundShader, {
      amount = snow,
      snowColor = v.snowColor,
      shadeColor = v.snowShade,
      clumpScale = v.snowClumpScale,
      patchScale = v.snowPatchScale,
      wet = wet,
      wetDarken = w.darken,
      wetSaturation = w.saturation,
      puddleCover = w.puddleCover,
      puddleScale = w.puddleScale,
      puddleOpacity = w.puddleOpacity,
      puddleColor = w.puddleColor,
      puddleGlint = w.puddleGlint,
      frost = frost,
      frostReach = v.frostReach,
      frostColor = v.frostColor,
      groundSize = { self.ground:getWidth(), self.ground:getHeight() },
    })
    love.graphics.setShader(groundShader)
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
  local risky = {} -- crop id -> would a crop planted today be caught by the frost? (one answer per crop per frame)
  for i, cropId in pairs(fields.plan) do
    if not crops[i] and onScreen(i) then
      local x, y = Grid.coords(grid, i)
      if CropCues.planState(cropId, fields.tilled[i], crops[i]) then
        -- A faint sprout says what is planned; a planted crop is solid, so a plan never passes for a plant (D102).
        local ghost = Assets.sprite(cropId .. "_1")
        love.graphics.setColor(1, 1, 1, v.cropCues.planGhostAlpha)
        love.graphics.draw(ghost.image, ghost.quad, (x - 1) * tile, y * tile - ghost.h)
        love.graphics.setColor(1, 1, 1, 1)
      end
      Assets.draw("plan_marker", (x - 1) * tile, (y - 1) * tile)
      if risky[cropId] == nil then
        risky[cropId] = Crops.frostRisk(world, cropId) ~= nil
      end
      if risky[cropId] then
        love.graphics.setColor(world.tuning.visuals.frostPlan)
        love.graphics.rectangle("fill", (x - 1) * tile, (y - 1) * tile, tile, tile)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- Snow resting on top of objects while the ground is white.
  local capShader = snow > 0 and Shaders.get("snowcap") or nil
  if capShader then
    Shaders.send(capShader, {
      amount = snow,
      capDepth = v.snowCapDepth,
      snowColor = v.snowColor,
      shadeColor = v.snowShade,
    })
  end

  -- Wind sway (sway.glsl): crops, brush and tree canopies lean with the weather's wind.
  local sway = self:swayShader()

  -- Y-sorted sprites: { sortY, draw function }
  -- Mist is a low layer: it hazes the ground and the creek but sits under crops, objects and tree canopies (#219).
  self:drawMist(visible, ice)
  local items = {}
  for i, crop in pairs(crops) do
    if onScreen(i) then
      local x, y = Grid.coords(grid, i)
      items[#items + 1] = {
        y * tile - 0.5,
        function()
          local thirsty = crop.moisture <= 0 and crop.growth < 1
          local sprite = Assets.sprite(crop.id .. "_" .. cropStage(crop))
          if sway then
            self:drawSwaying(sway, sprite, (x - 1) * tile, y * tile - sprite.h, v.wind.crop, self:swayPhase(x, y), thirsty)
            return
          end
          if thirsty then
            love.graphics.setColor(0.86, 0.80, 0.58, 1) -- thirsty
          else
            love.graphics.setColor(1, 1, 1, 1)
          end
          love.graphics.draw(sprite.image, sprite.quad, (x - 1) * tile, y * tile - sprite.h)
        end,
      }
    end
  end
  local defs, registry = {}, world.registry -- id -> definition, looked up once per frame
  for anchor, obj in pairs(grid.objects) do
    local def = defs[obj.id]
    if not def then
      def = registry:get("objects", obj.id)
      defs[obj.id] = def
    end
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
          if capShader then
            self:capSprite(capShader, sprite)
          end
          if def.sway and sway and not capShader then
            self:drawSwaying(sway, sprite, (x - 1) * tile, bottom - sprite.h, def.sway, self:swayPhase(x, y), false)
          else
            love.graphics.draw(sprite.image, sprite.quad, (x - 1) * tile, bottom - sprite.h)
          end
          if capShader then
            love.graphics.setShader()
          end
          if obj.id == "truck" and TripMarker.visible(Market.canTrip(world), world.state.market.inTown) then
            local cfg = world.tuning.visuals.tripMarker
            local arrow = Assets.sprite("trip_marker")
            local dy = TripMarker.offset(self.uiTime, cfg, Settings.read("reduceMotion", false))
            love.graphics.draw(
              arrow.image,
              arrow.quad,
              (x - 1) * tile + sprite.w - 18, -- over the cab
              bottom - sprite.h - arrow.h - cfg.gap + dy
            )
          end
          if smoking then
            self:drawSmoke((x - 1) * tile + 8, bottom - sprite.h + 2)
          end
          if def.machine then
            self:drawMachine(anchor, x, y, (x - 1) * tile + sprite.w - 4, bottom - sprite.h + 1)
          elseif def.sink or (def.source and def.source.curve == "fuel") then
            self:drawPowerLamp(anchor, def, (x - 1) * tile + sprite.w - 4, bottom - sprite.h + 1)
          end
          if def.drip then
            self:drawDripLamp(anchor, (x - 1) * tile + sprite.w - 4, bottom - sprite.h + 1)
          end
          if def.waterSource and def.waterSource.stored then
            self:drawCisternGauge((x - 1) * tile + 2, bottom - sprite.h + 1)
          end
          if def.pen and Animals.pail(world) > 0 then
            -- Milk waiting in the pail shows as white dots by the shed door.
            love.graphics.setColor(world.tuning.visuals.goats.milkMarker)
            for n = 0, math.min(2, Animals.pail(world) - 1) do
              love.graphics.rectangle("fill", (x - 1) * tile + 3 + n * 3, bottom - sprite.h + 12, 2, 3)
            end
          end
          if def.coop and Animals.nest(world) > 0 then
            -- Eggs waiting in the nest box show as cream dots on its side.
            love.graphics.setColor(world.tuning.visuals.hens.eggMarker)
            for n = 0, math.min(1, Animals.nest(world) - 1) do
              love.graphics.rectangle("fill", (x - 1) * tile + sprite.w - 5 + n * 2, bottom - sprite.h + 13, 2, 2)
            end
          end
        end,
      }
    end
  end
  self:addHens(items, x1, x2, y1, y2)
  self:addGoats(items, x1, x2, y1, y2)
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
  local cx, cy, cpx, cpy, cmode = Cat.position(world)
  if cx then
    local feetX = (cpx + (cx - cpx) * alpha - 0.5) * tile
    local feetY = (cpy + (cy - cpy) * alpha - 0.5) * tile + 6
    items[#items + 1] = {
      feetY,
      function()
        local resting = cmode == "nap" or cmode == "sleep"
        local sprite = Assets.sprite(resting and "cat_nap" or "cat")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sprite.image, sprite.quad, math.floor(feetX - sprite.w / 2 + 0.5), math.floor(feetY - sprite.h + 0.5))
        if cmode == "sleep" then
          self:drawSleep(feetX, feetY - 8)
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
  self:drawCloudShadows(visible, daylight)
end

--- The sway shader with this frame's wind sent, or nil when it is unavailable.
function Renderer:swayShader()
  local shader = Shaders.get("sway")
  if not shader then
    return nil
  end
  local cfg = self.world.tuning.visuals.wind
  local clock, wind = self.fx:windSway()
  Shaders.send(shader, {
    swayTime = clock,
    amplitude = Settings.read("reduceMotion", false) and 0 or cfg.amplitude * wind, -- reduce motion stills the sway (D96)
    lean = cfg.lean,
    gust = cfg.gust,
    thirsty = cfg.thirsty,
  })
  self.swayLast = nil -- the per-sprite uniforms (bounds, weight) are sent again when the sprite changes
  return shader
end

--- A plant's sway phase 0..1 (the shader's vertex colour): the tile's place in the gust that rolls across
--- the land, plus a little per-tile jitter so neighbours are not in lockstep.
function Renderer:swayPhase(x, y)
  local cfg = self.world.tuning.visuals.wind
  local jitter = variantFor(y * 1024 + x, 64) / 64
  return ((x * cfg.spread + y * cfg.spread * 0.37) / (2 * math.pi) + jitter * 0.15) % 1
end

--- Draw `sprite` swaying in the wind with its top-left at (x, y). `cfg` = { weight, root }. The sprite is
--- drawn on a quad padded each side by the most it can lean, so the tip is not clipped by its atlas cell.
function Renderer:drawSwaying(shader, sprite, x, y, cfg, phase, thirsty)
  local pad = self.swayPad
  if not pad then
    local w = self.world.tuning.visuals.wind
    pad = math.ceil(w.amplitude * 1.2 * (1 + w.gust) * 1.7) + 1 -- widest weight x peak wave x a gale
    self.swayPad = pad
  end
  if sprite.swayPad ~= pad then
    local iw, ih = sprite.image:getDimensions()
    local qx, qy, qw, qh = sprite.quad:getViewport()
    sprite.swayQuad = love.graphics.newQuad(qx - pad, qy, qw + 2 * pad, qh, iw, ih)
    sprite.swayCell = { { qx / iw, qy / ih, (qx + qw) / iw, (qy + qh) / ih }, { 1 / iw, 1 / ih } }
    sprite.swayPad = pad
  end
  if self.swayLast ~= sprite or self.swayLastCfg ~= cfg then
    shader:send("bounds", sprite.swayCell[1])
    shader:send("texel", sprite.swayCell[2])
    shader:send("spriteH", sprite.h)
    shader:send("weight", cfg.weight)
    shader:send("root", cfg.root)
    self.swayLast, self.swayLastCfg = sprite, cfg
  end
  love.graphics.setShader(shader)
  love.graphics.setColor(phase, thirsty and 1 or 0, 0, 1)
  love.graphics.draw(sprite.image, sprite.swayQuad, x - pad, y)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
end

--- Morning mist over the creek and low ground: how strong it is right now (0..1). It forms before
--- sunrise, holds a little, and burns off by mid-morning; calm and damp mornings have the most, wind
--- blows it away, and a frozen creek holds less.
function Renderer:mistStrength(ice)
  local world = self.world
  local cfg = world.tuning.visuals.mist
  local sunrise = Calendar.daylight(world)
  local hour = Calendar.now(world).hour
  local rise = math.min(1, math.max(0, (hour - (sunrise - cfg.preHours)) / cfg.preHours))
  local burn = math.min(1, math.max(0, (hour - (sunrise + cfg.holdHours)) / cfg.fadeHours))
  local time = (rise * rise * (3 - 2 * rise)) * (1 - burn * burn * (3 - 2 * burn))
  if time <= 0 then
    return 0
  end
  local _, wet = self.fx:rainAndWet()
  local _, wind = self.fx:windSway()
  local calm = 1 - math.min(1, math.max(0, (wind - cfg.calmUntil) / (cfg.windKill - cfg.calmUntil)))
  local damp = cfg.dryLevel + (1 - cfg.dryLevel) * wet
  return time * calm * damp * (1 - (1 - cfg.frozen) * ice)
end

--- Draw the morning mist as one translucent quad over the visible land (world-anchored, mist.glsl).
function Renderer:drawMist(visible, ice)
  local shader = Shaders.get("mist")
  local cfg = self.world.tuning.visuals.mist
  local strength = self:mistStrength(ice)
  if not shader or strength <= 0.01 or not Settings.read("ambientFx", true) then
    return
  end
  local grid, tile = self.world.state.grid, self.tile
  local x1, y1 = math.max(1, visible[1] - 1), math.max(1, visible[2] - 1)
  local x2, y2 = math.min(grid.w, visible[3] + 1), math.min(grid.h, visible[4] + 2)
  local rx, ry, rw, rh = (x1 - 1) * tile, (y1 - 1) * tile, (x2 - x1 + 1) * tile, (y2 - y1 + 1) * tile
  Shaders.send(shader, {
    reachMap = self.reachMap,
    reachTiles = cfg.reach,
    mapPixels = { grid.w * tile, grid.h * tile },
    rect = { rx, ry, rw, rh },
    offset = self.fx:mistOffset(),
    strength = strength,
    ground = cfg.ground,
    scale = cfg.scale,
    block = cfg.block,
    levels = cfg.levels,
    maxAlpha = cfg.alpha,
    mistColor = cfg.color,
  })
  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self:whiteImage(), rx, ry, 0, rw, rh)
  love.graphics.setShader()
end

--- Night lights, additive over the GRADED world (call with the camera transform on, after drawGraded).
--- Which objects glow is the `light` field of their definition and whether it is on is read from the sim
--- (Lights.visible); here we only paint. Returns how many lights were drawn (for the perf notes).
function Renderer:drawLights(visible, daylight)
  local world, tile = self.world, self.tile
  local cfg = world.tuning.visuals.lights
  local dark = math.min(1, math.max(0, (cfg.fadeStart - daylight) / (cfg.fadeStart - cfg.fadeEnd)))
  if dark <= 0.001 then
    return 0
  end
  local shader = Shaders.get("light")
  local lit = Lights.visible(world, visible, cfg.margin)
  if #lit == 0 then
    return 0
  end
  love.graphics.setBlendMode("add")
  local step = math.floor(self.time * cfg.flickerSpeed)
  for n, item in ipairs(lit) do
    local light = item.light
    local sprite = Assets.sprite(item.id)
    local left, top = (item.tileX - 1) * tile, item.bottom - sprite.h
    local flick = 1 + light.flicker * (variantFor(step * 31 + n * 7 + item.anchor, 64) / 63 * 2 - 1)
    local radius = math.floor(light.radius * flick + 0.5) -- whole art pixels, so the pool steps rather than shimmers
    local cx, cy = left + light.at[1], top + light.at[2]
    if shader then
      local c = light.color
      Shaders.send(shader, {
        rect = { cx - radius, cy - radius * 0.8, radius * 2, radius * 1.6 },
        center = { cx, cy },
        radius = radius,
        lightColor = { c[1] * cfg.intensity * dark, c[2] * cfg.intensity * dark, c[3] * cfg.intensity * dark },
        bands = cfg.bands,
        falloff = cfg.falloff,
        dither = cfg.dither,
      })
      love.graphics.setShader(shader)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self:whiteImage(), cx - radius, cy - radius * 0.8, 0, radius * 2, radius * 1.6)
      love.graphics.setShader()
    end
    if light.windows then
      local c, g = light.color, cfg.windowGlow * dark
      love.graphics.setColor(c[1] * g, c[2] * g, c[3] * g, 1)
      for _, w in ipairs(light.windows) do
        love.graphics.rectangle("fill", left + w[1], top + w[2], w[3], w[4])
      end
    end
  end
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  return #lit
end

--- Switch to the snow-cap shader for one sprite: tell it where the sprite's cell sits in its atlas, so
--- the cap never reads a neighbouring sprite as "the pixel above".
function Renderer:capSprite(shader, sprite)
  local cell = sprite.capCell
  if not cell then
    local iw, ih = sprite.image:getDimensions()
    local qx, qy, qw, qh = sprite.quad:getViewport()
    cell = { { qx / iw, qy / ih, (qx + qw) / iw, (qy + qh) / ih }, { 1 / iw, 1 / ih } }
    sprite.capCell = cell
  end
  shader:send("bounds", cell[1])
  shader:send("texel", cell[2])
  love.graphics.setShader(shader)
end

--- Soft cloud shadows drifting over the visible land (world-anchored; weather_fx supplies the cover and
--- the drift). One translucent quad over the visible tiles, shaded by clouds.glsl.
function Renderer:drawCloudShadows(visible, daylight)
  local shader = Shaders.get("clouds")
  local cfg = self.world.tuning.visuals.weather.clouds
  local strength = cfg.strength * daylight
  if not shader or strength <= 0.001 or not Settings.read("ambientFx", true) then
    return
  end
  local grid, tile = self.world.state.grid, self.tile
  local x1, y1 = math.max(1, visible[1] - 1), math.max(1, visible[2] - 1)
  local x2, y2 = math.min(grid.w, visible[3] + 1), math.min(grid.h, visible[4] + 2)
  local rx, ry, rw, rh = (x1 - 1) * tile, (y1 - 1) * tile, (x2 - x1 + 1) * tile, (y2 - y1 + 1) * tile
  local cover, drift = self.fx:clouds()
  Shaders.send(shader, {
    rect = { rx, ry, rw, rh },
    offset = drift,
    coverage = cover,
    strength = strength,
    scale = cfg.scale,
    block = cfg.block,
    shadowColor = cfg.color,
  })
  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self:whiteImage(), rx, ry, 0, rw, rh)
  love.graphics.setShader()
end

--- A 1x1 white image, scaled up as a flat quad for the full-area effects.
function Renderer:whiteImage()
  if not self.white then
    local data = love.image.newImageData(1, 1)
    data:setPixel(0, 0, 1, 1, 1, 1)
    self.white = love.graphics.newImage(data)
  end
  return self.white
end

--- Queue the flock for the y-sorted pass. Hens roam the run in front of each coop by day (they roost
--- inside at night and in a storm); their drift is a pure function of the render clock and their
--- number, so drawing never touches the sim.
function Renderer:addHens(items, x1, x2, y1, y2)
  local world, tile = self.world, self.tile
  local cfg = world.tuning.visuals.hens
  local hens = math.min(Animals.hens(world), cfg.maxDrawn)
  if hens == 0 or Calendar.isNight(world) or Weather.kind(world) == "storm" then
    return
  end
  local grid = world.state.grid
  local anchors = Grid.anchorsWith(world, "coop")
  for _, anchor in ipairs(anchors) do
    local ax, ay = Grid.coords(grid, anchor)
    local def = world.registry:get("objects", grid.objects[anchor].id)
    local fw, fh = def.footprintW or 1, def.footprintH or 1
    if ax + fw >= x1 and ax <= x2 and ay + fh + 2 >= y1 and ay <= y2 then
      for n = 1, hens do
        local phase = n * 2.399 -- golden-angle spacing, so hens never move in step
        local sway = math.sin(self.time * cfg.speed + phase)
        local depth = 0.5 + 0.5 * math.sin(self.time * cfg.speed * 0.77 + phase * 1.3)
        local feetX = (ax - 1 + fw / 2 + sway * cfg.wander) * tile
        local feetY = (ay - 1 + fh + 0.4 + depth * cfg.runDepth) * tile
        local facing = math.cos(self.time * cfg.speed + phase) >= 0 and 1 or -1
        local pecking = math.sin(self.time * cfg.peckSpeed + phase * 3) > cfg.peckAbove
        items[#items + 1] = {
          feetY,
          function()
            local sprite = Assets.sprite("hen")
            love.graphics.setColor(1, 1, 1, 1)
            local dy = pecking and 1 or 0
            local x = math.floor(feetX + 0.5)
            local y = math.floor(feetY - sprite.h + 0.5) + dy
            if facing > 0 then
              love.graphics.draw(sprite.image, sprite.quad, x - math.floor(sprite.w / 2), y)
            else
              love.graphics.draw(sprite.image, sprite.quad, x + math.floor(sprite.w / 2), y, 0, -1, 1)
            end
          end,
        }
      end
    end
  end
end

--- Queue the herd for the y-sorted pass. Goats browse the yard of each pen by day (they stay in the
--- shed at night and in a storm); like the hens, their drift is a pure function of the render clock.
function Renderer:addGoats(items, x1, x2, y1, y2)
  local world, tile = self.world, self.tile
  local cfg = world.tuning.visuals.goats
  local goats = math.min(Animals.goats(world), cfg.maxDrawn)
  if goats == 0 or Calendar.isNight(world) or Weather.kind(world) == "storm" then
    return
  end
  local grid = world.state.grid
  for _, anchor in ipairs(Grid.anchorsWith(world, "pen")) do
    local ax, ay = Grid.coords(grid, anchor)
    local def = world.registry:get("objects", grid.objects[anchor].id)
    local fw, fh = def.footprintW or 1, def.footprintH or 1
    if ax + fw >= x1 and ax <= x2 and ay + fh >= y1 and ay <= y2 then
      for n = 1, goats do
        local phase = n * 2.399
        local sway = math.sin(self.time * cfg.speed + phase)
        local depth = 0.5 + 0.5 * math.sin(self.time * cfg.speed * 0.77 + phase * 1.3)
        local feetX = (ax - 1 + fw / 2 + sway * cfg.wander) * tile
        local feetY = (ay - 1 + fh - cfg.yardDepth + depth * cfg.yardDepth * 0.8) * tile
        local facing = math.cos(self.time * cfg.speed + phase) >= 0 and 1 or -1
        local grazing = math.sin(self.time * cfg.grazeSpeed + phase * 3) > cfg.grazeAbove
        items[#items + 1] = {
          (ay - 1 + fh) * tile + 0.5 + depth, -- sorted just in front of the pen, so the herd shows inside the fence
          function()
            local sprite = Assets.sprite("goat")
            love.graphics.setColor(1, 1, 1, 1)
            local dy = grazing and 1 or 0
            local x = math.floor(feetX + 0.5)
            local y = math.floor(feetY - sprite.h + 0.5) + dy
            if facing > 0 then
              love.graphics.draw(sprite.image, sprite.quad, x - math.floor(sprite.w / 2), y)
            else
              love.graphics.draw(sprite.image, sprite.quad, x + math.floor(sprite.w / 2), y, 0, -1, 1)
            end
          end,
        }
      end
    end
  end
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

--- Heat shimmer inputs for the grade pass: how hot the day is (hot clear summer noon) and the lit fires
--- (stove, campfire) in view as shimmer columns, all in canvas pixels. nil when there is nothing to show.
function Renderer:heatHaze(camera, view, visible, daylight)
  local world, tile = self.world, self.tile
  local cfg = world.tuning.visuals.heat
  local snow = self:winterAmounts()
  local amount = Ambient.heatAmount(world, daylight, snow)
  local s = view.scale * camera:zoom()
  local ox = math.floor(view.w * view.scale / 2 - camera.x * s + 0.5)
  local oy = math.floor(view.h * view.scale / 2 - camera.y * s + 0.5)
  local sources = {}
  for _, item in ipairs(Lights.visible(world, visible, 1)) do
    if item.light.on == "heat" and #sources < cfg.maxSources then
      local sprite = Assets.sprite(item.id)
      local wx = (item.tileX - 1) * tile + item.light.at[1]
      local wy = item.bottom - sprite.h + item.light.at[2] - 4
      -- x, y: the base of the column in canvas pixels; z: half-width, w: height, both in art pixels.
      sources[#sources + 1] = { ox + wx * s, oy + wy * s, cfg.sourceWidth, cfg.sourceHeight }
    end
  end
  if amount <= 0.01 and #sources == 0 then
    return nil
  end
  return {
    amount = amount,
    sources = sources,
    origin = { ox, oy },
    world = { math.floor(camera.x - view.w / 2 / camera:zoom()), math.floor(camera.y - view.h / 2 / camera:zoom()) },
  }
end

--- Outline round the selected object (its whole footprint) or tile, drawn on the art-pixel grid over the
--- graded world, with the camera transform on. `pixelSize` = physical pixels per art pixel.
function Renderer:drawSelection(i, pixelSize)
  local world, grid, tile = self.world, self.world.state.grid, self.tile
  local cfg = world.tuning.visuals.selection
  local def, anchor = Grid.object(world, i)
  local tiles = { i }
  if def then
    local ax, ay = Grid.coords(grid, anchor)
    tiles = Grid.footprintTiles(grid, def, ax, ay) or tiles
  end
  local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
  for _, t in ipairs(tiles) do
    local x, y = Grid.coords(grid, t)
    minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y)
  end
  local l, t, r, b = (minX - 1) * tile, (minY - 1) * tile, maxX * tile, maxY * tile
  local th = math.max(cfg.thickness, math.ceil(cfg.minScreen / pixelSize))
  local breath = 0.5 + 0.5 * math.sin(self.uiTime / cfg.pulseSeconds * 2 * math.pi) -- UI: real time on purpose (D97)
  local alpha = 1 - cfg.pulseDepth * breath

  local function ring(rl, rt, rr, rb, w, color, a)
    love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * a)
    love.graphics.rectangle("fill", rl, rt, rr - rl, w)
    love.graphics.rectangle("fill", rl, rb - w, rr - rl, w)
    love.graphics.rectangle("fill", rl, rt + w, w, rb - rt - 2 * w)
    love.graphics.rectangle("fill", rr - w, rt + w, w, rb - rt - 2 * w)
  end
  ring(l - th, t - th, r + th, b + th, th, cfg.shadow, 1)
  ring(l, t, r, b, th, cfg.color, alpha)
  -- Corner brackets: an extra pixel of thickness and a brighter colour along the first few pixels of each edge.
  local cl, cw = math.min(cfg.cornerLength + th, math.floor((r - l) / 2)), th + 1
  local cc = cfg.cornerColor
  love.graphics.setColor(cc[1], cc[2], cc[3], 1)
  for _, corner in ipairs({ { l, t, 1, 1 }, { r, t, -1, 1 }, { l, b, 1, -1 }, { r, b, -1, -1 } }) do
    local cx, cy, sx, sy = corner[1], corner[2], corner[3], corner[4]
    love.graphics.rectangle("fill", sx > 0 and cx or cx - cl, sy > 0 and cy or cy - cw, cl, cw)
    love.graphics.rectangle("fill", sx > 0 and cx or cx - cw, sy > 0 and cy or cy - cl, cw, cl)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Crop cues over the graded world (world space, camera transform on; D102): a lift that keeps crop
--- sprites readable on the dark soil at night, a droplet over a thirsty crop and a sparkle over a ripe one.
--- UI cues on the real-time clock (like the selection ring, D97); reduce motion holds the sparkle still.
function Renderer:drawCropCues(visible, daylight)
  local world, grid, tile = self.world, self.world.state.grid, self.tile
  local cfg = world.tuning.visuals.cropCues
  local lift = CropCues.nightLift(daylight, cfg)
  local alpha = CropCues.iconAlpha(daylight, cfg)
  local reduce = Settings.read("reduceMotion", false)
  local x1, y1, x2, y2 = visible[1] - 1, visible[2] - 1, visible[3] + 1, visible[4] + 2
  if lift > 0.001 then -- planned tiles get the same lift, so a standing order still shows at night
    local frame = Assets.sprite("plan_marker")
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setColor(1, 1, 1, lift)
    for i in pairs(world.state.fields.plan) do
      local x, y = Grid.coords(grid, i)
      if not world.state.crops[i] and x >= x1 and x <= x2 and y >= y1 and y <= y2 then
        love.graphics.draw(frame.image, frame.quad, (x - 1) * tile, (y - 1) * tile)
      end
    end
    love.graphics.setBlendMode("alpha")
  end
  for i, crop in pairs(world.state.crops) do
    local x, y = Grid.coords(grid, i)
    if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
      local left, top = (x - 1) * tile, (y - 1) * tile
      if lift > 0.001 then
        local sprite = Assets.sprite(crop.id .. "_" .. cropStage(crop))
        love.graphics.setBlendMode("add", "alphamultiply")
        love.graphics.setColor(1, 1, 1, lift)
        love.graphics.draw(sprite.image, sprite.quad, left, y * tile - sprite.h)
        love.graphics.setBlendMode("alpha")
      end
      local cue = CropCues.cue(crop)
      if cue == "thirsty" then
        local drop = Assets.sprite("cue_droplet")
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(drop.image, drop.quad, left + tile - drop.w - 1, top - cfg.dropletGap - 1)
      elseif cue == "ready" then
        local a, frame = CropCues.sparkle(self.uiTime, x, y, cfg, reduce)
        local star = Assets.sprite("cue_ready_" .. frame)
        love.graphics.setColor(1, 1, 1, a * alpha)
        love.graphics.draw(star.image, star.quad, left + tile - star.w - 1, top - 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Fireflies and dust motes over the graded world (world space, camera transform on).
function Renderer:drawAmbient(visible, daylight)
  if not Settings.read("ambientFx", true) then
    return
  end
  local snow = self:winterAmounts()
  Ambient.draw(self, visible, daylight, snow)
end

--- Apply the colour grade while drawing `canvas` (the rendered world) to the screen.
function Renderer:drawGraded(canvas, tint, light, pixelSize, haze)
  local v = self.world.tuning.visuals
  local shader = Shaders.get("grade")
  if Settings.read("reduceMotion", false) then
    haze = nil -- no heat shimmer (D96)
  end
  -- Player-set grade strength (D96): 1 = as designed, 0 = no tint, saturation shift or vignette.
  local g = Settings.read("gradeStrength", 1)
  local function toward(neutral, value)
    return neutral + (value - neutral) * g
  end
  if shader then
    tint = { toward(1, tint[1]), toward(1, tint[2]), toward(1, tint[3]) }
    -- Heat shimmer rides in the grade pass (D85): `haze` = { amount, sources, origin, world } or nil.
    local sources = haze and haze.sources or {}
    Shaders.send(shader, {
      canvasSize = { canvas:getWidth(), canvas:getHeight() },
      hazeAmount = haze and haze.amount or 0,
      hazeCover = v.heat.cover,
      hazePatch = { v.heat.patchW, v.heat.patchH },
      hazeRise = v.heat.rise,
      hazeSpeed = v.heat.speed,
      sourceSpeed = v.heat.sourceSpeed,
      heatCount = #sources,
      gridOrigin = haze and haze.origin or { 0, 0 },
      worldCell = haze and haze.world or { 0, 0 },
    })
    if #sources > 0 and shader:hasUniform("heatSources") then
      shader:send("heatSources", unpack(sources))
    end
    Shaders.send(shader, {
      tint = tint,
      light = light,
      saturation = toward(1, v.saturation * v.seasonGrade[Calendar.now(self.world).season].saturation),
      vignette = v.vignette * g,
      grain = Settings.read("filmGrain", true) and v.grain or 0,
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
