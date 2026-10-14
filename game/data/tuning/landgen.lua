-- Random homestead generation (GDD §7.3). Fractions are of the map width/height unless noted.
return {
  creekMinX = 0.15, -- fraction of map width; leftmost start of the creek
  creekMaxX = 0.85, -- fraction of map width; rightmost start of the creek
  creekMinWidth = 2, -- tiles
  creekMaxWidth = 3, -- tiles
  creekWanderChance = 0.35, -- per row, chance the creek shifts a tile sideways
  creekWidthChangeChance = 0.08, -- per row, chance the creek widens or narrows by a tile
  fordCount = 2, -- shallow crossings over the creek
  roadMinRow = 0.35, -- fraction of map height; highest row the road may enter on
  roadMaxRow = 0.65, -- fraction of map height; lowest row the road may enter on
  roadWobbleChance = 0.15, -- per tile, chance the road steps up or down a row
  roadMinLength = 10, -- tiles; shortest road in from the map edge
  truckCreekGapMin = 6, -- tiles; nearest the road's end (the truck) may be to the creek
  truckCreekGapMax = 22, -- tiles; farthest the truck may be from the creek, so water stays a short walk on a wide map (#260)
  truckClearRadius = 3, -- tiles around the truck kept free of clutter
  messRadius = 12, -- tiles around the truck where the messy start is concentrated
  messDensity = 0.45, -- chance of clutter per tile right next to the clear zone (falls off with distance)
  backgroundClutter = 0.05, -- chance of clutter per tile far from the truck
  clutterWeights = { brush = 6, rock = 2, log = 1.5, junk = 1 }, -- relative odds of each clutter object
  junkRadius = 6, -- tiles around the truck where junk piles can appear
  treeNoiseScale = 7, -- tiles per noise cell for tree clusters
  treeThreshold = 0.62, -- noise value above which trees grow (higher = fewer trees)
  treeMinDistance = 8, -- tiles from the truck before trees appear
  soilNoiseScale = 8, -- tiles per noise cell for soil quality
  soilCreekBonus = 0.2, -- added soil quality on tiles beside the creek (fertile banks)
}
