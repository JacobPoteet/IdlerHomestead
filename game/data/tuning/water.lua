-- Water automation ladder (GDD §5.3, §7.4). Per-object numbers (fill times, pump rate, drip radius,
-- cistern size, prices) live in data/content/objects.lua and catalog.lua.
return {
  table = { -- the water table: how close groundwater is to the surface, per tile (0..1), seeded per run
    noiseScale = 9, -- tiles per noise cell for the groundwater pattern
    creekWeight = 0.3, -- share of a tile's table that comes from nearness to the creek (the rest is noise)
    creekReach = 7, -- tiles from the creek over which that nearness fades to nothing
    minForWell = 0.5, -- table value (0..1) a tile needs before a well or pump can be sunk there
    shallow = 0.7, -- table value (0..1) at or above which the tile is described as "high" in the object card
  },
  dripUnitsPerWatering = 0.5, -- cistern units a drip line spends to water one crop (a bucket spends 1, so drip wastes less)
  pumpBatch = 1, -- cistern units a pump accumulates before it adds them (keeps the ledger from changing every tick)
  lowFraction = 0.2, -- cistern fill fraction (0..1) below which it is shown as low
}
