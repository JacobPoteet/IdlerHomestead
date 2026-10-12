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

  -- Water ladder (GDD §5.3, §7.4). `placeOn = "waterTable"`: needs a tile with groundwater close to
  -- the surface. `waterSource { fillTime }`: a place to fill the bucket (seconds of work, against
  -- tuning.farming.fetchWaterTime at the creek); `stored` draws from the cistern stock instead of
  -- the ground. `pump { rate }`: cistern units per in-game hour at full power. `drip { radius }`:
  -- waters thirsty crops within that many tiles from the cistern, with no actor.
  {
    id = "well",
    name = "Dug well",
    blocks = true,
    clearable = false,
    placeable = true,
    placeOn = "waterTable",
    waterSource = { fillTime = 1.2 }, -- lowering a bucket on a rope; no walk to the creek, but not quick
  },
  {
    id = "hand_pump",
    name = "Hand pump",
    blocks = true,
    clearable = false,
    placeable = true,
    placeOn = "waterTable",
    waterSource = { fillTime = 0.6 }, -- a few strokes of the handle; works through the winter, no power
  },
  {
    id = "cistern",
    name = "Cistern",
    blocks = true,
    clearable = false,
    placeable = true,
    footprintW = 2,
    storage = { water = 60 }, -- cistern units (one bucket slot, or two drip waterings, each)
    waterSource = { fillTime = 0.4, stored = true }, -- turn the tap; the stock is shared by every cistern
  },
  {
    id = "dc_pump",
    name = "Solar pump",
    blocks = true,
    clearable = false,
    placeable = true,
    placeOn = "waterTable",
    -- Fills the cistern while there is room, scaled by how well the pumps tier is powered.
    sink = { tier = "pumps", draw = 0.4, schedule = "fill", fills = "water" },
    pump = { rate = 5 },
  },
  -- Roadside stand (GDD §6.4). `placeNear = "road"`: beside the road, never on it. `stand`: sells
  -- from the sell crate each day; see tuning.stand and src/sim/systems/stand.lua.
  {
    id = "roadside_stand",
    name = "Roadside stand",
    blocks = true,
    clearable = false,
    placeable = true,
    footprintW = 2,
    placeNear = "road",
    stand = true,
  },
  -- Hen house (GDD §7.7, D63). `storage`: houses six hens (the ledger's "hen" count). `coop`: the nest
  -- box holds laid eggs until collected, the feeder and waterer hold what the hens use between chores,
  -- and `guard` is the chance the latched door turns back a night predator; see tuning.animals.
  {
    id = "chicken_coop",
    name = "Chicken coop",
    blocks = true,
    clearable = false,
    placeable = true,
    footprintW = 2,
    offRoad = true,
    storage = { hen = 6 },
    coop = { nest = 12, feeder = 12, waterer = 4, guard = 0.6 },
  },
  -- Goat pen (GDD §7.7, D71): a fenced yard with a shed. `storage`: houses three goats and stacks twenty
  -- more hay. `pen`: the pail holds milk until collected, the manger holds hay and the trough water
  -- between chores, and `guard` is the chance the fence and gate turn back a night predator.
  {
    id = "goat_pen",
    name = "Goat pen",
    blocks = true,
    clearable = false,
    placeable = true,
    footprintW = 2,
    footprintH = 2,
    offRoad = true,
    storage = { goat = 3, hay = 20 },
    pen = { pail = 8, manger = 18, trough = 6, guard = 0.5 },
  },
  { id = "cheese_press", name = "Cheese press", blocks = true, clearable = false, placeable = true, station = "cheese_press" },
  {
    id = "drip_line",
    name = "Drip line",
    blocks = false,
    clearable = false,
    placeable = true,
    drip = { radius = 2 }, -- tiles each way, so a 5x5 patch
  },
  -- Machines (GDD §7.4, D65): stationary actors on the task board. `machine`: which task categories
  -- (and optionally which task ids) it may claim, how far it reaches and how fast it works; its
  -- `sink` (schedule "demand") draws power only while it has work. See src/sim/systems/machines.lua.
  {
    id = "auto_harvester",
    name = "Auto-harvester",
    blocks = true,
    clearable = false,
    placeable = true,
    sink = { tier = "machines", draw = 0.5, schedule = "demand" }, -- kW while it has ripe crops to pick (about 0.08 kWh a crop)
    machine = {
      categories = { "harvest" }, -- task categories it may claim
      radius = 3, -- tiles each way (Chebyshev), so a 7x7 patch around it
      workSpeed = 0.6, -- work seconds per second at full power (the idle homesteader does 0.8, but walks)
    },
  },
}
