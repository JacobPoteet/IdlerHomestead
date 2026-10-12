-- Roadside stand (GDD §6.4, D52). A placed stand sells a few goods from the sell crate each day.
return {
  baseCap = 6, -- items per day a bare stand can sell (before season and weather)
  maxCap = 18, -- items per day, hard ceiling however many upgrades are owned (the stand is always capped)
  priceFraction = 0.6, -- share of the town (truck) price the stand pays per item; below 1 so the trip stays the big payday
  sellHour = 17, -- in-game hour the day's customers come by (the day's sale happens once, then)
  seasonFlow = { -- season id -> multiplier (at most 1) on the daily cap: foot traffic on the road
    spring = 1,
    summer = 1,
    autumn = 0.9,
    winter = 0.5,
  },
  weatherFlow = { -- weather kind -> multiplier (at most 1) on the daily cap; nobody stops in a storm
    clear = 1,
    cloudy = 0.9,
    rain = 0.5,
    windy = 0.8,
    storm = 0.25,
  },
}
