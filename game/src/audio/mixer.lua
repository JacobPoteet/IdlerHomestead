-- Volume maths for the audio service (GDD D100). Pure functions, no audio device needed.

local Mixer = {}

--- Slider value 0..1 -> gain 0..1 (a power curve, so the low end of the slider is finer).
function Mixer.curve(v, exponent)
  v = math.min(1, math.max(0, v))
  return v ^ exponent
end

--- Gain of a bus: master x bus slider (music also has a fixed extra gain). `volumes` = { master, music,
--- ambience, sfx } sliders in 0..1.
function Mixer.busGain(volumes, bus, cfg)
  local g = Mixer.curve(volumes.master, cfg.volumeCurve) * Mixer.curve(volumes[bus], cfg.volumeCurve)
  if bus == "music" then
    g = g * cfg.musicGain
  end
  return g
end

--- Move `current` toward `target`, taking `seconds` for a full 0..1 swing, so a fade lasts the same
--- time whatever its size. dt in seconds.
function Mixer.approach(current, target, dt, seconds)
  if seconds <= 0 then
    return target
  end
  local step = dt / seconds
  if current < target then
    return math.min(target, current + step)
  end
  return math.max(target, current - step)
end

--- Level the ambience should sit at: full normally, `pausedDuck` while game time is paused.
function Mixer.duckTarget(paused, cfg)
  return paused and cfg.pausedDuck or 1
end

--- Pitch for one play: the cue's base pitch times a random spread. `roll` is a number in -1..1 from
--- the audio-local RNG.
function Mixer.pitch(base, spread, roll)
  return (base or 1) * (1 + (spread or 0) * roll)
end

--- May a cue play now? `last` = time it last played (nil = never), `now`, `cooldown` seconds.
function Mixer.ready(last, now, cooldown)
  return last == nil or cooldown == nil or now - last >= cooldown
end

return Mixer
