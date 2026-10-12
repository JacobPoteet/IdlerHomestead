-- Chickens (GDD §7.7, D63): needs, eggs, the chores and night predators. Coop sizes live in
-- data/content/objects.lua (`coop`, `storage`); prices in the catalog.
return {
  hens = { -- the flock: needs, laying and chores
    careHour = 17, -- in-game hour the flock eats and drinks for the day (dusk, as it heads into the coop)
    layHour = 9, -- in-game hour the day's eggs are laid (once a day)
    feedPerHen = 0.5, -- feed units one hen eats a day when it finds nothing for itself
    waterPerHen = 0.2, -- water units one hen drinks a day
    feedShare = { -- season id -> share of feedPerHen the hens need from the feeder (the rest is foraged); winter has no forage
      spring = 0.5,
      summer = 0.3,
      autumn = 0.5,
      winter = 1,
    },
    layChance = { -- season id -> probability one well-fed hen lays on a day (short days lay little)
      spring = 0.85,
      summer = 0.8,
      autumn = 0.5,
      winter = 0.25,
    },
    hungryLay = 0.2, -- lay-chance multiplier for a flock that ate nothing (scales up to 1 as it eats its fill)
    thirstyLay = 0.1, -- lay-chance multiplier for a flock that found the waterer dry
    hungryBelow = 0.5, -- share (0..1) of the day's feed or water need met under which the day counts as hungry or dry
    topUpBelow = 0.9, -- share of the feeder or waterer at or under which a player tap still tops it up
    starveAfter = 4, -- consecutive hungry days before a hen is lost each further day (forgiving: the grace is days, not hours)
    thirstAfter = 2, -- consecutive dry days before a hen is lost each further day (thirst is quicker than hunger)
    tendBelow = 0.5, -- share of the feeder or waterer under which the idle routine goes to refill it
    collectMin = 3, -- eggs in the nest box before the idle routine makes a trip just for them (a player tap takes any)
    tendTime = 3, -- seconds of work to tend the coop (collect eggs, top up feeder and waterer)
  },
  predators = { -- foxes and the like, at night
    hour = 23, -- in-game hour the night's raid is rolled (once a night)
    firstDay = 4, -- days; no raids before this day of the run
    chancePerDay = 0.25, -- probability per night (before season, weather and the cat) that a predator comes while hens are kept
    seasons = { -- season id -> multiplier on chancePerDay; lean seasons make foxes bold
      spring = 1,
      summer = 0.8,
      autumn = 1.2,
      winter = 1.5,
    },
    catFactor = 0.6, -- multiplier on the chance while the cat is on the homestead (it patrols and warns)
    maxGuard = 0.95, -- ceiling on the chance the coop and fence turn a raid back (no defence is perfect)
    loss = { min = 1, max = 2 }, -- hens an unstopped raid takes
  },
}
