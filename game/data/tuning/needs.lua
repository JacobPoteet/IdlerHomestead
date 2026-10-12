-- Survival needs (GDD §4.2).
return {
  dailyCalories = 2000, -- calories the homesteader eats each day
  conditionMax = 100, -- full health
  hungerDamage = 25, -- condition lost on a day with no food at all (scaled by the shortfall)
  dailyRecovery = 10, -- condition regained on a fully fed day
}
