-- Starting loadouts (D201, #386, docs/PLAN_DEPTH.md 12.3): a bundle of existing items for a new run, with a small
-- penalty elsewhere. Chosen on the recovery screen (Choose land, then Starting kit), never required: the default is
-- the standard start. A loadout is available once the Journal node `unlock` is known (a catalog item or a perk).
--   name, line: the card (line <= ~8 words, what it brings). penaltyLine: what it costs, in words.
--   startingResources: added to the starting stock. penalty: resource -> amount taken off the starting stock
--   (never below zero). startingEquipment: catalog equipment ids owned at the start.
--   startingObjects: placeable object ids put beside the truck. truckCharge: kWh in the truck battery.
--   The numbers are first guesses; M9 balances (the plan's open question is a floor on Footing by run 5, D170 Q15).
return {
  {
    id = "angler",
    name = "Angler",
    line = "A sturdy rod and six more bait.",
    penaltyLine = "Two fewer cans of food.",
    unlock = "sturdy_rod",
    startingEquipment = { "sturdy_rod" },
    startingResources = { bait = 6 },
    penalty = { canned_food = 2 },
  },
  {
    id = "gardener",
    name = "Gardener",
    line = "Lettuce, bean and carrot seed to start.",
    penaltyLine = "Two fewer logs of wood.",
    unlock = "carrot_seeds",
    startingResources = { seed_lettuce = 6, seed_beans = 6, seed_carrot = 6 },
    penalty = { wood = 2 },
  },
  {
    id = "herder",
    name = "Herder",
    line = "A coop beside the truck, two hens and feed.",
    penaltyLine = "Four dollars less to start.",
    unlock = "hens",
    startingObjects = { "chicken_coop" },
    startingResources = { hen = 2, chicken_feed = 10 },
    penalty = { money = 4 },
  },
  {
    id = "lumberjack",
    name = "Lumberjack",
    line = "An axe and eight more logs.",
    penaltyLine = "Three dollars less to start.",
    unlock = "axe",
    startingEquipment = { "axe" },
    startingResources = { wood = 8 },
    penalty = { money = 3 },
  },
  {
    id = "tinkerer",
    name = "Tinkerer",
    line = "The truck arrives charged, with a spare solar panel.",
    penaltyLine = "Three dollars less to start.",
    unlock = "used_panel",
    truckCharge = 12,
    startingObjects = { "folding_panel" },
    penalty = { money = 3 },
  },
}
