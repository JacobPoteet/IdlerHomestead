-- Tiered upgrades (D198, #382, docs/PLAN_DEPTH.md §11.1): the catalog's money sink. Accessors only, no state.
--
-- A catalog `family` is a ladder of items, each with a `tier` (1 to tuning.economy.tiers.max, I to III after the D184 trim).
-- Tier I is the plain item (rod, axe, stove, ...); each later tier is catalog equipment that replaces the one below it
-- (`replaces`, so the two never add up, D115), needs it owned (`requires`, the minimal prerequisite gate of #264) and carries
-- `modifiers`. Equipment that scales a building names its stat on the object (`tierStat`, read by Stats.scale), so
-- one upgrade improves every building of the kind. No upkeep: a tier is bought once and stays.
-- Cost is exponential: a tier without an explicit `price` costs round(tier I price x growth^(n-1)) (tuning.economy.tiers);
-- the tier I price is the family's tier I item, or the item's own `tierBase` where tier I is not an item (the plain bucket).
-- Tier III is also reputation-gated (tuning.economy.tiers.minDone, contracts finished, D197) and flagged `requiresFooting`.
-- Optional by design: no tier is needed to hold Footing, so an idle run does fine without them.

local Tiers = {}

--- The catalog item of `family` at `tier`, or nil.
function Tiers.find(world, family, tier)
  for _, item in ipairs(world.registry:all("catalog")) do
    if item.family == family and item.tier == tier then
      return item
    end
  end
  return nil
end

--- The $ price of a catalog item before any special: its own `price`, or the exponential tier price.
function Tiers.price(world, item)
  if item.price then
    return item.price
  end
  local cfg = world.tuning.economy.tiers
  local root = Tiers.find(world, item.family, 1)
  local base = root and root.price
  if not base then -- tier I is not an item (the plain bucket): the family names its reference price once
    for _, other in ipairs(world.registry:all("catalog")) do
      if other.family == item.family and other.tierBase then
        base = other.tierBase
      end
    end
  end
  assert(base, "tier item " .. item.id .. " has no price, tierBase or tier I item")
  return math.floor(base * cfg.growth ^ (item.tier - 1) + 0.5)
end

--- The next tier up from a catalog item, or nil (a top tier, or an item outside any family).
function Tiers.nextTier(world, item)
  if not item.family then
    return nil
  end
  return Tiers.find(world, item.family, item.tier + 1)
end

--- Contracts finished that the item's tier needs (0 = none).
function Tiers.minDone(world, item)
  if not item.tier then
    return 0
  end
  return rawget(world.tuning.economy.tiers.minDone, item.tier) or 0 -- strict tuning: a tier with no entry has no gate
end

return Tiers
