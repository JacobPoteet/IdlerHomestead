-- The supply catalog (GDD §6.3). Bought with money; delivered next morning (fee) or picked up
-- on a truck trip. In M3 most entries become learnable through the Field Journal; `starter`
-- entries are always known.
--   gives: resources added on arrival. object: a placeable object added to your inventory.
--   equipment: an item kept for the run whose `modifiers` adjust stats (see src/sim/stats.lua).
--   pickupOnly: can only be bought on a truck trip.
return {
  { id = "radish_seeds", name = "Radish seeds x5", page = "seeds", price = 4, starter = true, gives = { seed_radish = 5 } },
  { id = "potato_seeds", name = "Seed potatoes x3", page = "seeds", price = 6, starter = true, gives = { seed_potato = 3 } },
  { id = "canned_food", name = "Canned food x2", page = "supplies", price = 7, starter = true, gives = { canned_food = 2 } },
  { id = "bait", name = "Bait x6", page = "fishing", price = 3, starter = true, gives = { bait = 6 } },
  {
    id = "basic_rod",
    name = "Basic rod",
    page = "fishing",
    price = 10,
    starter = true,
    equipment = true,
    modifiers = { rod = 1 },
  },
  { id = "smoker", name = "Smoker", page = "preserving", price = 30, starter = true, object = "smoker" },
  {
    id = "sturdy_rod",
    name = "Sturdy rod",
    page = "fishing",
    price = 25,
    starter = true,
    equipment = true,
    modifiers = { rod = 1, maxTension = 0.25, reelSpeed = 0.15 },
  },
  {
    id = "big_bucket",
    name = "Big bucket",
    page = "tools",
    price = 12,
    starter = true,
    equipment = true,
    modifiers = { bucketCapacity = 4 },
  },
  {
    id = "used_panel",
    name = "Used solar panel",
    page = "power",
    price = 40,
    starter = true,
    pickupOnly = true,
    object = "folding_panel",
  },
}
