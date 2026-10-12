-- Field schemas for each content kind (see src/core/registry.lua for the spec format).
-- Unknown fields in content files are rejected, so add new fields here first.
return {
  resources = {
    name = "string", -- display name
    category = "string", -- currency | material | seed | food | ...
    capacity = "number?", -- default storage cap; absent means unlimited until storage buildings set one
    calories = "number?", -- food energy per unit; present means it can be eaten
    spoilDays = "number?", -- average days until a unit spoils; absent = keeps
    value = "number?", -- base sale price in $; absent = can't be sold
    autoSell = "boolean?", -- non-food goods sent to the sell crate by default
  },
  terrain = {
    name = "string",
    walkable = "boolean", -- can actors stand on it
    tillable = "boolean?", -- can be tilled into a field
    water = "boolean?", -- buckets can be filled here
    walkCost = "number?", -- movement cost multiplier (default 1)
  },
  objects = {
    name = "string",
    blocks = "boolean", -- blocks movement
    walkCost = "number?", -- movement cost multiplier when not blocking (default 1)
    clearTime = "number?", -- seconds of work to clear (absent with clearable = false)
    clearable = "boolean?", -- default true
    yields = "table?", -- resource -> amount or { min, max } when cleared
    autoClear = "boolean?", -- idle homesteader clears it without an order
    footprintW = "number?", -- tiles wide (default 1); anchored at the top-left tile
    footprintH = "number?", -- tiles tall (default 1)
    placeable = "boolean?", -- can be placed by the player from inventory
    powerOutput = "number?", -- peak kW in full sun (solar)
    battery = "number?", -- kWh of storage
    station = "string?", -- processor station id used by recipes (e.g. "smoker")
  },
  crops = {
    name = "string",
    seed = "string", -- resource consumed to plant
    produce = "string", -- resource gained on harvest
    growDays = "number", -- watered game days to mature
    yield = "number", -- base produce per harvest, scaled by soil
    seedReturn = "table", -- { min, max } seeds back per harvest
  },
  fish = {
    name = "string",
    rarity = "string", -- common | uncommon | rare | legendary
    idle = "boolean?", -- can be caught by the idle routine
    weight = "number", -- relative bite odds
    seasons = "table?", -- season ids; absent = all year
    hours = "table?", -- list of { from, to }; absent = any time
    sizeMin = "number", -- cm
    sizeMax = "number", -- cm
    strength = "number", -- 0..1 pull in the fight
    stamina = "number", -- seconds of hard fighting before tiring
    surgeChance = "number", -- surges per second while fighting
  },
  recipes = {
    name = "string",
    station = "string", -- objects with this station run the recipe
    inputCategory = "string", -- resource category accepted as input
    batch = "number", -- max input units per load
    fuel = "table?", -- resource -> amount per load
    output = "string", -- resource produced (1 per input unit)
    hours = "number", -- in-game hours per load
  },
  notes = {
    name = "string", -- journal map label (<= ~3 words)
    line = "string", -- what the note says (<= ~8 words)
    icon = "string", -- sprite id for the stamp
    event = "string", -- world event that writes the note
    match = "table?", -- event field -> value, or { min = n } / { max = n }
    count = "number?", -- matching events needed (default 1)
  },
  catalog = {
    name = "string",
    page = "string", -- catalog page / journal chapter grouping
    price = "number", -- $
    starter = "boolean?", -- known from the start; others are learned in the Field Journal
    needs = "table?", -- note ids that make this an idea (non-starter items)
    studyNights = "number?", -- nights of study to learn it (non-starter items)
    gives = "table?", -- resource -> amount delivered
    object = "string?", -- placeable object added to inventory
    equipment = "boolean?", -- kept for the run; applies `modifiers`
    modifiers = "table?", -- stat -> additive bonus (see src/sim/stats.lua)
    pickupOnly = "boolean?", -- only available on a truck trip
  },
  task_categories = {
    name = "string",
  },
}
