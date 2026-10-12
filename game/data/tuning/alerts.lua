-- Warnings and the winter-readiness indicator (D70, #157, #166). Read by systems/alerts.lua and
-- systems/readiness.lua; the HUD takes its chip colours from the same accessors.
return {
  checkInterval = 1, -- game seconds between looks at food, fuel and condition (a look is cheap; once a second is plenty)
  foodAmberDays = 2, -- days of food in stock under which the food chip turns amber and a warning toast shows
  foodRedDays = 1, -- days of food in stock under which the food chip turns red (the next midnight leaves a shortfall)
  fuelAmberNights = 2, -- nights of fuel (warmth in stock / tonight's need) under which the firewood chip turns amber
  fuelRedNights = 1, -- nights of fuel under which the firewood chip turns red (tonight is short)
  conditionAmber = 70, -- condition (health) under which the heart chip turns amber
  conditionRed = 40, -- condition under which the heart chip turns red and a warning toast shows
  readinessLeadDays = 7, -- days before the first frozen season from which the winter-readiness pill shows (7 = from autumn on; raise it to show it in late summer)
}
