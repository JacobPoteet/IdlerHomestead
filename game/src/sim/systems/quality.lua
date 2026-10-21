-- Crop quality (PLAN_DEPTH 8.6, D182, D185): normal and fine produce.
--
-- Grading (`Quality.grade`, read by the harvest task in crops.lua): a penalty from 0 (a perfect crop) to 1 is made of
-- the tile's missing fertility, its weeds at harvest and how long the crop stood thirsty (crop.thirst, in game days,
-- against `thirstTolerance` of its grow time), weighted by tuning.quality. The crop's `qualitySensitivity` scales it:
-- sensitivity x penalty at or under `fineMax` is fine, anything over is normal. There is no tended mark, so the idle
-- routine (which waters and weeds on its own) earns fine on healthy soil as the player does.
--
-- Stock: the ledger holds plain counts, so the tiers are a tally that follows it, as the spoilage batches do.
--   world.state.quality = { [resourceId] = { fine = units } }   (units above normal only)
-- Units that leave the ledger by eating, spoiling or the stand take the lowest tier first (the family eats the worst,
-- the stand sells the worst and keeps the best for the truck); a truck sale calls `Quality.take(.., "best")` first so
-- the best units are the ones sold. The tally is trimmed to the ledger on every decrease, so it can never exceed it.
--
-- Hook for the contracts board (E2): `Quality.atLeast(world, id, tier)` is the units of a good at that tier or better,
-- and `crop.harvested` carries the tier in `quality`.

local Ledger = require("src.sim.systems.ledger")
local Soil = require("src.sim.systems.soil")

local Quality = {}

local function cfg(world)
  return world.tuning.quality
end

--- Tier ids, worst first.
function Quality.tiers(world)
  return cfg(world).tiers
end

--- Rank of a tier, 1 for the lowest.
function Quality.rank(world, tier)
  for rank, id in ipairs(cfg(world).tiers) do
    if id == tier then
      return rank
    end
  end
  error("unknown quality tier '" .. tostring(tier) .. "'")
end

--- Multiplier on a good's sale price for a tier.
function Quality.priceMult(world, tier)
  return cfg(world).priceMult[tier]
end

--- The penalty (0..1) a crop on tile `i` would be graded on now: fertility, weeds and thirst, weighted.
function Quality.penalty(world, i, crop, def)
  local c = cfg(world)
  local thirst = math.min(1, (crop.thirst or 0) / (c.thirstTolerance * def.growDays))
  return c.weightFertility * (1 - Soil.fertility(world, i))
    + c.weightWeeds * Soil.weeds(world, i)
    + c.weightWater * thirst
end

--- Grade the crop on tile `i` as it stands: returns the tier id and the penalty.
function Quality.grade(world, i, crop, def)
  local c = cfg(world)
  local penalty = Quality.penalty(world, i, crop, def)
  local tier = c.tiers[1]
  if def.qualitySensitivity * penalty <= c.fineMax then
    tier = c.tiers[2]
  end
  return tier, penalty
end

-- Stock -----------------------------------------------------------------------------------------

local function tally(world, id)
  return world.state.quality[id]
end

--- Units of `id` in each tier: { normal, fine } (the normal count is what is left of the ledger's).
function Quality.counts(world, id)
  local t = tally(world, id)
  local tiers = cfg(world).tiers
  local fine = t and t[tiers[2]] or 0
  return { [tiers[1]] = math.max(0, Ledger.get(world, id) - fine), [tiers[2]] = fine }
end

--- Units of `id` at `tier` or better (the contracts hook).
function Quality.atLeast(world, id, tier)
  local counts = Quality.counts(world, id)
  local from, n = Quality.rank(world, tier), 0
  for rank, t in ipairs(cfg(world).tiers) do
    if rank >= from then
      n = n + counts[t]
    end
  end
  return n
end

--- Is any unit of `id` above normal?
function Quality.hasAny(world, id)
  return tally(world, id) ~= nil
end

--- Record `n` freshly added units of `id` at `tier` (call after the ledger add, with the amount that fitted).
function Quality.add(world, id, tier, n)
  local tiers = cfg(world).tiers
  if tier == tiers[1] or n <= 0 then
    return
  end
  local t = world.state.quality[id] or {}
  t[tier] = (t[tier] or 0) + n
  world.state.quality[id] = t
end

-- Make the tally add up to at most `total`.
local function trim(world, id, total)
  local t = tally(world, id)
  if not t then
    return
  end
  local fine = cfg(world).tiers[2]
  if (t[fine] or 0) > total then
    t[fine] = total > 0 and total or nil
  end
  if next(t) == nil then
    world.state.quality[id] = nil
  end
end

--- Which tiers the `n` best (order "best") or worst ("worst") units of `id` are: { [tier] = units }.
function Quality.pick(world, id, n, order)
  local counts = Quality.counts(world, id)
  local tiers = cfg(world).tiers
  local out = {}
  local first, last, step = 1, #tiers, 1
  if order == "best" then
    first, last, step = #tiers, 1, -1
  end
  for rank = first, last, step do
    local take = math.min(n, counts[tiers[rank]])
    if take > 0 then
      out[tiers[rank]] = take
      n = n - take
    end
  end
  return out
end

--- Sum of the price multipliers of the `n` best or worst units of `id` (what that many units are worth in units of price).
function Quality.worth(world, id, n, order)
  local sum = 0
  for tier, units in pairs(Quality.pick(world, id, n, order)) do
    sum = sum + units * cfg(world).priceMult[tier]
  end
  return sum
end

--- Take `n` units out of the tally, best or worst first, before the ledger removes them: so a truck sale sells the best
--- units. Returns the tiers taken ({ [tier] = units }).
function Quality.take(world, id, n, order)
  local picked = Quality.pick(world, id, n, order)
  local t = tally(world, id)
  if t then
    for tier, units in pairs(picked) do
      if t[tier] then
        t[tier] = t[tier] - units > 0 and t[tier] - units or nil
      end
    end
    if next(t) == nil then
      world.state.quality[id] = nil
    end
  end
  return picked
end

function Quality.init(world)
  world.state.quality = world.state.quality or {}
  world.events:on("ledger.changed", function(e)
    if e.delta < 0 and world.state.quality[e.id] then
      trim(world, e.id, e.total)
    end
  end)
end

return Quality
