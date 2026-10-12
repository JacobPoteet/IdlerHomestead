-- Crops (GDD §5.3). growDays: watered game days to mature. yield/seedReturn: base amounts,
-- scaled by soil quality. Numbers are first-pass and will be tuned.
return {
  {
    id = "radish",
    name = "Radish",
    seed = "seed_radish",
    produce = "radish",
    growDays = 2,
    yield = 3,
    seedReturn = { 1, 2 },
  },
  {
    id = "potato",
    name = "Potato",
    seed = "seed_potato",
    produce = "potato",
    growDays = 5,
    yield = 4,
    seedReturn = { 1, 2 },
  },
}
