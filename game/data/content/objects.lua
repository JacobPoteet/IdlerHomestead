-- Things that sit on tiles: clutter from the messy start, trees, and the truck.
-- yields: resource -> amount, or { min, max } for a random amount.
-- autoClear: the idle homesteader clears these on its own (trees need a player order).
return {
  { id = "brush", name = "Brush", blocks = false, walkCost = 2, clearTime = 2, yields = { wood = 1 }, autoClear = true },
  { id = "rock", name = "Rock", blocks = true, clearTime = 4, yields = { stone = { 1, 3 } }, autoClear = true },
  { id = "log", name = "Fallen log", blocks = true, clearTime = 5, yields = { wood = { 3, 5 } }, autoClear = true, chop = true },
  {
    id = "junk",
    name = "Junk pile",
    blocks = true,
    clearTime = 4,
    yields = { scrap = { 1, 3 }, money = { 2, 6 } },
    autoClear = true,
  },
  { id = "tree", name = "Tree", blocks = true, clearTime = 14, yields = { wood = { 6, 9 } }, chop = true },
  {
    id = "truck",
    name = "Electric truck",
    blocks = true,
    clearable = false,
    footprintW = 2,
    footprintH = 1,
    battery = 60, -- kWh it can store (GDD §7.6)
    vehicle = true, -- charged in the truck priority tier; lends power to the homestead only above a trip reserve (tuning.power.truckReserveKwh)
    maxRate = 11, -- kW it can charge or discharge at (onboard charger)
    shelter = true, -- you sleep in the truck at first
  },
  -- Placeable equipment (bought from the catalog or part of the starting kit)
  { id = "folding_panel", name = "Folding solar panel", blocks = false, clearable = false, placeable = true, source = { curve = "solar", peak = 0.8 } },
  { id = "smoker", name = "Smoker", blocks = true, clearable = false, placeable = true, station = "smoker" },
  -- Heat & firewood (GDD §4.2, §5.3)
  { id = "campfire", name = "Campfire", blocks = true, clearable = false, placeable = true, heatSource = 1 },
  { id = "chopping_block", name = "Chopping block", blocks = true, clearable = false, placeable = true, splitter = true },
  {
    id = "woodshed",
    name = "Woodshed",
    blocks = true,
    clearable = false,
    placeable = true,
    footprintW = 2,
    station = "woodshed",
    storage = { firewood = 30, seasoned_firewood = 60 },
  },
  { id = "wood_stove", name = "Wood stove", blocks = true, clearable = false, placeable = true, heatSource = 1.6 },

  -- Power network (GDD §7.5). Sources: `source` { curve, peak kW }. Batteries: `battery` kWh.
  -- Sinks: `sink` { tier, draw kW, schedule, inertia, effects }; see data/tuning/power.lua.
  {
    id = "solar_array",
    name = "Solar array",
    blocks = true,
    clearable = false,
    placeable = true,
    footprintW = 2,
    source = { curve = "solar", peak = 3 }, -- kW in full sun; 3.75x the folding panel
  },
  {
    id = "battery_bank",
    name = "Battery bank",
    blocks = true,
    clearable = false,
    placeable = true,
    battery = 20, -- kWh
    maxRate = 6, -- kW in or out
    efficiency = 0.9, -- fraction of charging energy kept
  },
  {
    id = "wind_turbine",
    name = "Wind turbine",
    blocks = true,
    clearable = false,
    placeable = true,
    source = { curve = "wind", peak = 1.2 }, -- kW in a steady breeze; wind is strongest in winter
  },
  {
    id = "micro_hydro",
    name = "Micro-hydro",
    blocks = true,
    clearable = false,
    placeable = true,
    placeNear = "water", -- needs the creek beside it
    source = { curve = "hydro", peak = 0.6 }, -- kW, day and night; the creek runs lower in summer and under ice
  },
  {
    id = "generator",
    name = "Generator",
    blocks = true,
    clearable = false,
    placeable = true,
    -- Starts by itself when the homestead is short of power (after batteries) and burns fuel.
    source = { curve = "fuel", peak = 2, fuel = "fuel", fuelPerKwh = 0.5 }, -- kW; fuel units burned per kWh made
  },
  {
    id = "electric_heater",
    name = "Electric heater",
    blocks = true,
    clearable = false,
    placeable = true,
    -- Heats in the dark hours of cold seasons until the night's warmth need is met, then idles.
    sink = { tier = "heating", draw = 1.5, schedule = "heat", effects = { warmthPerKwh = 0.15 } },
  },
  {
    id = "lamp",
    name = "Work lamp",
    blocks = false,
    clearable = false,
    placeable = true,
    sink = { tier = "lights", draw = 0.1, schedule = "dark", effects = { studySpeed = 0.3 } }, -- study goes faster by lamplight
  },
  {
    id = "chest_freezer",
    name = "Chest freezer",
    blocks = true,
    clearable = false,
    placeable = true,
    -- Always on; fresh food spoils slower while it is powered. It stays cold for hours (inertia).
    sink = { tier = "freezer", draw = 0.15, schedule = "always", inertia = 8, effects = { spoilSlow = 3 } },
  },
}
