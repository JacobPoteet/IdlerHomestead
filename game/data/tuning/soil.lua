-- Soil fertility (PLAN_DEPTH 8.2, D178). Every number is a reasoned first guess for the M9 balance pass.
-- Fertility is 0..1 per tile, beside soil quality (grid.soil) and the water table. A harvest draws it by the
-- crop's `fertilityDraw` (data/content/crops.lua); fallow, legumes, compost and manure give it back.
-- Rotation (PLAN_DEPTH 8.3, D179): harvesting the same crop family twice in a row on a tile builds pest pressure,
-- a different family relieves it; pressure cuts yield and invites pests (the pest* keys).
-- Weeds (PLAN_DEPTH 8.3, D180): field tiles sprout weeds on a timer and weeds cut yield until a pull task clears
-- them (the weed* keys); the Straw mulch equipment (stat weedGuard) holds them back.
return {
  startBase = 0.85, -- 0..1 fertility of new ground of average soil quality, before the variation below
  startSoilWeight = 0.3, -- fertility added per 1.0 of soil quality above 0.5 (below 0.5 takes it away): rich earth starts richer
  startNoise = 0.2, -- fertility span of the seeded patchiness (the `soil` RNG stream): a tile varies by up to half of it either way
  noiseScale = 7, -- tiles per noise cell for that patchiness
  soilFloor = 0.5, -- yield multiplier at fertility 0 (the multiplier rises to 1 at fertility 1): drained land still gives about this much of base, never nothing
  fallowRate = 0.03, -- fertility regained per game day by a worked tile with no crop on it
  fallowCeiling = 0.8, -- 0..1 fertility fallow alone can reach; only legumes, compost and manure (D4, D5) take a tile higher
  pressurePerRepeat = 0.15, -- 0..1 pest pressure a harvest adds to its tile when the crop's family repeats the last one harvested there (D179)
  rotateRelief = 0.5, -- 0..1 pest pressure a harvest takes off when its family differs from the last: rotating clears it in about two harvests
  fallowRelief = 0.02, -- pest pressure shed per game day by a tile with no crop on it (a fallow tile clears in about 50 days)
  pressureCut = 0.25, -- 0..1 share of yield lost at full pest pressure (scales with pressure); under 1, so pressure alone can never zero a yield
  pestAt = 0.5, -- pest pressure from which a growing crop on the tile can be hit by a pest (and the tile card says "high")
  pestChance = 0.08, -- per game day chance of a pest hit at pressure 1 (scales with pressure) on a growing crop of a tile at or above pestAt
  pestSetback = 0.2, -- 0..1 of its growth a pest hit knocks a crop back (it never kills it)
  weedSeedChance = 0.12, -- per game day chance a thawed field tile (tilled, planned or planted) with no weeds sprouts some; one roll a tile a day on the `weeds` RNG stream, whatever the mulch
  weedStart = 0.1, -- 0..1 weed level of a fresh sprout
  weedRate = 0.1, -- weed level gained per game day by a tile that already has weeds (a nuisance in 2 days, choking in 10)
  weedCut = 0.4, -- 0..1 share of yield lost at full weeds (scales with the level); under 1, so weeds alone can never zero a yield
  weedPullAt = 0.2, -- weed level from which the idle routine pulls a tile (a player tap pulls any); pulled at 2 days old, the idle rate keeps a field clean
  weedHigh = 0.5, -- weed level from which the tile card says "high" and the Soil lens paints the tile as overgrown
  weedPullTime = 1.5, -- seconds of work to pull a tile's weeds at 1x efficiency
  poorBelow = 0.4, -- fertility under which the tile card calls the ground poor
  richFrom = 0.75, -- fertility from which the tile card calls the ground rich
}
