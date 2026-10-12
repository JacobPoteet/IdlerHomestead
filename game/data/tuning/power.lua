-- Power (GDD §7.5). Per-object output/storage lives in data/content/objects.lua.
-- Sunrise and sunset per season live in tuning.time.daylight.
return {
  seasonalOutput = { -- season id -> solar output multiplier (low sun, snow on the panels in winter)
    spring = 1,
    summer = 1,
    autumn = 0.85,
    winter = 0.5,
  },
}
