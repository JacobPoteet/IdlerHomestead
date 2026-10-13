-- Survival needs (GDD §4.2, D104).
return {
  -- D56: days became 2.5x longer (tuning.time.dayLength), so the player does more work per day. The
  -- per-day demands below were raised (calories x1.5, warmth x2) so a day of survival costs about the
  -- same real play time as before; harness numbers in docs/BALANCE.md.
  dailyCalories = 3000, -- calories the homesteader eats each day (was 2000 before D56)
  conditionMax = 100, -- full health
  hungerDamage = 25, -- condition lost on a day with no food at all (scaled by the shortfall)
  dailyRecovery = 10, -- condition regained on a fully fed, warm day
  -- D104: the night's warmth need is one smooth curve over the year (a night is read at the middle of
  -- its day), not four steps. Warmth 1 = one unit of heat 1 burned at efficiency 1.
  warmthPeak = 8, -- warmth a full winter night needs at severity 1, no cold snap and no shelter insulation (doubled in D56)
  warmthCurve = { -- { year fraction, share of warmthPeak }, piecewise linear; 0 = start of spring, 1 = end of winter; the two ends must match (the year wraps)
    { 0.00, 0.20 }, -- first spring night: the thaw still bites
    { 0.10, 0.10 },
    { 0.20, 0.00 }, -- late spring: no fire needed
    { 0.50, 0.00 }, -- all summer (0.25 to 0.50) is warm: no fire, no warmth need
    { 0.60, 0.25 }, -- autumn: a real but partial need; a night out in the cold costs health
    { 0.75, 0.65 }, -- first winter night (the frozen season, severity applies from here)
    { 0.80, 1.00 },
    { 0.92, 1.00 }, -- deep winter: the full need
    { 1.00, 0.20 }, -- the thaw
  },
  coldDamage = 20, -- condition lost on a night with no warmth at all (scaled by the shortfall)
}
