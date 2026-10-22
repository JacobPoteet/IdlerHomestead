-- Night raiders (C2 + C3, #356, D188, docs/PLAN_DEPTH.md §6.1): the raccoon at the stores, deer and rabbits at the field
-- edge and the black bear at the smoker's and feed stores. The framework (tuning.night: exposure, mercy) scales every
-- chance here; a guard in the counter's catalog item turns a raid back. Every number is a first guess for the M9 balance
-- pass. Rule behind all of it (D184): damage is a share of one store or a share of a few tiles' yield, never a death.
return {
  mercy = { -- the reserve rule shared by the raiders of the stores (PLAN_DEPTH 6.5)
    keepFoodDays = 2, -- days of food in stock (at the daily calorie need) a raid never takes the homesteader under: a raccoon or a bear cannot take the meal the next days need
  },
  raccoon = { -- spring to autumn (content seasons): a raccoon opens a food store and spoils part of one kind
    hour = 22, -- in-game hour tonight's raid lands (a raccoon is out before the small hours)
    firstDay = 6, -- days; no raccoon before this day of the run
    chancePerDay = 0.2, -- probability per night (before exposure and the mercy scale) that a raccoon comes while there is food to take
    yearScale = { 1 }, -- multiplier on the chance by year of the run (the last repeats): the same every year
    maxTiles = 1, -- picks drawn at dusk for the raid (a store raid needs one: which store)
    targetCategories = { "food", "dairy" }, -- resource categories it eats at: fresh produce, eggs, milk
    targetResources = { "chicken_feed", "hay" }, -- resource ids it scatters as well: a day or two of feed
    lossFraction = 0.4, -- share of the one store it picks that a landed raid spoils
    minLoss = 1, -- units, floor of a raid's loss (when there is anything to take)
    maxLoss = 6, -- units, ceiling of a raid's loss: a mercy cap so a big larder is never wiped
    maxGuard = 0.95, -- ceiling on the chance the lidded bins turn a raid back (no defence is perfect)
  },
  deer = { -- spring to autumn: deer and rabbits browse the crops at the field's edge
    hour = 23, -- in-game hour tonight's raid lands
    firstDay = 8, -- days; no browsing before this day of the run (before then there is little in the ground)
    yearScale = { 1 }, -- multiplier on the chance by year of the run (the last repeats): the same every year
    chancePerDay = 0.12, -- probability per night (before exposure and the mercy scale) that deer come while a crop stands on the edge
    shareOfEdge = 0.25, -- share of the edge's unripe crops a landed raid browses (rounded up, at least one)
    maxTiles = 3, -- tiles, ceiling on one raid: a mercy cap so a night never strips a field
    browseCut = 0.4, -- share (0..1, below 1) of a browsed crop's harvest that is lost: it still ripens and still gives something
    maxGuard = 0.95, -- ceiling on the chance the scarecrow turns a raid back
  },
  bear = { -- autumn only (content seasons): a black bear feeding up strips one of the foods that smell
    hour = 23, -- in-game hour tonight's raid lands
    firstDay = 8, -- days; no bear before this day of the run
    chancePerDay = 0.3, -- probability per autumn night (before the year scale, exposure and the mercy scale) that a bear comes while there is a store to strip
    yearScale = { 0.3, 1 }, -- multiplier on the chance by year of the run (the last repeats): a bear is rare in year 1 and common after
    maxTiles = 1, -- picks drawn at dusk for the raid (a store raid needs one: which store)
    targetCategories = {}, -- resource categories it strips (none: it wants only the listed stores)
    targetResources = { "smoked_fish", "cheese", "chicken_feed", "hay" }, -- resource ids it will strip (there is no honey yet)
    lossFraction = 0.6, -- share of the one store it picks that a landed raid takes
    minLoss = 1, -- units, floor of a raid's loss (when there is anything to take)
    maxLoss = 10, -- units, ceiling of a raid's loss: a mercy cap so a full store is never wiped
    maxGuard = 0.95, -- ceiling on the chance the bear box turns a raid back
  },
}
