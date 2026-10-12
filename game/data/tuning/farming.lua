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
}
