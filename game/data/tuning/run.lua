-- What a fresh run starts with (before Field Journal perks, GDD §4.3).
return {
  startingResources = { -- resource id -> amount
    seed_radish = 10,
    seed_potato = 6,
    canned_food = 4,
    bait = 4,
    seasoned_firewood = 3,
  },
  startingEquipment = { "basic_rod" }, -- catalog equipment ids owned at the start
  startingObjects = { "folding_panel", "campfire", "chopping_block" }, -- placed next to the truck at the start of a run
}
