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

--- Falling rain across the screen: slanted streaks that scroll down, denser the harder it rains.
--- `view` is the virtual screen { w, h }; the streaks are drawn in those units.
function Fx:drawRain(view)
  local cfg = self.world.tuning.visuals.weather.rain
  if self.rain <= 0.01 then
    return
  end
  local count = math.floor(cfg.drops * self.rain * (view.w * view.h) / cfg.referenceArea)
  love.graphics.push("all")
  love.graphics.setLineWidth(cfg.width)
  love.graphics.setColor(cfg.color[1], cfg.color[2], cfg.color[3], cfg.color[4] * math.min(1, self.rain))
  local w, h = view.w, view.h
  local slant = cfg.slant
  for n = 1, count do
    local speed = cfg.speed * lerp(0.7, 1.3, hash(n, 3))
    local len = cfg.length * lerp(0.6, 1.2, hash(n, 5))
    local y = (hash(n, 2) * (h + len) + self.time * speed) % (h + len) - len
    local x = (hash(n, 1) * (w + slant * h) - slant * y) % w
    love.graphics.line(x, y, x - slant * len, y + len)
  end
  love.graphics.pop()
end

return Fx
