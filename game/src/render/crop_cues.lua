-- Crop and plan cues (#20, D102): which little icon a field tile earns. Pure rules, no drawing: the
-- renderer feeds in sim state (a crop, the plan, the tilled flag) and the real-time effect clock (a UI cue,
-- D97), and draws what comes back through the sprite manifest.

local CropCues = {}

--- The cue of a planted tile: "ready" (grown, harvest it), "thirsty" (still growing but dry) or nil.
function CropCues.cue(crop)
  if not crop then
    return nil
  end
  if crop.growth >= 1 then
    return "ready"
  end
  if crop.moisture <= 0 then
    return "thirsty"
  end
  return nil
end

--- How a tile with a standing plan looks: "planned_bare" (not tilled yet), "planned_tilled" (waiting for
--- seed) or nil (no plan, or a crop already stands there, so it is a plant, not an order).
function CropCues.planState(planCropId, tilled, crop)
  if crop or not planCropId then
    return nil
  end
  return tilled and "planned_tilled" or "planned_bare"
end

--- The ripe sparkle at tile (x, y): `alpha` 0..1 and `frame` (1 small plus, 2 star). It twinkles for
--- `sparkleDuty` of each cycle and rests as the plus the rest of the time, staggered per tile. Reduce
--- motion (D96) holds the resting plus still. `cfg` = tuning.visuals.cropCues.
function CropCues.sparkle(uiTime, x, y, cfg, reduceMotion)
  if reduceMotion then
    return cfg.sparkleRest, 1
  end
  local stagger = ((x * 7 + y * 13) % cfg.sparkleSpread) / cfg.sparkleSpread
  local phase = (uiTime / cfg.sparkleSeconds + stagger) % 1
  if phase < cfg.sparkleDuty then
    local t = phase / cfg.sparkleDuty
    return cfg.sparkleRest + (1 - cfg.sparkleRest) * math.sin(math.pi * t), t > 0.25 and t < 0.75 and 2 or 1
  end
  return cfg.sparkleRest, 1
end

--- Icon opacity for the light level (0 night .. 1 day): full by day, dimmed by `nightIconDim` at night.
function CropCues.iconAlpha(daylight, cfg)
  return cfg.iconAlpha * (1 - cfg.nightIconDim * (1 - daylight))
end

--- Extra brightness (0..nightLift) added to crop sprites at this light level, so they hold against dark soil.
function CropCues.nightLift(daylight, cfg)
  return cfg.nightLift * (1 - math.max(0, math.min(1, daylight)))
end

return CropCues
