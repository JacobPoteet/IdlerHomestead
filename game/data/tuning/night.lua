-- The night (docs/PLAN_DEPTH.md §3.1, §5, M8 phase A). So far the dusk check that shows the Tonight card;
-- Footing (#341); the night-threat knobs arrive with their slices. First guesses, not balanced (balance waits
-- for M9).
return {
  duskLeadHours = 4, -- in-game hours before sunset at which the Tonight card opens by itself (4 h is about 53 s at 1x: time to act on a gap, such as to fell two trees at 14 s each); the card stays until bedtime, can be dismissed and is re-opened from the Tonight stamp or the T key
  snapLookDays = 2, -- days ahead (0 = tonight) a cold snap already on the forecast shows as a risk on the card; the forecast reveals it late, so this only decides how soon the card says so
  footing = { -- Footing (D162, #341, PLAN_DEPTH §3.2), judged once a day at sunset. First guesses, not balanced (M9)
    fuelNights = 3, -- nights of wood (at tonight's need) that must be in stock for a night to count toward Footing
    foodDays = 3, -- days of food (at the daily calorie need) that must be in stock for a night to count toward Footing
    waterDays = 1, -- days of drinking water (cistern plus canteen) that must be in hand for a night to count: the water source test
    streakNights = 5, -- good nights in a row that earn Footing; a night that is not good starts the count again
    slipFuelNights = 1, -- nights of wood below which held Footing slips (less than fuelNights, so a small dip is not a slip)
    slipFoodDays = 1, -- days of food below which held Footing slips (less than foodDays, for the same reason)
    regainNights = 2, -- good nights in a row that regain slipped Footing; a night that is not good starts the count again
  },
  fix = { -- the one-tap fix actions: ordinary orders, no new automation
    maxMarks = 6, -- most trees or logs one "Chop" tap marks; a larger gap marks this many and the card offers the rest next time
  },
}
