-- Simulation clock & calendar.
return {
  tickRate = 20, -- simulation ticks per second of game time
  maxTicksPerFrame = 400, -- cap on catch-up ticks in one frame; backlog beyond this is dropped
  debugTimeScales = { 1, 2, 5, 10, 30 }, -- time-scale steps cycled by the debug speed key
  speedSteps = { 0, 1, 2, 4 }, -- player game-speed multipliers cycled by the speed button/key; 0 = paused (GDD D42)
  defaultSpeed = 1, -- multiplier a session starts at (one of speedSteps)
  dayLength = 320, -- seconds of game time per in-game day (at 1x); was 128 before D56, first pass to tune from play
  legacyDayLength = 128, -- seconds; the day length saves without a recorded one were written with (rescaled on load, D56)
  sleepSpeed = 8, -- sim speed multiplier applied automatically while the homesteader is asleep (D56); the player's speed still caps a pause at 0
  skipSpeed = 60, -- sim speed multiplier while "skip night" is on; it ends the moment the homesteader wakes (D56)
  daysPerSeason = 7, -- in-game days per season (7 x 320s = ~37 min awake-and-asleep at 1x, about 27 min with fast sleep; GDD §4.1, D56)
  seasons = { "spring", "summer", "autumn", "winter" }, -- season ids in order
  startHour = 6, -- in-game hour a new run begins
  daylight = { -- season id -> { sunrise hour, sunset hour }; solar follows it, study happens outside it
    spring = { 6, 20 },
    summer = { 5, 21 },
    autumn = { 7, 19 },
    winter = { 8, 17 },
  },
}
