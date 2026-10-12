-- Growing-season threats (GDD §4.1, §7.9, D67). Each year rolls a few of these (tuning.threats
-- curves); each one writes its own Field Journal note when it strikes, and that note makes its
-- countermeasure (a catalog equipment item) an idea. Effects are a small data vocabulary applied by
-- src/sim/systems/threats.lua: `damage` (crops hit once) or `drought` (crops dry fast for a spell).
-- `strike` makes a threat weather-driven: it may land on any day of its span, more likely on stormy
-- days (Weather.threat), and the forecast shows which days are risky.
return {
  {
    id = "hail",
    name = "Hail",
    line = "Storm hail shreds leaves and knocks crops back.",
    icon = "icon_hail",
    season = "summer",
    startDays = { 2, 4 },
    span = { 3, 4 },
    hour = 15,
    minYear = 1,
    weight = 1,
    guard = "hailGuard",
    counter = "hail_netting",
    strike = { chance = 0.12, weatherPower = 3 }, -- clear 12%, windy ~21%, storm 96% a day
    damage = { share = 0.6, setback = 0.6, ripe = true, unripe = true },
  },
  {
    id = "drought",
    name = "Drought",
    line = "Hot dry days: beds dry out fast.",
    icon = "icon_drought",
    season = "summer",
    startDays = { 1, 5 },
    span = { 3, 4 },
    hour = 10,
    minYear = 1,
    weight = 1,
    guard = "droughtGuard",
    counter = "straw_mulch",
    drought = { dryRate = 3, witherHours = 10 },
  },
  {
    id = "locusts",
    name = "Locusts",
    line = "A swarm strips crops to the stalk.",
    icon = "icon_locust",
    season = "summer",
    startDays = { 3, 7 },
    span = { 1, 1 },
    hour = 13,
    minYear = 2,
    weight = 1,
    guard = "pestGuard",
    counter = "row_covers",
    damage = { share = 0.5, kill = true, ripe = true, unripe = true },
  },
  {
    id = "early_frost",
    name = "Early frost",
    line = "A hard frost kills unripe crops.",
    icon = "icon_frost",
    season = "autumn",
    startDays = { 2, 5 },
    span = { 1, 1 },
    hour = 5,
    minYear = 1,
    weight = 0.8,
    guard = "frostGuard",
    counter = "frost_cloth",
    damage = { share = 0.6, kill = true, ripe = false, unripe = true },
  },
}
