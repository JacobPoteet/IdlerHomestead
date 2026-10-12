-- Growing-season threats and escalation (GDD §4.1, §7.9, D3, D67). What each threat does lives
-- with the threat in data/content/threats.lua; this file holds the per-year curves and the global
-- knobs. A curve is a list indexed by year; years past its end use the last entry plus `...PerYear`.
return {
  count = { 1, 2, 3 }, -- threats scheduled per year, by year (year 1 gets one gentle threat, never in spring)
  countPerYear = 0, -- extra threats per year past the end of `count` (capped by how many kinds exist)
  strength = { 0.4, 0.8, 1 }, -- multiplier on every threat's damage share and drying rate, by year (year 1 is gentle)
  strengthPerYear = 0.1, -- added to the last `strength` entry for each year past the end of the list
  maxStrength = 1.6, -- ceiling on the strength multiplier however many years go by
  maxShare = 0.9, -- ceiling on the share of crops one threat can hit, after strength (something always survives)
  maxGuard = 0.9, -- ceiling on how much of a threat a countermeasure stat can turn aside (0..1)
  firstSeason = { 2, 1 }, -- by year: earliest season index (1 = spring) a threat may start; year 1 waits for summer
  warnDays = 3, -- days of warning before a threat starts (toast and forecast hint); the weather-sense stat adds more
  likelyAt = 0.5, -- strike chance (0..1) of a forecast day at or above which the forecast pill says "<threat> likely"
  gapDays = 1, -- days kept free between two threats of the same year (they are pushed later, or dropped if no room)
  historyLimit = 12, -- finished threats remembered in the run state (for summaries)

  winter = { -- harsher winters per year, on top of D37's severity growth (weather.lua severityPerYear)
    snapDaysPerYear = 0.5, -- cold-snap nights added per year after the first (rounded down: one more night every two years)
    maxExtraSnapDays = 2, -- most extra cold-snap nights the yearly growth can add
  },
}
