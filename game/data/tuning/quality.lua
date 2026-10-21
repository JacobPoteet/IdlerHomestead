-- Crop quality (PLAN_DEPTH 8.6, D182, D185). Every number is a reasoned first guess for the M9 balance pass.
-- A harvest is graded into a tier from the tile's fertility, its weeds and how long the crop stood thirsty. There is no
-- tended mark: healthy soil, a weeded bed and steady water earn `fine`, and the idle routine does all three.
return {
  tiers = { "normal", "fine" }, -- tier ids, worst first (the rank of a tier is its place here)
  priceMult = { -- tier -> multiplier on the produce's sale price (town and stand)
    normal = 1, -- x
    fine = 1.3, -- x
  },
  weightFertility = 0.4, -- share of the penalty the tile's missing fertility (1 - fertility) carries
  weightWeeds = 0.3, -- share of the penalty the weed level at harvest carries
  weightWater = 0.3, -- share of the penalty the crop's thirst carries
  thirstTolerance = 0.25, -- share of a crop's grow time it may stand dry before its water penalty is full (the routine's walking lag stays well under it)
  fineMax = 0.15, -- the crop's quality sensitivity x its penalty (0..1) at or under which the harvest is fine
}
