-- Conditions a routine category can wait on (GDD §7.4, D66). A category whose condition is not met
-- is skipped by the idle routine; player orders and machines ignore it. File order is the order the
-- panel cycles through them.
-- measure: what is read ("foodDays" days of food in stock, "stock" the sum of `resources` in the
--   ledger, "seasonIndex" 1 = first season of tuning.time.seasons, "hour" the in-game hour 0-24).
-- cmp: "below" (measure < value), "atleast" (measure >= value), "is" (measure == value).
-- min / max / step / default: the value the stepper buttons edit, in the unit named by `unit`.
-- short: how the panel prints the condition (%s takes the value; the season kind prints its name).
return {
  {
    id = "food_days_below",
    name = "Food below",
    measure = "foodDays",
    cmp = "below",
    min = 1,
    max = 60,
    step = 1,
    default = 10, -- days of food in stock
    unit = "days",
    short = "food < %s d",
  },
  {
    id = "food_days_atleast",
    name = "Food at least",
    measure = "foodDays",
    cmp = "atleast",
    min = 1,
    max = 60,
    step = 1,
    default = 5, -- days of food in stock
    unit = "days",
    short = "food >= %s d",
  },
  {
    id = "firewood_below",
    name = "Firewood below",
    measure = "stock",
    resources = { "firewood", "seasoned_firewood" },
    cmp = "below",
    min = 10,
    max = 200,
    step = 10,
    default = 80, -- split firewood (green and seasoned) in stock; a first winter wants roughly 70 to 140 pieces
    unit = "pieces",
    short = "firewood < %s",
  },
  {
    id = "wood_below",
    name = "Wood below",
    measure = "stock",
    resources = { "wood" },
    cmp = "below",
    min = 5,
    max = 100,
    step = 5,
    default = 30, -- wood in stock
    unit = "wood",
    short = "wood < %s",
  },
  {
    id = "season_is",
    name = "Only in season",
    measure = "seasonIndex",
    cmp = "is",
    min = 1,
    max = 4, -- as many as tuning.time.seasons (checked by the data test)
    step = 1,
    default = 1, -- spring
    unit = "season",
    short = "only in %s",
  },
  {
    id = "hour_after",
    name = "From hour",
    measure = "hour",
    cmp = "atleast",
    min = 0,
    max = 23,
    step = 1,
    default = 8, -- in-game hour of day
    unit = "hour",
    short = "from %s:00",
  },
  {
    id = "hour_before",
    name = "Until hour",
    measure = "hour",
    cmp = "below",
    min = 1,
    max = 24,
    step = 1,
    default = 16, -- in-game hour of day
    unit = "hour",
    short = "until %s:00",
  },
}
