-- Simulation clock & calendar.
return {
  tickRate = 20, -- simulation ticks per second of game time
  maxTicksPerFrame = 400, -- cap on catch-up ticks in one frame; backlog beyond this is dropped
  debugTimeScales = { 1, 2, 5, 10, 30 }, -- time-scale steps cycled by the debug speed key
  dayLength = 128, -- seconds of game time per in-game day (at 1x)
  daysPerSeason = 7, -- in-game days per season (7 x 128s = ~15 min, GDD §4.1)
  seasons = { "spring", "summer", "autumn", "winter" }, -- season ids in order
  startHour = 6, -- in-game hour a new run begins
}
