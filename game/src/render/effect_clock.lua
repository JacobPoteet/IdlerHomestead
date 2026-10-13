-- Effect clock (GDD D97): the render layer's own time. Presentation only, it never touches the sim.
--
-- `world` time advances by dt * game speed, so flames, wind, clouds, water and the like stand still
-- while the game is paused (player pause, tip card, town) and run faster at 2x/4x. The speed is capped
-- (`maxSpeed`) so a night skip at 8x/60x does not strobe a flame. `real` time always runs by dt, for
-- UI pulses. Both only ever advance by a non-negative step, so changing the speed or pausing changes the
-- rate of the clock and never its value: nothing jumps.

local EffectClock = {}
EffectClock.__index = EffectClock

--- `cfg` = tuning.visuals.effectClock: { maxSpeed, wrap }.
function EffectClock.new(cfg)
  return setmetatable({ cfg = cfg, world = 0, real = 0, speed = 1 }, EffectClock)
end

--- Advance by real seconds `dt` at game speed `speed` (nil = 1). Returns the world-time step taken.
function EffectClock:advance(dt, speed)
  local cfg = self.cfg
  speed = math.max(0, math.min(speed or 1, cfg.maxSpeed))
  self.speed = speed
  local step = dt * speed
  self.world = (self.world + step) % cfg.wrap
  self.real = (self.real + dt) % cfg.wrap
  return step
end

return EffectClock
