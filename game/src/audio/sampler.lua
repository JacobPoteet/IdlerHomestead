-- Reads the world for the audio service (GDD D100). Like src/render/, it only reads sim state through
-- accessors and never changes it. Returns the plain snapshot src/audio/cues.lua turns into bed levels.

local Calendar = require("src.sim.systems.calendar")
local Lights = require("src.render.lights")
local Power = require("src.sim.systems.power")
local Weather = require("src.sim.systems.weather")

local Sampler = {}

--- Tiles from the view centre to the nearest lit heat source (campfire, stove), or nil if none burns.
local function nearestFire(world, cx, cy)
  local grid = world.state.grid
  local best
  for _, lit in ipairs(Lights.visible(world, { 1, 1, grid.w, grid.h }, 0)) do
    if lit.light.on == "heat" then
      local d = math.sqrt((lit.tileX - cx) ^ 2 + (lit.tileY - cy) ^ 2)
      if not best or d < best then
        best = d
      end
    end
  end
  return best
end

--- ctx = { world, speed (Session:effectiveSpeed), fx (the renderer's weather fx), center = { tileX, tileY } }
function Sampler.snapshot(ctx)
  local world = ctx.world
  local rain = ctx.fx and (ctx.fx:rainAndWet()) or 0
  local wind = Weather.windStrength(world)
  if ctx.fx then
    local _, eased = ctx.fx:windSway()
    wind = eased
  end
  return {
    speed = ctx.speed,
    night = Calendar.isNight(world),
    season = Calendar.now(world).season,
    kind = Weather.kind(world),
    wind = wind,
    rain = rain,
    frozen = Weather.isFrozen(world),
    fire = ctx.center and nearestFire(world, ctx.center[1], ctx.center[2]) or nil,
    hum = Power.output(world) > 0,
  }
end

return Sampler
