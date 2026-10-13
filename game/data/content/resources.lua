-- Everything the ledger can hold (GDD §7.2).
-- calories: food energy per unit (present = edible). Food is eaten in file order, so fresher,
--   more perishable food comes first.
-- Shelf lives (how long fresh food keeps) are tuning: data/tuning/food.lua `shelfLife` (D73). value: base sale price in $.
-- keepsForWinter: fresh food that keeps well enough to count toward the winter stock (potatoes).
-- Anything with a value can be sold: stock above its keep target (D75, data/tuning/food.lua) is
-- surplus for the roadside stand and the truck load. Wood and fuel are kept for the winter by default.
-- heat: warmth per unit when burned (GDD §4.2); seasoned wood burns hotter than green.
-- capacity: storage limit until storage buildings (woodshed) raise it.
return {
  { id = "money", name = "Money", category = "currency" },
  -- D75 (#195): raw materials sell cheap, a lifeline for a broke player rather than an income: a full
  -- truck of wood (40 units) is $40, about two radish harvests.
  { id = "wood", name = "Wood", category = "material", value = 1 }, -- $ per log
  { id = "stone", name = "Stone", category = "material", value = 1 }, -- $ per unit (cleared rocks have no other use yet)
  { id = "scrap", name = "Scrap", category = "material", value = 2 }, -- $ per unit of junk metal

  { id = "seed_radish", name = "Radish seeds", category = "seed" },
  { id = "seed_potato", name = "Seed potatoes", category = "seed" },
  { id = "bait", name = "Bait", category = "supply" },

  -- Fuel (GDD §4.2, §5.3): split wood is green; a woodshed seasons it. Sellable (D75) at the price of
  -- the wood it came from, seasoned at twice that for the time it took; kept for winter by default.
  { id = "firewood", name = "Green firewood", category = "firewood", heat = 0.5, capacity = 30, value = 1 },
  { id = "seasoned_firewood", name = "Seasoned firewood", category = "fuel", heat = 1, capacity = 20, value = 2 },

  -- Stored water (GDD §5.3): pumped into cisterns, drawn by buckets and drip lines. Capacity comes
  -- only from cisterns (`storage` in objects.lua), so a pump with no cistern has nowhere to put it.
  { id = "water", name = "Water", category = "supply", capacity = 0 },

  -- Generator fuel (GDD §7.5): burned only when the homestead is short of power.
  { id = "fuel", name = "Fuel", category = "supply", capacity = 20 },

  -- Fresh fish (GDD §7.10). Ids match data/content/fish.lua.
  { id = "creek_chub", name = "Creek chub", category = "fish", calories = 250, value = 2 },
  { id = "sunfish", name = "Sunfish", category = "fish", calories = 300, value = 3 },
  { id = "brook_trout", name = "Brook trout", category = "fish", calories = 450, value = 7 },
  { id = "smallmouth_bass", name = "Smallmouth bass", category = "fish", calories = 700, value = 9 },
  { id = "channel_catfish", name = "Channel catfish", category = "fish", calories = 800, value = 8 },
  { id = "rainbow_trout", name = "Rainbow trout", category = "fish", calories = 600, value = 15 },
  { id = "golden_trout", name = "Golden trout", category = "fish", calories = 600, value = 45 },

  -- Milk (GDD §7.7, D71): goats' milk, collected from the pen's pail. The most perishable food there
  -- is (two days); a cheese press turns it into cheese. Capacity is a base cap (a full store holds the
  -- milk in the pail instead of losing it, D59).
  { id = "milk", name = "Milk", category = "dairy", calories = 250, value = 3, capacity = 24 },

  -- Fresh produce
  { id = "radish", name = "Radish", category = "food", calories = 300, value = 1 },
  { id = "potato", name = "Potato", category = "food", calories = 900, value = 2, keepsForWinter = true },
  -- Eggs (GDD §7.7, D63): laid by hens, collected from the coop's nest box. Capacity is a base cap
  -- (a full store holds the eggs in the nest instead of losing them, D59).
  { id = "egg", name = "Egg", category = "food", calories = 90, value = 2, capacity = 40 },

  -- Livestock (GDD §7.7, D63). Hens are a flock count in the ledger: their capacity is 0 until a coop
  -- is placed (`storage` in objects.lua), so a hen needs a coop, and a full coop leaves new hens waiting.
  { id = "hen", name = "Hen", category = "animal", capacity = 0, housing = "coop" },
  -- Layer feed: bought in sacks, kept in the ledger, and moved to the coop's feeder by the tend chore.
  { id = "chicken_feed", name = "Chicken feed", category = "supply", capacity = 40 },

  -- Goats (GDD §7.7, D71): a flock count like hens, housed in a goat pen. Hay is the winter feed: bought
  -- in bales, kept in the ledger, and moved to the pen's manger by the tend chore.
  { id = "goat", name = "Goat", category = "animal", capacity = 0, housing = "pen" },
  { id = "hay", name = "Hay", category = "supply", capacity = 40 },

  -- Preserved food (keeps all winter; sells for more than fresh, GDD §6.2)
  { id = "smoked_fish", name = "Smoked fish", category = "preserved", calories = 700, value = 10 },
  { id = "cheese", name = "Cheese", category = "preserved", calories = 700, value = 12 },
  { id = "canned_food", name = "Canned food", category = "preserved", calories = 1000, value = 3 },
}
