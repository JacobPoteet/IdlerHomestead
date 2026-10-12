-- Fields & crops. Per-crop values live in data/content/crops.lua.
return {
  tillTime = 2, -- seconds of work to till a tile
  plantTime = 1, -- seconds of work to plant a tile
  waterTime = 0.8, -- seconds of work to water a tile
  harvestTime = 1.2, -- seconds of work to harvest a tile
  fetchWaterTime = 1.5, -- seconds to fill the bucket
  topUpMoisture = 0.5, -- moisture fraction (0..1) below which a player order may water a crop early
  moistureDays = 1, -- in-game days one watering keeps a tile moist
  soilYieldMin = 0.7, -- yield multiplier on the worst soil
  soilYieldMax = 1.3, -- yield multiplier on the best soil

  -- The idle routine's starter field (D61, #66): planned for the player when the routine takes over
  -- and nothing at all is planned, so an unattended start does not starve.
  starterField = { -- crop id -> tiles, in planting order; a crop with no seed or too late to ripen is skipped
    { crop = "radish", tiles = 4 }, -- tiles; the quick crop, first meals in a couple of days
    { crop = "potato", tiles = 2 }, -- tiles; the slow crop that keeps for winter
  },
  starterRadius = 10, -- tiles (Chebyshev) from the truck within which the starter field is placed
  starterWaterWeight = 1, -- score per tile of distance to the nearest water (lower score wins; the bucket walk)
  starterTruckWeight = 0.5, -- score per tile of distance to the truck
  starterSoilWeight = 4, -- score removed per 1.0 of soil quality (better soil wins ties)
  starterFrostMargin = 1, -- days of slack beyond a crop's grow time before the freeze when judging "ripens in time"
}
