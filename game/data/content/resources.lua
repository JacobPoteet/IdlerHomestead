-- Everything the ledger can hold (GDD §7.2).
-- calories: food energy per unit (present = edible). Food is eaten in file order, so fresher,
--   more perishable food comes first.
-- spoilDays: average days before a unit spoils (absent = keeps). value: base sale price in $.
-- keepsForWinter: fresh food that keeps well enough to count toward the winter stock (potatoes).
-- autoSell: non-food goods that go to the sell crate by default.
-- heat: warmth per unit when burned (GDD §4.2); seasoned wood burns hotter than green.
-- capacity: storage limit until storage buildings (woodshed) raise it.
return {
  { id = "money", name = "Money", category = "currency" },
  { id = "wood", name = "Wood", category = "material", value = 1 },
  { id = "stone", name = "Stone", category = "material" },
  { id = "scrap", name = "Scrap", category = "material", value = 2, autoSell = true },

  { id = "seed_radish", name = "Radish seeds", category = "seed" },
  { id = "seed_potato", name = "Seed potatoes", category = "seed" },
  { id = "bait", name = "Bait", category = "supply" },

  -- Fuel (GDD §4.2, §5.3): split wood is green; a woodshed seasons it.
  { id = "firewood", name = "Green firewood", category = "firewood", heat = 0.5, capacity = 30 },
  { id = "seasoned_firewood", name = "Seasoned firewood", category = "fuel", heat = 1, capacity = 20 },

  -- Fresh fish (GDD §7.10). Ids match data/content/fish.lua.
  { id = "creek_chub", name = "Creek chub", category = "fish", calories = 250, spoilDays = 2, value = 2 },
  { id = "sunfish", name = "Sunfish", category = "fish", calories = 300, spoilDays = 2, value = 3 },
  { id = "brook_trout", name = "Brook trout", category = "fish", calories = 450, spoilDays = 2, value = 7 },
  { id = "smallmouth_bass", name = "Smallmouth bass", category = "fish", calories = 700, spoilDays = 2, value = 9 },
  { id = "channel_catfish", name = "Channel catfish", category = "fish", calories = 800, spoilDays = 2, value = 8 },
  { id = "rainbow_trout", name = "Rainbow trout", category = "fish", calories = 600, spoilDays = 2, value = 15 },
  { id = "golden_trout", name = "Golden trout", category = "fish", calories = 600, spoilDays = 2, value = 45 },

  -- Fresh produce
  { id = "radish", name = "Radish", category = "food", calories = 300, spoilDays = 4, value = 1 },
  { id = "potato", name = "Potato", category = "food", calories = 900, spoilDays = 20, value = 2, keepsForWinter = true },

  -- Preserved food (keeps all winter; sells for more than fresh, GDD §6.2)
  { id = "smoked_fish", name = "Smoked fish", category = "preserved", calories = 700, value = 10 },
  { id = "canned_food", name = "Canned food", category = "preserved", calories = 1000, value = 3 },
}
