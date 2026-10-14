-- Wetness maths (GDD D83, D124): how soaked the land is, and how that dims objects. Pure functions, no
-- love.graphics, so they test headless. Steps are effect-clock seconds (D97), so wet land soaks and
-- dries on game time: it stands still while paused and runs at the capped game rate at 2x and 4x.

local M = {}

--- How wet the land wants to be for this much rain (0..1). `cfg` = tuning.visuals.weather.wet.
function M.target(cfg, rain)
  return math.min(1, rain / cfg.fullRain)
end

--- Move `wet` toward `want` by `step` effect-clock seconds: it soaks in `riseSeconds` and dries in
--- `drySeconds`. A zero step changes nothing; it settles exactly on `want`.
function M.advance(cfg, wet, want, step)
  if want > wet then
    return math.min(want, wet + step / cfg.riseSeconds)
  end
  return math.max(want, wet - step / cfg.drySeconds)
end

--- Colour multiplier for a sprite on land this wet: white when dry, `cfg.objectTint` when soaked.
--- Writes into `out` (r, g, b) so the per-frame call allocates nothing.
function M.objectTint(cfg, wet, out)
  local tint = cfg.objectTint
  for n = 1, 3 do
    out[n] = 1 + (tint[n] - 1) * wet
  end
  return out
end

--- Relative luminance of a linear-ish rgb colour (the same weights the shaders use).
function M.luma(c)
  return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
end

return M
