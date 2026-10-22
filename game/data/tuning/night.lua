-- The night (docs/PLAN_DEPTH.md §3.1, §5, M8 phases A and C). The dusk check that shows the Tonight card;
-- Footing (#341); the exposure model and the night-threat mercy knobs (C1, #355). First guesses, not balanced (balance waits
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
  exposure = { -- how much the homestead gives a night to work with (PLAN_DEPTH 5.1, D169); shared by events and night threats (C1, D187); the Tonight card shows only the word
    min = 0, -- points: the lowest exposure
    max = 10, -- points: the highest exposure; the total is clamped to min..max
    neutral = 5, -- points: a homestead with no source or guard
    chanceAtMin = 0.4, -- multiplier on a night's chance at min exposure
    chanceAtMax = 1.8, -- multiplier on a night's chance at max exposure (linear between)
    lowBelow = 3.5, -- points: below this the card says "low"
    highFrom = 6.5, -- points: from this up the card says "high"
    shelter = { truck = 2, camp = 0, shack = -2 }, -- points by the best shelter: the truck gives a night the most to work with, the shack the least
    stores = { smoked_fish = 1, cheese = 1, chicken_feed = 0.5, hay = 0.5 }, -- points added while any is in stock: stores that attract animals
    perAnimal = 0.25, -- points for each hen and goat kept
    maxLivestock = 2, -- points: ceiling on what livestock add
    guards = { -- guard id -> { points = points subtracted while it is owned (equipment or in stock), covers = { threat ids it answers } }; only a covering guard lowers that threat's own chance, all of them lower the word on the card. The cat and the predator fence act inside their handlers' own odds
      farm_dog = { points = 1.5, covers = { "fox", "raccoon", "deer", "bear" } }, -- points (D189): a dog about the place; covers must list the threats of tuning.dog.guards (a test checks it)
      lantern = { points = 1, covers = { "fox", "raccoon", "bear" } }, -- points (D191): a light by the door; covers must list the threats of tuning.lantern.guards (a test checks it)
    },
  },
  threats = { -- the night threat framework (C1, D187, PLAN_DEPTH 6.1, 6.5). First guesses, not balanced (M9)
    coolingScale = 0.5, -- multiplier (0..1) on a threat's chance while the post-bad cooldown runs (tuning.events.badCooldownNights after a threat that landed or a bad event): a landed threat is not followed by another at once
    history = 12, -- nights of resolved threats kept in the run state (older ones are dropped)
  },
  wakePenalty = 1, -- share (0..1) of the rest of a night's study lost when a wake event wakes the homesteader (D195): 1 = the night's study is gone; Tired never comes from the wake itself, only from an option the player picks
  fix = { -- the one-tap fix actions: ordinary orders, no new automation
    maxMarks = 6, -- most trees or logs one "Chop" tap marks; a larger gap marks this many and the card offers the rest next time
  },
}
