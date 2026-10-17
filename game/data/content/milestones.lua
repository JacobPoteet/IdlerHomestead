-- Run milestones (GDD §4.4, D117 item 4, D163, #276/#342): a short checklist per run, ticked on the Progress panel.
-- Each is reached by an existing world event, like a Field Journal note, but they are run state (a new run starts
-- with none ticked) and carry no reward. The list is in the order a run usually reaches them.
--   name: the checklist line (<= ~4 words). hint: what to do, as an action (<= ~8 words).
--   event: the world event that reaches it. match: event field -> value, a list of values (any one of them), or
--   { min = n } / { max = n } for numbers. count: matching events needed (default 1).
return {
  {
    id = "first_harvest",
    name = "First harvest",
    hint = "Bring in a crop",
    event = "crop.harvested",
  },
  {
    id = "first_sale",
    name = "First sale",
    hint = "Sell something from the truck or the stand",
    event = "market.sold",
  },
  {
    id = "shack",
    name = "A shack",
    hint = "Raise a shack to live in",
    event = "object.placed",
    match = { object = "shack" },
  },
  {
    id = "power",
    name = "Power on",
    hint = "Put up a solar array, a turbine, a hydro or a generator",
    event = "object.placed",
    match = { object = { "solar_array", "wind_turbine", "micro_hydro", "generator" } },
  },
  {
    id = "footing",
    name = "Footing",
    hint = "Keep wood, food and water stocked for five nights",
    event = "footing.gained",
  },
  {
    id = "first_winter",
    name = "Through a winter",
    hint = "Live to the first thaw",
    event = "weather.thawed",
  },
  {
    id = "first_year",
    name = "A full year",
    hint = "Start a second year",
    event = "calendar.newSeason",
    match = { year = { min = 2 } },
  },
  {
    id = "great_winter",
    name = "The Great Winter",
    hint = "Live through the hardest winter, to its thaw",
    event = "progress.established",
  },
}
