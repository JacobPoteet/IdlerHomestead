-- Weather & winter (GDD §4.1, §7.1, §7.9). Each year rolls its own winter; autumn forecasts it.
-- Day-to-day weather (D51) is a seeded run of spells on top of that.
return {
  frozenSeasons = { "winter" }, -- season ids when the ground and creek freeze (no growth, frost kills crops)
  severityMin = 0.9, -- winter warmth-need multiplier, lowest roll in year 1
  severityMax = 1.3, -- winter warmth-need multiplier, highest roll in year 1
  severityPerYear = 0.2, -- added to both ends of the roll for each year after the first (harsher winters)
  severityLevels = { 1.05, 1.25 }, -- multiplier thresholds between forecast words: mild | hard | brutal
  snapStartMin = 3, -- earliest day of winter the cold snap begins
  snapStartMax = 6, -- latest day of winter the cold snap begins
  snapDaysMin = 1, -- shortest cold snap, in days
  snapDaysMax = 3, -- longest cold snap, in days
  snapMultiplier = 2, -- warmth need multiplier on cold-snap nights (on top of the severity)
  forecastDays = { 2, 4, 6 }, -- autumn days revealing forecast pieces: severity, snap timing, snap length
  iceCutTime = 6, -- seconds of work to cut a hole in the creek ice (holes stay open all winter)

  -- Day-to-day weather. The sky is a queue of whole days rolled ahead from the "sky" RNG stream:
  -- each spell is one kind lasting a few days, picked by season weight x transition from the last spell.
  startKind = "clear", -- weather on the first day of a run (and for an older save loaded without a sky)
  frozenRainKind = "cloudy", -- kind a rainy day becomes when it lands in a frozen season (snow is the winter look)
  queueDays = 8, -- days of weather rolled ahead, including today (must cover forecastHorizon + the weather-sense lead)
  forecastHorizon = 3, -- days past today the forecast shows (the weather-sense stat adds more)
  kinds = { -- weather kind -> its effects (fields below)
    -- label: shown to the player. cloud: 0..1 share of sunlight blocked (solar x (1 - cloud)).
    -- wind: turbine multiplier on top of the wind model. flow: micro-hydro multiplier (rain swells the creek).
    -- fish: fish activity multiplier (1 = normal; more means quicker bites and better odds).
    -- rainfall: 0 = dry, otherwise a multiplier on rainWaterRate and it waters every crop (not while frozen).
    -- threat: multiplier on mice, predator and weather-driven threat (hail) odds (GDD §7.9, D54, D64, D67).
    -- days: shortest and longest spell of this kind, in whole days.
    clear = { label = "Clear", cloud = 0, wind = 1, flow = 1, fish = 1, rainfall = 0, threat = 1, days = { 1, 3 } },
    cloudy = { label = "Cloudy", cloud = 0.4, wind = 1, flow = 1, fish = 1.15, rainfall = 0, threat = 1, days = { 1, 2 } },
    rain = { label = "Rain", cloud = 0.6, wind = 1, flow = 1.3, fish = 1.4, rainfall = 1, threat = 1, days = { 1, 2 } },
    windy = { label = "Windy", cloud = 0.15, wind = 1.5, flow = 1, fish = 0.8, rainfall = 0, threat = 1.2, days = { 1, 2 } },
    storm = { label = "Storm", cloud = 0.8, wind = 1.7, flow = 1.5, fish = 0.6, rainfall = 1.5, threat = 2, days = { 1, 1 } },
  },
  order = { "clear", "cloudy", "rain", "windy", "storm" }, -- kinds in rolling order (keeps rolls deterministic)
  seasonWeights = { -- season id -> kind -> relative chance a new spell is this kind (0 = never)
    spring = { clear = 3, cloudy = 2, rain = 3, windy = 1, storm = 0.5 },
    summer = { clear = 5, cloudy = 2, rain = 1.5, windy = 1, storm = 1 },
    autumn = { clear = 2, cloudy = 3, rain = 3, windy = 2, storm = 0.5 },
    winter = { clear = 3, cloudy = 4, rain = 0, windy = 2, storm = 0 }, -- no rain on frozen ground
  },
  transitions = { -- last kind -> next kind -> multiplier on the season weight (weather moves in believable steps)
    clear = { clear = 0.5, cloudy = 1.5, rain = 0.5, windy = 1, storm = 0.3 },
    cloudy = { clear = 1, cloudy = 0.5, rain = 1.8, windy = 1, storm = 0.8 },
    rain = { clear = 0.6, cloudy = 1.8, rain = 0.5, windy = 0.6, storm = 0.8 },
    windy = { clear = 1.5, cloudy = 1.2, rain = 0.8, windy = 0.3, storm = 0.8 },
    storm = { clear = 0.8, cloudy = 1.8, rain = 0.8, windy = 1.2, storm = 0 },
  },
  rainWaterRate = 6, -- cistern units gathered per in-game hour of rain (times the kind's rainfall), if a cistern is placed
}
