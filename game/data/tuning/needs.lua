-- Survival needs (GDD §4.2).
return {
  -- D56: days became 2.5x longer (tuning.time.dayLength), so the player does more work per day. The
  -- per-day demands below were raised (calories x1.5, warmth x2) so a day of survival costs about the
  -- same real play time as before; harness numbers in docs/BALANCE.md.
  dailyCalories = 3000, -- calories the homesteader eats each day (was 2000 before D56)
  conditionMax = 100, -- full health
  hungerDamage = 25, -- condition lost on a day with no food at all (scaled by the shortfall)
  dailyRecovery = 10, -- condition regained on a fully fed, warm day
  dailyWarmth = { -- season id -> warmth needed per night (1 = one seasoned firewood in a campfire); doubled in D56
    spring = 1,
    summer = 0,
    autumn = 4,
    winter = 8,
  },
  coldDamage = 20, -- condition lost on a night with no warmth at all (scaled by the shortfall)
}
