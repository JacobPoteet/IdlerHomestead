-- Survival needs (GDD §4.2).
return {
  dailyCalories = 2000, -- calories the homesteader eats each day
  conditionMax = 100, -- full health
  hungerDamage = 25, -- condition lost on a day with no food at all (scaled by the shortfall)
  dailyRecovery = 10, -- condition regained on a fully fed, warm day
  dailyWarmth = { -- season id -> warmth needed per night (1 = one seasoned firewood in a campfire)
    spring = 0.5,
    summer = 0,
    autumn = 2,
    winter = 4,
  },
  coldDamage = 20, -- condition lost on a night with no warmth at all (scaled by the shortfall)
}
