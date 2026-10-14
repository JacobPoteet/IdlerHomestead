-- Frame-time probes behind the F3 overlay (#19, D103): CPU milliseconds per sim tick, per update and
-- per draw (the time LÖVE spends submitting the frame, not the GPU's), averaged over a window of frames.
-- Off unless `Perf.enabled` (main.lua ties it to the overlay), so a normal frame pays one boolean test.
-- Never touches the sim: callers time their own calls and report here. Presentation/tooling only.

local Perf = { enabled = false, window = 60 }

local function newBucket()
  return { frame = 0, count = 0, frames = {}, next = 1 }
end

local buckets = { tick = newBucket(), update = newBucket(), draw = newBucket() }
local ticksThisFrame, tickRing, tickRingNext, tickMax = 0, {}, 1, 0

--- Seconds, from the same clock everywhere (love.timer when present, so it matches the frame time).
function Perf.now()
  return love and love.timer and love.timer.getTime() or os.clock()
end

--- Add `seconds` to the current frame's total for `name` ("tick", "update" or "draw").
function Perf.add(name, seconds)
  local b = buckets[name]
  b.frame = b.frame + seconds
  b.count = b.count + 1
  if name == "tick" then
    ticksThisFrame = ticksThisFrame + 1
    if seconds > tickMax then
      tickMax = seconds
    end
  end
end

--- Close the frame: fold its totals into the rolling windows.
function Perf.endFrame()
  for _, b in pairs(buckets) do
    b.frames[b.next] = b.frame
    b.next = b.next % Perf.window + 1
    b.frame, b.count = 0, 0
  end
  tickRing[tickRingNext] = ticksThisFrame
  tickRingNext = tickRingNext % Perf.window + 1
  ticksThisFrame = 0
end

local function mean(list)
  local sum, n = 0, 0
  for _, v in ipairs(list) do
    sum, n = sum + v, n + 1
  end
  return n > 0 and sum / n or 0
end

local function maxOf(list)
  local m = 0
  for _, v in ipairs(list) do
    m = math.max(m, v)
  end
  return m
end

--- Averages over the window: { tickMs (per tick), ticksPerFrame, simMs (sim time per frame), updateMs,
--- drawMs, worstDrawMs, worstTickMs }.
function Perf.summary()
  local ticksPerFrame = mean(tickRing)
  local simPerFrame = mean(buckets.tick.frames)
  return {
    tickMs = ticksPerFrame > 0 and simPerFrame / ticksPerFrame * 1000 or 0,
    ticksPerFrame = ticksPerFrame,
    simMs = simPerFrame * 1000,
    updateMs = mean(buckets.update.frames) * 1000,
    drawMs = mean(buckets.draw.frames) * 1000,
    worstDrawMs = maxOf(buckets.draw.frames) * 1000,
    worstTickMs = tickMax * 1000,
  }
end

--- Forget the worst-tick figure (the overlay shows the worst since it was opened or reset).
function Perf.reset()
  tickMax = 0
  for _, b in pairs(buckets) do
    b.frames, b.next, b.frame, b.count = {}, 1, 0, 0
  end
  tickRing, tickRingNext, ticksThisFrame = {}, 1, 0
end

--- Overlay text lines. `budget` is tuning.perf (optional): the figures are flagged "OVER" past it.
function Perf.lines(budget)
  local s = Perf.summary()
  local function flag(value, limit)
    return limit and value > limit and " OVER" or ""
  end
  return {
    string.format(
      "Sim: %.3f ms/tick, %.1f ticks/frame (%.2f ms)%s",
      s.tickMs,
      s.ticksPerFrame,
      s.simMs,
      flag(s.tickMs, budget and budget.simMsPerTick)
    ),
    string.format("Worst tick: %.2f ms%s", s.worstTickMs, flag(s.worstTickMs, budget and budget.worstTickMs)),
    string.format(
      "Update: %.2f ms  Draw: %.2f ms (CPU)%s",
      s.updateMs,
      s.drawMs,
      flag(s.drawMs, budget and budget.drawMs)
    ),
  }
end

return Perf
