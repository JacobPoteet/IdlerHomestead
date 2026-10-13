-- Weather presentation (GDD §7.1, D51): the grey-blue cast of cloud and the falling rain. It
-- reads the sim's weather and never changes it. Look values live in tuning.visuals.weather, keyed
-- by weather kind. Full ambience (cloud shadows, wind sway, wet ground) is tracked in #49.

local Weather = require("src.sim.systems.weather")

local Fx = {}
Fx.__index = Fx

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function target(world)
  local look = world.tuning.visuals.weather.looks[Weather.kind(world)]
  -- No rain falls on frozen ground (snow is the winter look), whatever the day's kind says.
  local rain = Weather.isRaining(world) and look.rain or 0
  return look, rain
end

function Fx.new(world)
  local look, rain = target(world)
  return setmetatable({
    world = world,
    tint = { look.tint[1], look.tint[2], look.tint[3] },
    light = look.light,
    rain = rain,
    time = 0,
  }, Fx)
end

--- Ease the look toward today's weather so a new day fades in rather than snapping.
function Fx:update(dt)
  local cfg = self.world.tuning.visuals.weather
  local look, rain = target(self.world)
  local k = math.min(1, dt / cfg.blendSeconds)
  for n = 1, 3 do
    self.tint[n] = lerp(self.tint[n], look.tint[n], k)
  end
  self.light = lerp(self.light, look.light, k)
  self.rain = lerp(self.rain, rain, k)
  self.time = (self.time + dt) % 3600
end

--- Multipliers for the colour grade: tint {r, g, b} and light level.
function Fx:grade()
  return self.tint, self.light
end

-- A repeatable 0..1 value for drop n (no game RNG: this is only decoration).
local function hash(n, salt)
  local v = math.sin(n * 12.9898 + salt * 78.233) * 43758.5453
  return v - math.floor(v)
end

--- Falling rain over the whole screen: slanted streaks that scroll down and flat splash rings,
--- denser the harder it rains. `view` is the virtual screen { w, h }. `grid` = { zoom, ox, oy } is
--- the art-pixel grid on that screen (virtual pixels per art pixel and the grid's offset), so the
--- rain is built in art pixels and scales with the camera zoom like the land does (#193).
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

  -- Splash rings: each slot lands somewhere new every cycle, spreads as a flat ring, and fades.
  local radius = cfg.splashRadius
  for n = 1, math.floor(cfg.splashes * self.rain * area) do
    local phase = self.time / cfg.splashSeconds + hash(n, 7)
    local cycle = math.floor(phase)
    local age = phase - cycle
    local cx = math.floor(hash(n + cycle * 131, 8) * cols)
    local cy = math.floor(hash(n + cycle * 131, 9) * rows)
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
  love.graphics.pop()
end

return Fx
