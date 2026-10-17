-- Plain words for the limit on wood from trees (issue #362, tuning.wood.fellAllowance): the Tonight card's warmth row,
-- the winter readiness card and the refusal toast. Pure: it turns Felling.outlook into sentences, so tests can check
-- the figures without a window. The numbers come from the sim; none are decided here.

local FellingText = {}

FellingText.refused = "No more wood from trees this season: the frost has them. Logs and brush still clear"

--- The Tonight card's sentence for the current season's limit, or nil when this season has none.
function FellingText.tonight(out)
  if not out or not out.now then
    return nil
  end
  if out.left <= 0 then
    return string.format("Trees give no more wood this %s. Logs, brush and the truck still bring wood.", out.season)
  end
  return string.format("Trees: %d of %d wood left this %s.", out.left, out.allowance, out.season)
end

--- The readiness card's sentence for the limit (now or ahead), or nil when no season is limited.
function FellingText.readiness(out)
  if not out then
    return nil
  end
  if not out.now then
    return string.format(
      "Once it is %s, trees give only %d wood in all: stock the rest of the wood before then.",
      out.season,
      out.allowance
    )
  end
  if out.left <= 0 then
    return string.format("Trees give no more wood this %s; wood in the store must carry the rest.", out.season)
  end
  return string.format(
    "Trees: %d of %d wood left this %s. Wood in the store carries the rest.",
    out.left,
    out.allowance,
    out.season
  )
end

--- The readiness card's advice when the fuel is short: how to get wood given the limit. `full` is true when the wood store
--- is full (a woodshed holds more).
function FellingText.advice(out, full)
  if full then
    return "the wood store is full: a woodshed holds more"
  end
  if out and out.now and out.left <= 0 then
    return "trees are used up: log and brush wood, or buy wood"
  elseif out and not out.now then
    return "fell trees now (they are limited once it is " .. out.season .. ") or buy wood"
  end
  return "fell trees or buy wood"
end

return FellingText
