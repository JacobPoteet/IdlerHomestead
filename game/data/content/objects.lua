-- Things that sit on tiles: clutter from the messy start, trees, and the truck.
-- yields: resource -> amount, or { min, max } for a random amount.
-- autoClear: the idle homesteader clears these on its own (trees need a player order).
return {
  { id = "brush", name = "Brush", blocks = false, walkCost = 2, clearTime = 2, yields = { wood = 1 }, autoClear = true },
  { id = "rock", name = "Rock", blocks = true, clearTime = 4, yields = { stone = { 1, 3 } }, autoClear = true },
  { id = "log", name = "Fallen log", blocks = true, clearTime = 5, yields = { wood = { 3, 5 } }, autoClear = true },
  {
    id = "junk",
    name = "Junk pile",
    blocks = true,
    clearTime = 4,
    yields = { scrap = { 1, 3 }, money = { 2, 6 } },
    autoClear = true,
  },
  { id = "tree", name = "Tree", blocks = true, clearTime = 14, yields = { wood = { 6, 9 } } },
  {
    id = "truck",
    name = "Electric truck",
    blocks = true,
    clearable = false,
    footprintW = 2,
    footprintH = 1,
    battery = 60, -- kWh it can store (GDD §7.6)
  },
  -- Placeable equipment (bought from the catalog or part of the starting kit)
  { id = "folding_panel", name = "Folding solar panel", blocks = false, clearable = false, placeable = true, powerOutput = 0.8 },
  { id = "smoker", name = "Smoker", blocks = true, clearable = false, placeable = true, station = "smoker" },
}
