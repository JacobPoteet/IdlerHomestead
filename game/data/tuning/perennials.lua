-- Perennials (PLAN_DEPTH 8.5, D183). Every number is a reasoned first guess for the M9 balance pass.
-- Berries and orchard trees (data/content/crops.lua, `perennial`) are planted once. A plant gives its first, small
-- crop in its fruiting season after the one it was planted in, and a full crop once it has been through one winter.
-- The first fruit year is documented in the GDD (D183).
return {
  firstYieldShare = 0.4, -- share of a full crop a plant gives in its first, young year
}
