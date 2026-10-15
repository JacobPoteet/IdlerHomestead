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

  -- Biomes: the map is cut into regions (cells round random points, edges warped by noise) and each region is
  -- one biome, so a pinewood is pines, a meadow is open, and the plot reads as places, not scatter.
  biomeCellsMin = 10, -- fewest regions on a plot
  biomeCellsMax = 14, -- most regions on a plot
  biomeWarpScale = 12, -- tiles per noise cell that bends the region edges
  biomeWarp = 7, -- tiles the region edges wander from straight lines
  biomeEdgeBlend = 4, -- tiles; within this of an edge a tile may take the next region's look (a soft edge, not a wall)
  startBiome = "meadow", -- the region the truck sits in: open and kind, never a thicket
  -- Per biome: weight = odds a spare region is this biome (each biome gets one region before weights apply);
  -- wood = a forest (clearings go here); treeThreshold = tree-noise value above which trees grow (1 = none);
  -- density = chance such a tile grows one; lone = chance of a lone tree where none grow; species = relative
  -- odds of each tree object; rocks / brush = chance per tile of a rock / brush; clutter = multiple of the
  -- ordinary clutter chance; soil = added soil quality.
  biomes = { -- biome id -> its look (fields above); the ids are only names for the regions
    meadow = {
      weight = 3,
      wood = false,
      treeThreshold = 1,
      density = 0,
      lone = 0.012,
      species = { tree = 1 },
      rocks = 0,
      brush = 0.01,
      clutter = 0.4,
      soil = 0.12,
    },
    oakwood = {
      weight = 3,
      wood = true,
      treeThreshold = 0.42,
      density = 0.62,
      lone = 0,
      species = { tree = 9, birch = 1 },
      rocks = 0,
      brush = 0.03,
      clutter = 1,
      soil = 0.04,
    },
    pinewood = {
      weight = 2,
      wood = true,
      treeThreshold = 0.4,
      density = 0.66,
      lone = 0,
      species = { pine = 9, tree = 1 },
      rocks = 0.02,
      brush = 0,
      clutter = 0.8,
      soil = -0.04,
    },
    birchgrove = {
      weight = 2,
      wood = true,
      treeThreshold = 0.5,
      density = 0.5,
      lone = 0,
      species = { birch = 9, tree = 1 },
      rocks = 0,
      brush = 0.05,
      clutter = 0.7,
      soil = 0.06,
    },
    scrub = {
      weight = 1.5,
      wood = false,
      treeThreshold = 0.78,
      density = 0.35,
      lone = 0.01,
      species = { tree = 2, pine = 1 },
      rocks = 0.01,
      brush = 0.2,
      clutter = 1,
      soil = 0,
    },
    rocky = {
      weight = 1.5,
      wood = false,
      treeThreshold = 0.72,
      density = 0.4,
      lone = 0,
      species = { pine = 3, tree = 1 },
      rocks = 0.14,
      brush = 0.02,
      clutter = 0.6,
      soil = -0.2,
    },
  },

  -- Clearings: round gaps inside the woods, with a log or two on the rim.
  clearingMin = 2, -- fewest clearings on a plot
  clearingMax = 4, -- most clearings on a plot
  clearingMinRadius = 3, -- tiles
  clearingMaxRadius = 5, -- tiles
  clearingLogChance = 0.08, -- per tile on the clearing's rim, chance of a fallen log
  clearingSoilBonus = 0.1, -- added soil quality inside (woodland loam)
}
