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
  -- D160: the daily drinking-water need (GDD §4.2). It is drawn from the ledger "water" stock (the cistern,
  -- the same pool as irrigation) first, then from the canteen the homesteader fills by hand. A dry day
  -- builds Thirst slowly (like hunger and cold, never instant death): the damage grows with each dry day in a row.
  dailyWater = 1, -- water units the homesteader drinks each day (one unit = one crop watering, so a day's drink is a small share of a cistern)
  thirstDamage = 15, -- condition lost on the first day with no water at all (scaled by the shortfall; hunger 25, cold 20: thirst starts gentler and builds)
  thirstBuild = 0.5, -- extra share of thirstDamage added for each dry day already in a row (0.5: day 2 hurts 1.5x, day 3 2x)
  thirstBuildDays = 3, -- dry days in a row after which the damage stops growing (the multiplier is 1 + thirstBuild x this at most)
  canteenCapacity = 3, -- water units the canteen holds (three days of drinking); a new run starts with it full
  drinkRefillDays = 2, -- days of drinking water on hand (cistern plus canteen) below which the homesteader goes to fill the canteen
  meltYield = 3, -- water units one melt of snow makes (fills a canteen; winter fallback beside the fire, costs meltWood)
  meltWood = 1, -- wood burned to melt one batch of snow (the fallback is never free: it competes with the night's warmth)
  meltTime = 4, -- seconds of work to gather and melt one batch of snow at a fire
}
