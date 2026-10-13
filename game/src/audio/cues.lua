-- Pure decisions of the audio service (GDD D100): which cue an event plays, and how loud each ambience
-- bed should be. No audio device and no sim access here: callers pass plain values, so it is tested headless.

local Cues = {}

--- The cue id a world event plays, or nil. `events` = the sounds data's event table.
function Cues.forEvent(events, name, payload)
  local rule = events[name]
  if rule == nil then
    return nil
  end
  if type(rule) == "string" then
    return rule
  end
  local key = payload and payload[rule.field]
  local cue = key ~= nil and rule.map[key] or nil
  return cue or rule.default
end

local function clamp01(v)
  return math.min(1, math.max(0, v))
end

--- Target level 0..1 of every ambience bed. `snap`:
---   night (bool), season (id), wind (eased Weather.windStrength), rain (eased 0..1), frozen (bool),
---   fire (tiles to the nearest lit fire, or nil), hum (bool: a powered machine is running).
function Cues.beds(snap, cfg)
  local calm = snap.rain < cfg.rainQuiet and 1 - snap.rain / cfg.rainQuiet or 0
  local day = not snap.night
  local fire = 0
  if snap.fire then
    fire = clamp01(1 - snap.fire / cfg.fireRange)
  end
  return {
    amb_birds = day and (cfg.birdSeasons[snap.season] or 0) * calm or 0,
    amb_creek = snap.frozen and cfg.frozenCreek or 1,
    amb_wind = clamp01((snap.wind - cfg.windFloor) / (cfg.windFull - cfg.windFloor)),
    amb_crickets = snap.night and (cfg.cricketSeasons[snap.season] or 0) * calm or 0,
    amb_rain = clamp01(snap.rain),
    amb_fire = fire,
    amb_hum = snap.hum and 1 or 0,
  }
end

return Cues
