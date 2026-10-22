-- The farm dog (C4, #358, D189, docs/PLAN_DEPTH.md §6.1, §10.3): a companion that keeps watch on the night threats and eats
-- from the food ledger, like the cat. Every number is a first guess for the M9 balance pass.
return {
  feedHour = 18, -- in-game hour the dog eats (once a day, after the cat's meal)
  mealUnits = 1, -- units of food eaten per day, through the ledger (reason "dog"): the cheapest stocked food goes first
  mealCategories = { "food", "fish" }, -- resource categories the dog eats (preserved food is kept for the homesteader)
  keepFoodDays = 2, -- days of food (at the daily calorie need) that must stay in stock after the dog's meal: under that the dog goes hungry instead, so it never takes a meal the homesteader needs (mercy, PLAN_DEPTH 6.5)
  hungryScale = 0.5, -- multiplier (0..1) on the dog's guard while it is hungry: it still watches, a little worse; it never leaves or starves
  guards = { -- threat id -> chance (0..1) added to that threat's own guard roll while the dog is on the homestead; a threat not listed is not covered (the dog does not answer mice, which are the cat's)
    fox = 0.35, -- hens and goats: the dog is a barking second line behind the coop door and the fence
    raccoon = 0.5, -- the stores: half of the raids turn back without any bins
    deer = 0.4, -- the field's edge
    bear = 0.3, -- partly: a bear is not afraid of a dog for long, so the bear box stays the answer
  },
  postRadius = 3, -- tiles from the spawn point within which the dog lies down (the first free tile found, nearest first)
}
