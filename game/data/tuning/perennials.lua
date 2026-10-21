-- Perennials (PLAN_DEPTH 8.5, D183). Every number is a reasoned first guess for the M9 balance pass.
-- Berries and orchard trees (data/content/crops.lua, `perennial`) are planted once. A plant gives its first, small
-- crop in its fruiting season after the one it was planted in, and a full crop once it has been through one winter.
-- A young plant (not yet through a winter) needs wrapping before the freeze and is a deer and bear target; every plant
-- needs pruning after a harvest or its next crop is smaller. The first fruit year is documented in the GDD (D183).
return {
  firstYieldShare = 0.4, -- share of a full crop a plant gives in its first, young year
  unprunedCut = 0.3, -- share of a crop lost when the plant was not pruned since its last harvest (a share, so never zero)
  pruneTime = 2, -- seconds of work to prune a plant at 1x efficiency
  wrapTime = 1.5, -- seconds of work to wrap a young plant against the frost at 1x efficiency
  wrapLead = 5, -- days before the freeze from which the routine wraps young plants (a player tap wraps any time)
  youngFrostKill = 0.5, -- chance an unwrapped young plant is killed by the freeze (the frostGuard stat turns part aside)
}
