-- Plain-words descriptions of crop quality (D182) for the pantry, the truck and the tile card. Numbers come from the
-- Quality accessors; this file only turns them into short phrases.

local Quality = require("src.sim.systems.quality")

local QualityText = {}

--- "fine" -> "Fine".
function QualityText.name(tier)
  return tier:sub(1, 1):upper() .. tier:sub(2)
end

--- "2 fine" for a { [tier] = units } table (the best tier first, normal left out), or nil when every unit
--- is normal.
function QualityText.tiers(world, counts)
  local ids = Quality.tiers(world)
  local parts = {}
  for rank = #ids, 2, -1 do
    local n = counts[ids[rank]] or 0
    if n > 0 then
      parts[#parts + 1] = string.format("%d %s", n, ids[rank])
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

--- The tiers of the stock of one good, as above, or nil when none of it is above normal.
function QualityText.stock(world, id)
  if not Quality.hasAny(world, id) then
    return nil
  end
  return QualityText.tiers(world, Quality.counts(world, id))
end

--- The tile card's line for the crop on tile `i`: the tier it would be graded now, so the player sees what weeding
--- and watering do. Nil when there is no crop or it is a resting perennial.
function QualityText.cropLine(world, i)
  local crop = world.state.crops[i]
  if not crop or (crop.rest and crop.growth < 1) then
    return nil
  end
  local def = world.registry:get("crops", crop.id)
  local tier = Quality.grade(world, i, crop, def)
  return string.format("Quality: %s", tier)
end

return QualityText
