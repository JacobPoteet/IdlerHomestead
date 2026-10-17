-- The night (docs/PLAN_DEPTH.md §3.1, §5, M8 phase A). So far the dusk check that shows the Tonight card;
-- the Footing and night-threat knobs arrive with their slices. First guesses, not balanced (balance waits
-- for M9).
return {
  duskLeadHours = 4, -- in-game hours before sunset at which the Tonight card opens by itself (4 h is about 53 s at 1x: time to act on a gap, such as to fell two trees at 14 s each); the card stays until bedtime, can be dismissed and is re-opened from the Tonight stamp or the T key
  snapLookDays = 2, -- days ahead (0 = tonight) a cold snap already on the forecast shows as a risk on the card; the forecast reveals it late, so this only decides how soon the card says so
  fix = { -- the one-tap fix actions: ordinary orders, no new automation
    maxMarks = 6, -- most trees or logs one "Chop" tap marks; a larger gap marks this many and the card offers the rest next time
  },
}
