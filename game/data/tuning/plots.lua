-- Plot preview at the start of a new run (D200, #384, docs/PLAN_DEPTH.md 12.1). After a rescue the player may
-- look at three offered plots before heading out. Each is a real seed; its traits are read off the land it would
-- make. Choosing is optional: Head out without choosing takes the first plot. These are first guesses (M9 balances).
return {
  offered = 3, -- plots shown in the offer
  traitRadius = 16, -- tiles round the truck that soil, sun, rocks and brush are read over (the first days' working ground)
  woodRadius = 24, -- tiles round the truck that trees are counted over (a wood is worth a short walk)
  shadeReach = 2, -- tiles; a tile this close to a tree counts as shaded for the sun trait

  -- Each trait is shown as a level 1 to 3 (Poor, Fair, Good). A value at or above thresholds[n] reaches level n + 1;
  -- `lowIsGood = true` flips it, so that a value at or below the threshold reaches the higher level.
  soil = { thresholds = { 0.55, 0.6 }, lowIsGood = false }, -- mean soil quality (0..1) of the tillable tiles in traitRadius
  water = { thresholds = { 12, 8 }, lowIsGood = true }, -- tiles from the truck to the nearest water
  wood = { thresholds = { 200, 320 }, lowIsGood = false }, -- trees within woodRadius
  sun = { thresholds = { 0.52, 0.65 }, lowIsGood = false }, -- share (0..1) of tiles in traitRadius clear of tree shade

  -- Hazards, tested in this order; the first that fits is the plot's one hazard, and none fits an easy plot.
  -- `bonus` is a small extra starting stock that comes with the hard plot, so the safest plot is not always the pick.
  hazards = { -- list of { id, name, line, test = { trait, atLeast }, bonus }; the order is the order tested
    {
      id = "far_water",
      name = "Far from water",
      line = "A long walk to the creek.",
      test = { trait = "waterTiles", atLeast = 15 }, -- tiles from the truck to water
      bonus = { money = 4 },
    },
    {
      id = "rocky",
      name = "Stony ground",
      line = "Boulders to clear before the first rows.",
      test = { trait = "rocks", atLeast = 30 }, -- rocks within traitRadius
      bonus = { stone = 6 },
    },
    {
      id = "thicket",
      name = "Overgrown",
      line = "Brush and logs everywhere.",
      test = { trait = "clutter", atLeast = 95 }, -- brush and logs within traitRadius
      bonus = { wood = 4 },
    },
  },

  -- The words on the plot card (docs/PLAN_DEPTH.md 12.1). Level words run from level 1 to level 3.
  words = { -- text shown to the player (no units); level words run from level 1 to level 3
    title = "Choose your land",
    intro = "Three plots to start on. Look them over, or just head out: the first one is fine.",
    footer = "Every plot has a creek, a road and the same old truck. Your knowledge comes with you.",
    done = "Done",
    plotNames = { "Plot A", "Plot B", "Plot C" },
    chosen = "Chosen",
    default = "Taken if you head out", -- on the first plot while nothing is chosen
    soil = { label = "Soil", levels = { "Thin", "Fair", "Rich" } },
    water = { label = "Water", levels = { "Far", "Fair", "Close" } },
    wood = { label = "Wood", levels = { "Sparse", "Some", "Plenty" } },
    sun = { label = "Sun", levels = { "Shady", "Mixed", "Bright" } },
    easy = "Easy start. No trouble to speak of.",
    hazard = "Rougher start: %s. %s Comes with %s.", -- hazard name, its line, the bonus
    landLine = "Land: %s", -- on the recovery screen, the plot Head out will take
    chooseButton = "Choose land",
  },
}
