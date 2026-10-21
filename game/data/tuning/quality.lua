-- Crop quality (PLAN_DEPTH 8.6, D182). Every number is a reasoned first guess for the M9 balance pass.
-- A harvest is graded into a tier from the tile's fertility, its weeds, how long the crop stood thirsty and whether the
-- player tended it (a hand order to water it or pull its weeds). The routine reaches `good` at best: `excellent` needs a
-- tended mark as well as a clean score, and only the player's own orders put one on.
return {
  tiers = { "normal", "good", "excellent" }, -- tier ids, worst first (the rank of a tier is its place here)
  priceMult = { -- tier -> multiplier on the produce's sale price (town and stand)
    normal = 1, -- x
    good = 1.25, -- x
    excellent = 1.6, -- x
  },
  weightFertility = 0.4, -- share of the penalty the tile's missing fertility (1 - fertility) carries
  weightWeeds = 0.3, -- share of the penalty the weed level at harvest carries
  weightWater = 0.3, -- share of the penalty the crop's thirst carries
  thirstTolerance = 0.25, -- share of a crop's grow time it may stand dry before its water penalty is full (the routine's walking lag stays well under it)
  goodMax = 0.15, -- the crop's quality sensitivity x its penalty (0..1) at or under which the harvest is good
  excellentMax = 0.05, -- the same figure at or under which a tended harvest is excellent (an untended one is never above good)
  tendsNeeded = 1, -- hand orders (watering or weeding the crop) that give it the tended mark
}
