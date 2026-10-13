-- What a fresh run starts with (before Field Journal perks, GDD §4.3).
return {
  startingResources = { -- resource id -> amount
    seed_radish = 10,
    seed_potato = 6,
    canned_food = 6, -- D68 (#161): two more cans than before, so the first days are less of a countdown
    money = 6, -- D68 (#161): starting $; buys bait ($3 + $3 delivery), or radish seeds once the first junk is sold
    bait = 4,
    wood = 4, -- 3 warmth at heat 0.75 (was 3 seasoned firewood)
  },
  startingEquipment = { "basic_rod" }, -- catalog equipment ids owned at the start
  startingObjects = { "folding_panel", "campfire" }, -- placed next to the truck at the start of a run
}
