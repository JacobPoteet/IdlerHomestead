-- Weather & winter (GDD §4.1, §7.9). Each year rolls its own winter; autumn forecasts it.
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
  powerInputs = { -- placeholder weather inputs to the power network until day-to-day weather exists (#39)
    cloud = 0, -- 0..1 share of sunlight blocked by cloud (solar output is multiplied by 1 - cloud)
    wind = 1, -- multiplier on turbine output on top of the wind model
    flow = 1, -- multiplier on micro-hydro output (rain and drought)
  },
  iceCutTime = 6, -- seconds of work to cut a hole in the creek ice (holes stay open all winter)
}
