-- Fixed-step simulation clock.
-- Converts variable frame time into a whole number of fixed-length simulation ticks,
-- so the sim behaves identically regardless of frame rate or time scale.

local Clock = {}
Clock.__index = Clock

--- opts.tickRate: ticks per second of sim time.
--- opts.maxTicksPerFrame: safety cap; backlog beyond this is dropped instead of spiralling.
function Clock.new(opts)
  assert(opts and opts.tickRate and opts.tickRate > 0, "Clock.new requires a positive tickRate")
  assert(opts.maxTicksPerFrame and opts.maxTicksPerFrame > 0, "Clock.new requires maxTicksPerFrame")
  return setmetatable({
    step = 1 / opts.tickRate,
    maxTicksPerFrame = opts.maxTicksPerFrame,
    timeScale = 1,
    paused = false,
    accumulator = 0,
  }, Clock)
end

--- Advance by real time `dt`, calling onTick(step) once per due tick. Returns ticks run.
function Clock:advance(dt, onTick)
  if self.paused then
    return 0
  end
  self.accumulator = self.accumulator + dt * self.timeScale
  -- Tolerance so float error (e.g. 0.1 + 0.1 + 0.1 < 0.3) never swallows a due tick.
  local due = self.step * (1 - 1e-6)
  local ticks = 0
  while self.accumulator >= due and ticks < self.maxTicksPerFrame do
    self.accumulator = self.accumulator - self.step
    ticks = ticks + 1
    onTick(self.step)
  end
  if self.accumulator < 0 then
    self.accumulator = 0
  end
  if ticks >= self.maxTicksPerFrame and self.accumulator >= due then
    -- Too far behind (e.g. a long hitch); drop the backlog rather than freezing.
    self.accumulator = 0
  end
  return ticks
end

--- Fraction of the way to the next tick, for render interpolation.
function Clock:alpha()
  return self.accumulator / self.step
end

return Clock
