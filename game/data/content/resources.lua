-- Everything the ledger can hold. GDD §7.2.
return {
  { id = "money", name = "Money", category = "currency" },
  { id = "wood", name = "Wood", category = "material" },
  { id = "stone", name = "Stone", category = "material" },
  { id = "scrap", name = "Scrap", category = "material" },

  { id = "seed_radish", name = "Radish seeds", category = "seed" },
  { id = "seed_potato", name = "Seed potatoes", category = "seed" },

  -- Food is eaten in this order (fresh first, canned last). calories: per unit.
  { id = "radish", name = "Radish", category = "food", calories = 300 },
  { id = "potato", name = "Potato", category = "food", calories = 900 },
  { id = "canned_food", name = "Canned food", category = "food", calories = 1000 },
}
