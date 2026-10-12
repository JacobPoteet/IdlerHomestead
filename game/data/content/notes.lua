-- Field Journal notes (GDD §8.1): specific things the player experienced, written automatically
-- when a world event happens. Notes persist across runs (per save slot) and unlock ideas: catalog
-- entries list the notes they need in `needs`.
--   name: label on the journal map (<= ~3 words). line: what the note says (<= ~8 words).
--   icon: sprite id for the stamp. event: the world event that writes it.
--   match: event field -> value that must be equal, or { min = n } / { max = n } for numbers.
--   count: matching events needed before the note is written (default 1).
return {
  {
    id = "first_catch",
    name = "First catch",
    line = "Landed my first fish.",
    icon = "icon_creek_chub",
    event = "fish.caught",
  },
  {
    id = "ten_fish",
    name = "Ten fish",
    line = "Ten fish out of this creek.",
    icon = "icon_rod",
    event = "fish.caught",
    count = 10,
  },
  {
    id = "one_got_away",
    name = "Got away",
    line = "One got away. Need stronger line.",
    icon = "icon_rod",
    event = "fish.lost",
  },
  {
    id = "fish_spoil",
    name = "Fish spoil",
    line = "Fish go bad in two days.",
    icon = "icon_spoiled",
    event = "food.spoiled",
    match = { category = "fish" },
  },
  {
    id = "produce_spoils",
    name = "Produce rots",
    line = "Fresh vegetables don't keep long.",
    icon = "icon_seed_radish",
    event = "food.spoiled",
    match = { category = "food" },
  },
  {
    id = "first_harvest",
    name = "First harvest",
    line = "Pulled my first crop.",
    icon = "icon_seed_potato",
    event = "crop.harvested",
  },
  {
    id = "bucket_hauling",
    name = "Heavy buckets",
    line = "So many trips to the creek.",
    icon = "icon_water",
    event = "task.completed",
    match = { task = "fetch_water" },
    count = 12,
  },
  {
    id = "went_hungry",
    name = "Went hungry",
    line = "Went to bed hungry.",
    icon = "icon_heart",
    event = "needs.ate",
    match = { shortfall = { min = 0.001 } },
  },
  {
    id = "first_trip",
    name = "Town trip",
    line = "Town buys what I grow and catch.",
    icon = "icon_battery",
    event = "market.trip",
  },
  {
    id = "first_smoke",
    name = "Smoked fish",
    line = "Smoked fish keeps for months.",
    icon = "icon_smoked_fish",
    event = "processing.done",
  },
}
