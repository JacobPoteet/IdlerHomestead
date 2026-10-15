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
  treeThreshold = 0.66, -- noise value above which trees grow (higher = fewer trees)
  treeMinDistance = 8, -- tiles from the truck before trees appear
  soilNoiseScale = 8, -- tiles per noise cell for soil quality
  soilCreekBonus = 0.2, -- added soil quality on tiles beside any water (fertile banks)

  -- Tributary: a second, narrower stream from a side edge that runs into the main creek.
  tributaryChance = 0.85, -- chance a plot has one
  tributaryMinWidth = 1, -- tiles
  tributaryMaxWidth = 2, -- tiles
  tributaryWanderChance = 0.45, -- per column, chance it shifts a row
  tributaryRoadGap = 9, -- rows; nearest it may enter to the road row, so it never runs through the truck yard
  tributaryEdgeMargin = 0.12, -- fraction of map height kept clear above and below where it starts
  tributaryFords = 1, -- shallow crossings along it

  -- Ponds: still water blobs away from the creek, the road and the truck.
  pondMin = 2, -- fewest ponds on a plot
  pondMax = 4, -- most ponds on a plot
  pondMinRadius = 2.5, -- tiles; smallest pond (half its width)
  pondMaxRadius = 5, -- tiles; largest pond
  pondSquash = 0.7, -- shortest height as a fraction of width, so ponds are not all round
  pondLobes = 0.22, -- 0..1 how lumpy the shore is (0 = a clean ellipse)
  pondWaterGap = 3, -- tiles; open bank kept between a pond and other water, the road and the map edge
  pondTruckMin = 9, -- tiles; nearest a pond may be to the truck
  pondTruckMax = 36, -- tiles; farthest a pond may be from the truck (a pond within a short walk is a feature, not a trek)
  pondAttempts = 40, -- tries to find room for each pond before giving up on it
  marshChance = 0.5, -- chance a pond is a marsh: shallows round its rim and thick brush on its banks
  marshShallowChance = 0.55, -- per rim tile of a marsh, chance it is a ford-deep shallow
  marshBrushChance = 0.4, -- per bank tile within marshBrushReach of a marsh, chance of brush
  marshBrushReach = 2, -- tiles from a marsh's water

  -- Land cover: big soft zones from low-frequency noise.
  woodlandNoiseScale = 22, -- tiles per noise cell for the woodland field (large: woods and meadows)
  woodlandShift = 0.3, -- how far the tree threshold moves between the thickest wood and the barest meadow
  groveDensity = 0.8, -- chance a tile that passes the grove test actually grows a tree (thins the woods so they have gaps)
  meadowBelow = 0.38, -- woodland value under which land is an open meadow
  meadowTrees = 0.01, -- per meadow tile, chance of a lone tree
  meadowClutter = 0.4, -- multiple of the background clutter chance in a meadow
  meadowSoilBonus = 0.12, -- added soil quality in a meadow
  speciesNoiseScale = 9, -- tiles per noise cell for tree species patches
  speciesMix = 0.2, -- chance a tree ignores its patch's species and is a plain oak
  pineAbove = 0.62, -- species value above which a stand is pine
  birchBelow = 0.3, -- species value below which a stand is birch
  birchWaterReach = 7, -- tiles from water within which birches are favoured
  birchWaterChance = 0.6, -- chance a tree near water is a birch

  -- Clearings: round gaps in the woods, with a log or two at the edge.
  clearingMin = 2, -- fewest clearings on a plot
  clearingMax = 4, -- most clearings on a plot
  clearingMinRadius = 3, -- tiles
  clearingMaxRadius = 5, -- tiles
  clearingLogChance = 0.08, -- per tile on the clearing's rim, chance of a fallen log
  clearingSoilBonus = 0.1, -- added soil quality inside (woodland loam)

  -- Boulder fields: patches of rock scattered over poor ground.
  boulderFieldMin = 1, -- fewest boulder fields on a plot
  boulderFieldMax = 3, -- most boulder fields on a plot
  boulderMinRadius = 3, -- tiles
  boulderMaxRadius = 6, -- tiles
  boulderDensity = 0.55, -- chance of a rock per tile at a field's heart (falls off to the edge)
  boulderSoilPenalty = 0.25, -- subtracted soil quality inside
  boulderTruckMin = 10, -- tiles; nearest a field may be to the truck (the start is not walled in)
}
