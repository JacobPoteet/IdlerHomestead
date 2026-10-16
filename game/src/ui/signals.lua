-- Calm signals (GDD §9.4, D142): when an amber plate glints and where, and which frame a red plate's beat is
-- in. Pure functions of time, so the schedules are tested headless and the flash limit is checked on the
-- real numbers. Amber is a steady quiet outline plus one pixel of glint every few seconds; red is a slow
-- three-frame beat. Neither is ever a fade or a flash. Knobs: tuning.ui.motion.amber and .red.

local Signals = {}

--- The cycle number of `t` and the seconds into it, for a cycle of `every` seconds.
local function cycle(t, every)
  local n = math.floor(t / every)
  return n, t - n * every
end

--- A whole number from a cycle and a salt (so each plate glints at its own spot and moment).
local function scramble(n, salt)
  local v = math.sin(n * 12.9898 + salt * 78.233) * 43758.5453
  return v - math.floor(v)
end

--- The i-th pixel (0-based) round the ring of a w x h plate, `margin` pixels in from every corner so the
--- glint never sits on a cut corner. Returns x, y in plate pixels, or nil when the plate is too small.
function Signals.ringPixel(i, w, h, margin)
  local across, down = w - 2 * margin, h - 2 * margin
  if across < 1 or down < 1 then
    return nil
  end
  local total = 2 * (across + down)
  i = i % total
  if i < across then
    return margin + i, 0
  end
  i = i - across
  if i < down then
    return w - 1, margin + i
  end
  i = i - down
  if i < across then
    return w - 1 - margin - i, h - 1
  end
  i = i - across
  return 0, h - 1 - margin - i
end

--- Where an amber plate's glint is at time `t` (seconds), as x, y in plate pixels, or nil between glints.
--- `salt` makes each plate its own. A glint lasts `cfg.hold` seconds every `cfg.every`, at a new place.
function Signals.glint(t, cfg, w, h, salt, margin)
  local n, into = cycle(t + scramble(0, salt) * cfg.every, cfg.every)
  if into >= cfg.hold then
    return nil
  end
  local across, down = w - 2 * margin, h - 2 * margin
  if across < 1 or down < 1 then
    return nil
  end
  local i = math.floor(scramble(n, salt) * 2 * (across + down))
  return Signals.ringPixel(i, w, h, margin)
end

--- Is a glint showing at time `t`? (The same schedule as `glint`, without a place; for the flash audit.)
function Signals.glinting(t, cfg, salt)
  local _, into = cycle(t + scramble(0, salt) * cfg.every, cfg.every)
  return into < cfg.hold
end

--- Which frame (1, 2 or 3) a red plate's beat is in at time `t`: rest, then up through 2 to 3 and back down
--- through 2, the rest of the beat split evenly among the three. Frame 1 holds for `cfg.rest` of the beat.
function Signals.beatFrame(t, cfg)
  local _, into = cycle(t, cfg.every)
  local u = into / cfg.every
  if u < cfg.rest then
    return 1
  end
  local k = (u - cfg.rest) / ((1 - cfg.rest) / 3)
  return k < 1 and 2 or k < 2 and 3 or 2
end

--- How far toward red the outline sits at time `t` (0..1). `reduce`: Reduce motion holds the last frame.
function Signals.beatLevel(t, cfg, reduce)
  if reduce then
    return cfg.levels[3]
  end
  return cfg.levels[Signals.beatFrame(t, cfg)]
end

return Signals
