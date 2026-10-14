-- Weather presentation (GDD §7.1, D51, D83): the grey-blue cast of cloud, the falling rain, the wet
-- ground and the drifting cloud shadows. It reads the sim's weather and never changes it. Look values
-- live in tuning.visuals.weather, keyed by weather kind. Wetness and cloud drift are eased here and
-- handed to ground.glsl, water.glsl and clouds.glsl by the renderer. It also keeps the clocks the wind sway and the mist drift run on (D84).

local Grid = require("src.sim.grid")
local Weather = require("src.sim.systems.weather")
local Wetness = require("src.render.wetness")

local Fx = {}
Fx.__index = Fx

local DRIFT_WRAP = 1048576 -- art pixels (2^20): keeps the drift exact in a float, wraps after ~60 hours of play

local SWAY_WRAP = 2 * math.pi * 1000 -- radians: a whole number of turns, so the wrap is invisible

local function cfg_wind(world)
  return world.tuning.visuals.wind
end

local function lerp(a, b, t)
  if math.abs(b - a) < 1e-4 then
    return b -- arrived: an easing look settles exactly, so a paused frame stops changing (D97)
  end
  return a + (b - a) * t
end

local function target(world)
  local look = world.tuning.visuals.weather.looks[Weather.kind(world)]
  -- No rain falls on frozen ground (snow is the winter look), whatever the day's kind says.
  local rain = Weather.isRaining(world) and look.rain or 0
  return look, rain
end

local function wetTarget(cfg, rain)
  return Wetness.target(cfg.wet, rain)
end

function Fx.new(world)
  local look, rain = target(world)
  return setmetatable({
    world = world,
    tint = { look.tint[1], look.tint[2], look.tint[3] },
    light = look.light,
    rain = rain,
    wet = wetTarget(world.tuning.visuals.weather, rain),
    wind = Weather.windStrength(world),
    drift = { 0, 0 }, -- art pixels the cloud shadows have drifted
    mistDrift = { 0, 0 }, -- art pixels the mist banks have drifted
    dustDrift = { 0, 0 }, -- art pixels the dust motes have drifted
    swayClock = 0, -- radians of wind sway so far
    time = 0,
  }, Fx)
end

--- Ease the look toward today's weather so a new day fades in rather than snapping.
--- `dt` = real seconds (easing toward the weather); `step` = effect-clock seconds (D97: game time, 0 while
--- paused), which drives everything that moves: rain, clouds, sway, mist and dust. nil = `dt`.
function Fx:update(dt, step)
  step = step or dt
  local cfg = self.world.tuning.visuals.weather
  local look, rain = target(self.world)
  local k = math.min(1, dt / cfg.blendSeconds)
  for n = 1, 3 do
    self.tint[n] = lerp(self.tint[n], look.tint[n], k)
  end
  self.light = lerp(self.light, look.light, k)
  self.rain = lerp(self.rain, rain, k)
  self.time = (self.time + step) % 3600

  -- Wet land soaks in quickly and dries slowly, on game time (the effect-clock step, D124): paused it
  -- holds, and at 2x and 4x it dries at the capped rate instead of in real seconds.
  self.wet = Wetness.advance(cfg.wet, self.wet, wetTarget(cfg, rain), step)

  -- Cloud shadows drift downwind; the speed eases toward the day's wind so a gust never jumps them.
  local clouds = cfg.clouds
  self.wind = lerp(self.wind, Weather.windStrength(self.world), math.min(1, dt / clouds.windBlendSeconds))
  local dx, dy = clouds.direction[1], clouds.direction[2]
  local cstep = clouds.speed * self.wind * step / math.sqrt(dx * dx + dy * dy)
  self.drift[1] = (self.drift[1] + dx * cstep) % DRIFT_WRAP
  self.drift[2] = (self.drift[2] + dy * cstep) % DRIFT_WRAP

  -- Wind sway: a clock in radians that speeds up with the (eased) wind, so a gust never jumps the pose.
  -- The wrap is a whole number of turns, so the sine carries on unbroken.
  self.swayClock = (self.swayClock + cfg_wind(self.world).speed * self.wind * step) % SWAY_WRAP

  -- Mist banks drift slowly downwind.
  local mist = self.world.tuning.visuals.mist
  local mx, my = mist.direction[1], mist.direction[2]
  local mstep = mist.drift * self.wind * step / math.sqrt(mx * mx + my * my)
  self.mistDrift[1] = (self.mistDrift[1] + mx * mstep) % DRIFT_WRAP
  self.mistDrift[2] = (self.mistDrift[2] + my * mstep) % DRIFT_WRAP

  -- Dust motes drift downwind the same way (D85).
  local dust = self.world.tuning.visuals.dust
  local ux, uy = dust.direction[1], dust.direction[2]
  local dstep = dust.speed * self.wind * step / math.sqrt(ux * ux + uy * uy)
  self.dustDrift[1] = (self.dustDrift[1] + ux * dstep) % DRIFT_WRAP
  self.dustDrift[2] = (self.dustDrift[2] + uy * dstep) % DRIFT_WRAP
end

--- Wind for the sway shader: the clock (radians) and the eased wind strength (1 = ordinary).
function Fx:windSway()
  return self.swayClock, self.wind
end

--- Mist banks' drift in art pixels.
function Fx:mistOffset()
  return self.mistDrift
end

--- Multipliers for the colour grade: tint {r, g, b} and light level.
function Fx:grade()
  return self.tint, self.light
end

--- How hard it rains right now (0..1, eased) and how wet the ground is (0..1).
function Fx:rainAndWet()
  return self.rain, self.wet
end

--- Cloud cover 0..1 for today (an open sky still has a few shadows) and the drift in art pixels.
function Fx:clouds()
  local cfg = self.world.tuning.visuals.weather.clouds
  return math.min(1, cfg.base + Weather.current(self.world).cloud * cfg.gain), self.drift
end

-- A repeatable 0..1 value for drop n (no game RNG: this is only decoration).
local function hash(n, salt)
  local v = math.sin(n * 12.9898 + salt * 78.233) * 43758.5453
  return v - math.floor(v)
end

--- Is the world art pixel (wx, wy) open water (or off the map)? Rain rings there belong to the
--- creek shader, so the ground rings skip it.
local function onWater(world, wx, wy)
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local tx, ty = math.floor(wx / tile) + 1, math.floor(wy / tile) + 1
  if not Grid.inBounds(grid, tx, ty) then
    return true
  end
  return Grid.terrain(world, Grid.index(grid, tx, ty)).water == true
end

--- Falling rain over the whole screen: slanted streaks that scroll down, and flat splash rings landing
--- on the ground, denser the harder it rains. `view` is the virtual screen { w, h }. `grid` = { zoom,
--- ox, oy, wx, wy } is the art-pixel grid on that screen: virtual pixels per art pixel, the grid's
--- offset, and the world art pixel at its first column and row. Streaks fall through the air, so they
--- are laid out on the screen; splash rings are placed in WORLD cells, so they stay on the spot of
--- ground they hit while the camera pans (#193, D83). Everything is in art pixels scaled by the zoom.
function Fx:drawRain(view, grid)
  local cfg = self.world.tuning.visuals.weather.rain
  if self.rain <= 0.01 then
    return
  end
  local z = grid.zoom
  local ox, oy = grid.ox, grid.oy
  local cols, rows = math.ceil(view.w / z) + 1, math.ceil(view.h / z) + 1 -- the screen in art pixels
  local area = cols * rows / cfg.referenceArea
  local strength = math.min(1, self.rain)
  local c = cfg.color
  love.graphics.push("all")

  local function pixel(cx, cy)
    love.graphics.rectangle("fill", ox + cx * z, oy + cy * z, z, z)
  end

  love.graphics.setColor(c[1], c[2], c[3], c[4] * strength)
  local slant = cfg.slant
  for n = 1, math.floor(cfg.drops * self.rain * area) do
    local speed = cfg.speed * lerp(0.7, 1.3, hash(n, 3))
    local len = math.max(2, math.floor(cfg.length * lerp(0.6, 1.2, hash(n, 5)) + 0.5))
    local y = (hash(n, 2) * (rows + len) + self.time * speed) % (rows + len) - len
    local x = hash(n, 1) * (cols + slant * rows) - slant * y
    for k = 0, len - 1 do -- one art pixel per row, leaning with the wind
      pixel(math.floor((x - slant * k) % cols), math.floor(y + k))
    end
  end

  -- Splash rings: every world cell may land one ring per cycle, spreading as a flat ring and fading.
  local radius, cw, ch = cfg.splashRadius, cfg.splashCellW, cfg.splashCellH
  local chance = cfg.splashChance * self.rain
  local firstX, firstY = math.floor(grid.wx / cw), math.floor(grid.wy / ch)
  local lastX, lastY = math.floor((grid.wx + cols) / cw), math.floor((grid.wy + rows) / ch)
  for cellY = firstY, lastY do
    for cellX = firstX, lastX do
      local id = cellX * 7919 + cellY * 104729
      local phase = self.time / cfg.splashSeconds + hash(id, 7)
      local cycle = math.floor(phase)
      local age = phase - cycle
      local seed = id + cycle * 131
      if hash(seed, 6) < chance then
        -- Keep the whole ring inside its cell so neighbours never overlap or clip.
        local wx = cellX * cw + radius + math.floor(hash(seed, 8) * (cw - 2 * radius))
        local wy = cellY * ch + radius + math.floor(hash(seed, 9) * (ch - 2 * radius))
        if not onWater(self.world, wx, wy) then
          local cx, cy = wx - grid.wx, wy - grid.wy -- back to screen art pixels
          local r = 1 + math.floor(age * radius)
          love.graphics.setColor(c[1], c[2], c[3], cfg.splashAlpha * (1 - age) * strength)
          local steps = math.max(8, r * 4)
          local seen = {}
          for s = 0, steps - 1 do
            local a = s / steps * 2 * math.pi
            local px, py = cx + math.floor(math.cos(a) * r + 0.5), cy + math.floor(math.sin(a) * r * 0.5 + 0.5)
            local key = px * 4096 + py
            if not seen[key] then
              seen[key] = true
              pixel(px, py)
            end
          end
        end
      end
    end
  end
  love.graphics.pop()
end

return Fx
