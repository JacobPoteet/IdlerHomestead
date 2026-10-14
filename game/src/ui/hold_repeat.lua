-- Hold-to-repeat timing for steppers (pure, no love.*; D119, #201). Holding a stepper button, the
-- first repeat comes after `delay` real seconds, then repeats come `rate` per second, and the step
-- grows every `stageTicks` repeats through `stageUnits` (1, 5, 10 ... units per repeat), so a long
-- hold reaches a big number quickly while a short hold stays precise. Everything is a function of
-- the elapsed hold time, so it behaves the same at any sim speed and while paused.

local M = {}

--- Repeats that have fired by `elapsed` seconds of holding (0 before the delay).
function M.count(elapsed, cfg)
  if elapsed < cfg.delay then
    return 0
  end
  return math.floor((elapsed - cfg.delay) * cfg.rate) + 1
end

--- Units the k-th repeat (1-based) moves the number by.
function M.unitsAt(k, cfg)
  local stage = math.min(#cfg.stageUnits, math.floor((k - 1) / cfg.stageTicks) + 1)
  return cfg.stageUnits[stage]
end

--- Total units to move when the hold time goes from `prev` to `now` seconds: the sum of the repeats
--- that fell in that window (0 when none did).
function M.units(prev, now, cfg)
  local total = 0
  for k = M.count(prev, cfg) + 1, M.count(now, cfg) do
    total = total + M.unitsAt(k, cfg)
  end
  return total
end

return M
