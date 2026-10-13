-- Ambient air life (D85): fireflies on warm evenings and dust motes in dry daylight, plus the "how hot is
-- it" amount behind the heat shimmer. Presentation only: it reads the calendar and the weather, never
-- changes them, and uses no game RNG. Positions are a pure function of a world cell and the render
-- clock (a small hash), so they are world-anchored: they pan and zoom with the land. Everything is
-- drawn as whole art pixels. Parameters: tuning.visuals.fireflies / dust / heat.

local Grid = require("src.sim.grid")
local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")

local Ambient = {}

local function hash(n, salt)
  local v = math.sin(n * 12.9898 + salt * 78.233) * 43758.5453
  return v - math.floor(v)
end

local function smooth(a, b, x)
  local t = math.min(1, math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
end

--- 0..1: how many fireflies are out. Warm evenings only: after sunset until a few hours into the night,
--- in the warm seasons, not in rain and not in a gale.
function Ambient.fireflyAmount(world, fx)
  local cfg = world.tuning.visuals.fireflies
  local now = Calendar.now(world)
  local season = cfg.seasons[now.season]
  if season <= 0 then
    return 0
  end
  local _, sunset = Calendar.daylight(world)
  local h = now.hour - sunset
  local time = smooth(cfg.inStart, cfg.inEnd, h) * (1 - smooth(cfg.outStart, cfg.outEnd, h))
  if time <= 0 then
    return 0
  end
  local rain = fx:rainAndWet()
  local calm = 1 - smooth(cfg.calmUntil, cfg.windKill, fx.wind)
  return time * season * calm * (1 - math.min(1, rain * 2))
end

--- 0..1: how much dust hangs in the air. Dry daylight only; wind raises it, rain and snow settle it.
function Ambient.dustAmount(world, fx, daylight, snow)
  local cfg = world.tuning.visuals.dust
  local season = cfg.seasons[Calendar.now(world).season]
  local light = smooth(cfg.daylightFrom, cfg.daylightFull, daylight)
  if season <= 0 or light <= 0 then
    return 0
  end
  local rain, wet = fx:rainAndWet()
  local windy = smooth(cfg.windMin, cfg.windFull, fx.wind)
  return light * season * (cfg.calm + (1 - cfg.calm) * windy) * (1 - math.min(1, wet + rain)) * (1 - snow)
end

--- 0..1: how hot it is. Peaks at solar noon on a clear summer day.
function Ambient.heatAmount(world, daylight, snow)
  local cfg = world.tuning.visuals.heat
  local now = Calendar.now(world)
  local season = cfg.seasons[now.season]
  if season <= 0 or daylight <= 0.5 then
    return 0
  end
  local sunrise, sunset = Calendar.daylight(world)
  local noon = (sunrise + sunset) / 2
  local near = 1 - smooth(1, cfg.noonHours, math.abs(now.hour - noon))
  return season * cfg.sky[Weather.kind(world)] * near * (1 - snow)
end

local function inRange(renderer, visible)
  local tile = renderer.tile
  return (visible[1] - 1) * tile, (visible[2] - 1) * tile, visible[3] * tile, (visible[4] + 1) * tile
end

--- Fireflies: warm dots that wander a few pixels and pulse, over grass (more beside the creek). Additive,
--- over the graded world, in world space (call with the camera transform on).
local function drawFireflies(renderer, visible, amount)
  local world, fx = renderer.world, renderer.fx
  local grid, tile = world.state.grid, renderer.tile
  local cfg = world.tuning.visuals.fireflies
  local c, cell = cfg.color, cfg.cell
  local x0, y0, x1, y1 = inRange(renderer, visible)
  local t = fx.time
  love.graphics.setBlendMode("add")
  for cy = math.floor(y0 / cell) - 1, math.floor(y1 / cell) do
    for cx = math.floor(x0 / cell) - 1, math.floor(x1 / cell) do
      for k = 1, cfg.perCell do
        local id = cx * 7919 + cy * 104729 + k * 31
        local hx, hy = cx * cell + hash(id, 1) * cell, cy * cell + hash(id, 2) * cell
        local tx, ty = math.floor(hx / tile) + 1, math.floor(hy / tile) + 1
        if Grid.inBounds(grid, tx, ty) then
          local i = Grid.index(grid, tx, ty)
          if grid.terrain[i] == "grass" then
            local near = 1 - math.min(1, (renderer.reach[i] or cfg.reach) / cfg.reach)
            local odds = cfg.farGrass + (cfg.nearCreek - cfg.farGrass) * near
            if hash(id, 3) < odds then
              local drift = t * cfg.wanderSpeed
              local x = hx + math.sin(drift * (0.6 + hash(id, 4)) + hash(id, 5) * 6.28) * cfg.wander
              local y = hy + math.cos(drift * (0.7 + hash(id, 6)) + hash(id, 7) * 6.28) * cfg.wander * 0.6
              local phase = t / (cfg.pulseSeconds * (0.8 + 0.4 * hash(id, 8))) + hash(id, 9)
              local p = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
              p = p * p * p -- mostly dark with a slow bright swell
              local a = amount * p
              if a > 0.02 then
                local px, py = math.floor(x), math.floor(y)
                local g = cfg.glow * a
                love.graphics.setColor(c[1] * g, c[2] * g, c[3] * g, 1)
                love.graphics.rectangle("fill", px, py, 1, 1)
                local h = g * cfg.halo
                love.graphics.setColor(c[1] * h, c[2] * h, c[3] * h, 1)
                love.graphics.rectangle("fill", px - 1, py, 1, 1)
                love.graphics.rectangle("fill", px + 1, py, 1, 1)
                love.graphics.rectangle("fill", px, py - 1, 1, 1)
                love.graphics.rectangle("fill", px, py + 1, 1, 1)
              end
            end
          end
        end
      end
    end
  end
  love.graphics.setBlendMode("alpha")
end

--- Dust motes: pale specks that float on the wind, fading in and out along their path so the wrap is
--- never seen, longer streaks in a gale. Skips the creek. Alpha blended, world space.
local function drawDust(renderer, visible, amount)
  local world, fx = renderer.world, renderer.fx
  local grid, tile = world.state.grid, renderer.tile
  local cfg = world.tuning.visuals.dust
  local c, cell = cfg.color, cfg.cell
  local x0, y0, x1, y1 = inRange(renderer, visible)
  local dx, dy = fx.dustDrift[1], fx.dustDrift[2]
  local t = fx.time
  local streak = math.floor(cfg.streak * smooth(cfg.windMin, cfg.windFull, fx.wind) + 0.5)
  for cy = math.floor(y0 / cell) - 1, math.floor(y1 / cell) do
    for cx = math.floor(x0 / cell) - 1, math.floor(x1 / cell) do
      for k = 1, cfg.perCell do
        local id = cx * 7919 + cy * 104729 + k * 37
        if hash(id, 3) < amount then
          local u = ((hash(id, 1) * cell + dx) % cell) / cell
          local v = ((hash(id, 2) * cell + dy) % cell) / cell
          local fade = math.sin(u * math.pi) * math.sin(v * math.pi)
          local twinkle = 0.65 + 0.35 * math.sin(t * (1 + hash(id, 4)) + hash(id, 5) * 6.28)
          local x = cx * cell + u * cell
          local y = cy * cell + v * cell + math.sin(t * 0.8 + hash(id, 6) * 6.28) * cfg.bob
          local tx, ty = math.floor(x / tile) + 1, math.floor(y / tile) + 1
          if Grid.inBounds(grid, tx, ty) and (renderer.reach[Grid.index(grid, tx, ty)] or 1) > 0 then
            love.graphics.setColor(c[1], c[2], c[3], cfg.alpha * fade * twinkle * (0.5 + 0.5 * amount))
            love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1 + streak, 1)
          end
        end
      end
    end
  end
end

--- Draw both. `visible` = { x1, y1, x2, y2 } tiles; `daylight` 0..1; `snow` 0..1 ground cover.
function Ambient.draw(renderer, visible, daylight, snow)
  local world, fx = renderer.world, renderer.fx
  local flies = Ambient.fireflyAmount(world, fx)
  local dust = Ambient.dustAmount(world, fx, daylight, snow)
  if flies <= 0.01 and dust <= 0.01 then
    return
  end
  love.graphics.push("all")
  if dust > 0.01 then
    drawDust(renderer, visible, dust)
  end
  if flies > 0.01 then
    drawFireflies(renderer, visible, flies)
  end
  love.graphics.pop()
end

return Ambient
