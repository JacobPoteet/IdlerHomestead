-- Finds (GDD §8.4, D53): the options of a "pick 1 of 3" offer. Effects are data, not code:
--   effects.resources: resource -> amount added to the ledger (overflow is lost, as ever)
--   effects.objects: object id -> count added to the inventory, ready to place
--   effects.equipment: catalog equipment ids granted (a find is not offered if all are owned)
--   effects.truckCharge: kWh added to the truck battery
--   name: card title (<= ~3 words). line: what you get (<= ~8 words). icon: sprite id.
-- Selection: weight (default 1), seasons: season -> weight multiplier, minYear / maxYear,
--   lacks: when true the weight is multiplied by tuning.finds.lackBoost. One of
--   { resource = id, below = n }, { object = id } (none in the inventory or placed),
--   { equipment = id } (not owned).
-- The stray cat (D54) is the catalog's shelter cat as equipment; it is not offered once a cat is owned.
return {
  {
    id = "stray_cat",
    name = "Stray cat",
    line = "A thin tabby moves into the shed.",
    icon = "icon_cat",
    weight = 0.7,
    lacks = { equipment = "shelter_cat" },
    effects = { equipment = { "shelter_cat" } },
  },
  -- The stray dog (C4, D189) is the catalog's farm dog as equipment; it is not offered once a dog is owned.
  {
    id = "stray_dog",
    name = "Stray dog",
    line = "A lean dog follows you home.",
    icon = "icon_dog",
    weight = 0.5,
    lacks = { equipment = "farm_dog" },
    effects = { equipment = { "farm_dog" } },
  },
  {
    id = "heirloom_seeds",
    name = "Heirloom seeds",
    line = "A tin of potato and radish seed.",
    icon = "icon_seed_potato",
    weight = 1.2,
    seasons = { spring = 2.5, summer = 1, autumn = 0.4, winter = 0.2 },
    lacks = { resource = "seed_potato", below = 6 },
    effects = { resources = { seed_potato = 6, seed_radish = 8 } },
  },
  {
    id = "used_panel",
    name = "Used solar panel",
    line = "A folding panel, ready to place.",
    icon = "icon_folding_panel",
    weight = 0.8,
    lacks = { object = "folding_panel" },
    effects = { objects = { folding_panel = 1 } },
  },
  {
    id = "junk_with_goods",
    name = "Rusty toolbox",
    line = "Scrap and wood from a junk heap.",
    icon = "icon_scrap",
    weight = 1.2,
    lacks = { resource = "scrap", below = 4 },
    effects = { resources = { scrap = 6, wood = 5 } },
  },
  {
    id = "bait_tin",
    name = "Bait tin",
    line = "Ten fresh baits for the rod.",
    icon = "icon_bait",
    weight = 1,
    seasons = { spring = 1.5, summer = 1.5, autumn = 1, winter = 0.6 },
    lacks = { resource = "bait", below = 3 },
    effects = { resources = { bait = 10 } },
  },
  {
    id = "dusty_cans",
    name = "Dusty cans",
    line = "Five cans, still sealed.",
    icon = "icon_canned_food",
    weight = 1,
    seasons = { spring = 0.8, summer = 0.8, autumn = 1.4, winter = 1.8 },
    lacks = { resource = "canned_food", below = 3 },
    effects = { resources = { canned_food = 5 } },
  },
  {
    id = "dry_stack",
    name = "Dry stack",
    line = "Ten dry logs, left behind.",
    icon = "icon_wood",
    weight = 0.9,
    seasons = { spring = 0.6, summer = 0.6, autumn = 1.8, winter = 2 },
    lacks = { resource = "wood", below = 4 },
    effects = { resources = { wood = 10 } },
  },
  {
    id = "rusty_axe",
    name = "Old axe",
    line = "Dull, but it felled trees once.",
    icon = "icon_axe",
    weight = 0.7,
    lacks = { equipment = "axe" },
    effects = { equipment = { "axe" } },
  },
  {
    id = "jump_pack",
    name = "Jump pack",
    line = "Some charge for the truck battery.",
    icon = "icon_battery",
    weight = 0.7,
    effects = { truckCharge = 2 },
  },
  {
    id = "loose_cash",
    name = "Coffee can cash",
    line = "Folded bills in a coffee can.",
    icon = "icon_money",
    weight = 0.8,
    effects = { resources = { money = 25 } },
  },
}
