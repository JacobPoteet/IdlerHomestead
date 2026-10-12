-- Mice and the cat (GDD §7.7, D54). Mice nibble the stored food; a cat catches them.
return {
  mice = { -- night raids on the stored food
    raidHour = 23, -- in-game hour the day's mouse raid is rolled (once a day, at night)
    firstDay = 6, -- days; no mice before this day of the run
    chancePerDay = 0.3, -- probability per day (before season and weather) that mice come
    seasons = { -- season id -> multiplier on chancePerDay; mice want the harvest and a warm shed
      spring = 0.8,
      summer = 0.7,
      autumn = 1.4,
      winter = 1.2,
    },
    targetCategories = { "food" }, -- resource categories mice eat (fresh produce); cans, fish and seed are safe
    lossFraction = 0.1, -- share of the stored target units one raid ruins
    minLoss = 1, -- units, floor of one raid's loss (when there is anything to take)
    maxLoss = 6, -- units, ceiling of one raid's loss
  },
  cat = { -- the cat that answers them
    walkSpeed = 1.6, -- tiles per second
    wanderRadius = 7, -- tiles from the spawn point the cat roams
    idleSeconds = { min = 4, max = 14 }, -- game seconds the cat sits before its next move (a day is 128 s)
    napSeconds = { min = 12, max = 30 }, -- game seconds a nap in a sunny spot lasts (an in-game hour is ~5 s)
    napChance = 0.5, -- probability that the next move is toward a sunny spot rather than a random tile
    sunnyTries = 8, -- random tiles sampled when looking for a sunny spot
    shadeRadius = 1, -- tiles; a spot with a tree this close is shaded, not sunny
    fedCatch = 0.8, -- probability a raid is caught while the cat has been fed
    hungryCatch = 0.4, -- probability a raid is caught while the cat is hungry (it still hunts for itself)
    bondCatch = 0.02, -- added to the catch probability per point of bond
    maxBond = 5, -- points; one point per day the cat is petted
    feedHour = 18, -- in-game hour the cat eats (once a day)
    mealCategories = { "fish" }, -- resource categories the cat eats; the cheapest stocked fish goes first
    mealUnits = 1, -- units eaten per day
  },
}
