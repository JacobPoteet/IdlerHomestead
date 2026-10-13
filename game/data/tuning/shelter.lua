-- Shelter ladder (GDD §5.3, D82). Per-shelter numbers (insulation, sleep recovery, heater radius,
-- study bonus) are content fields on the shelter objects in data/content/objects.lua; only the
-- knobs shared by all shelters live here.
return {
  farHeat = 0.6, -- fraction (0..1) of a heat source's warmth that reaches the sleeping spot when the source stands beyond the shelter's heaterRadius
  defaultInsulation = 1, -- multiplier on the night's warmth need with no shelter at all (1 = no help)
  defaultRecovery = 1, -- multiplier on the daily Condition recovery with no shelter at all
}
