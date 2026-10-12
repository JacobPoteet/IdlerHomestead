-- Simulation clock & calendar.
return {
  tickRate = 20, -- simulation ticks per second of game time
  maxTicksPerFrame = 400, -- cap on catch-up ticks in one frame; backlog beyond this is dropped
  debugTimeScales = { 1, 2, 5, 10, 30 }, -- time-scale steps cycled by the debug speed key
  speedSteps = { 0, 1, 2, 4 }, -- player game-speed multipliers cycled by the speed button/key; 0 = paused (GDD D42)
  defaultSpeed = 1, -- multiplier a session starts at (one of speedSteps)
  dayLength = 128, -- seconds of game time per in-game day (at 1x)
  daysPerSeason = 7, -- in-game days per season (7 x 128s = ~15 min, GDD §4.1)
  seasons = { "spring", "summer", "autumn", "winter" }, -- season ids in order
  startHour = 6, -- in-game hour a new run begins
  daylight = { -- season id -> { sunrise hour, sunset hour }; solar follows it, study happens outside it
    spring = { 6, 20 },
    summer = { 5, 21 },
    autumn = { 7, 19 },
    winter = { 8, 17 },
  },
}
