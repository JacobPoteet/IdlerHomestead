-- Field schemas for each content kind (see src/core/registry.lua for the spec format).
-- Unknown fields in content files are rejected, so add new fields here first.
return {
  resources = {
    name = "string", -- display name
    category = "string", -- currency | material | seed | food | ...
    capacity = "number?", -- default storage cap; absent means unlimited until storage buildings set one
    calories = "number?", -- food energy per unit; present means it can be eaten
    keepsForWinter = "boolean?", -- fresh food that keeps long enough to count toward the winter stock
    value = "number?", -- base sale price in $; absent = can't be sold
    heat = "number?", -- warmth per unit burned in a heat source; present means it's fuel
    housing = "string?", -- livestock: what houses it ("coop", "pen"), for "needs a ..." messages
  },
  terrain = {
    name = "string",
    walkable = "boolean", -- can actors stand on it
    tillable = "boolean?", -- can be tilled into a field
    buildable = "boolean?", -- objects may be placed here (grass; roads and water are off limits, D79)
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
    fell = "boolean?", -- the routine's "Clear trees" category fells it (opt-in, D109); like any clearable it can also be ordered by hand
    footprintW = "number?", -- tiles wide (default 1); anchored at the top-left tile
    footprintH = "number?", -- tiles tall (default 1)
    placeable = "boolean?", -- can be placed by the player from inventory
    source = "table?", -- power source: { curve = "solar"|"wind"|"hydro"|"fuel", peak = kW, fuel?, fuelPerKwh? } (GDD §7.5)
    sink = "table?", -- power sink: { tier, draw = kW, schedule = "always"|"dark"|"heat"|"fill"|"demand" (fill needs `fills` = resource id; demand draws only while its owner asks, machines), inertia? = hours, effects? = { name -> amount } }
    machine = "table?", -- stationary actor (D65): { categories = { task category ids }, tasks? = { task ids }, radius = tiles (Chebyshev), workSpeed = work seconds per second at full power }; also needs a `sink`
    maxRate = "number?", -- battery: most kW it can charge or discharge at (absent = unlimited)
    efficiency = "number?", -- battery: fraction of charging energy that is stored (absent = 1)
    vehicle = "boolean?", -- battery: the truck; charged in the "truck" priority tier, lends power only above a trip reserve
    placeNear = "string?", -- placement rule: must touch this terrain ("water": next to the creek; "road": beside the road, not on it)
    stand = "boolean?", -- roadside stand: sells a capped number of spare goods each day (tuning.stand, GDD §6.4)
    offRoad = "boolean?", -- placement rule: never on the road (the hen house)
    placeOn = "string?", -- placement rule: "waterTable" needs a tile with a high water table (wells, pumps; GDD §5.3)
    waterSource = "table?", -- a place to fill the bucket: { fillTime = seconds, stored? = draws on the cistern stock }
    pump = "table?", -- pumps water into cisterns: { rate = units per in-game hour at full power }; also needs a `sink`
    drip = "table?", -- drip line: { radius = tiles }; waters thirsty crops in range from the cistern stock, no actor
    battery = "number?", -- kWh of storage
    station = "string?", -- processor station id used by recipes (e.g. "smoker")
    shelter = "boolean?", -- the homesteader sleeps here (GDD §5.3 shelter ladder, D82)
    shelterRank = "number?", -- shelter: higher is better; Sleep picks the best reachable (truck 0, camp 1, shack 2)
    insulation = "number?", -- shelter: multiplier on the night's warmth need (1 = none, lower keeps more heat)
    recovery = "number?", -- shelter: multiplier on the daily Condition recovery of a fed, warm day
    heaterRadius = "number?", -- shelter: tiles within which a heat source delivers its warmth in full (beyond it: tuning.shelter.farHeat)
    studySpeed = "number?", -- shelter: study speed added while resting there (a desk)
    heatSource = "table?", -- burns wood for warmth (D104): { efficiency = share of the wood's heat that reaches the night; the best placed fire counts }
    light = "table?", -- night light (D84, shaders/light.glsl): { on = "heat" | "power" | "shelter", radius = art pixels, color, flicker = 0..1, at = { x, y } pixel on the sprite, windows? = { { x, y, w, h } } sprite pixels that glow }
    sway = "table?", -- wind sway (D84, shaders/sway.glsl): { weight = multiplier on the wind amplitude, root = 0..1 share of the sprite height from the bottom that stays still }
    chop = "boolean?", -- an axe (chopSpeed) speeds up clearing it
    storage = "table?", -- resource -> extra storage capacity while placed
    pen = "table?", -- goat pen (D71): { pail = milk held, manger = hay units held, trough = water units held, guard = 0..1 chance a night raid is turned back }; see src/sim/systems/animals.lua
    coop = "table?", -- hen house: { nest = eggs held, feeder = feed units held, waterer = water units held, guard = 0..1 chance a night raid is turned back }; see src/sim/systems/animals.lua
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
    yield = "number?", -- output units per input unit (default 1; cheese makes one from two milk)
    output = "string", -- resource produced (`yield` per input unit)
    hours = "number", -- in-game hours per load
  },
  notes = {
    name = "string", -- journal map label (<= ~3 words)
    line = "string", -- what the note says (<= ~8 words)
    hint = "string", -- how to get it, written as an action (<= ~8 words); shown for notes not written yet (D72)
    icon = "string", -- sprite id for the stamp
    event = "string", -- world event that writes the note
    match = "table?", -- event field -> value, or { min = n } / { max = n }
    count = "number?", -- matching events needed (default 1)
  },
  chapters = {
    name = "string", -- region title on the journal map
    pages = "table", -- node `page` values that belong to this chapter
    area = "string?", -- overview heading this chapter is grouped under (D81); absent = tuning.ui.journal.defaultArea
  },
  catalog = {
    name = "string",
    line = "string", -- what it does, for the journal card (<= ~8 words)
    desc = "string?", -- longer text for the store's item card (#266, D107): what it does and how; the card falls back to `line`
    replaces = "string?", -- catalog id of the item this one supersedes (the card says "Replaces the ..."); no item uses it yet
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
    requires = "string?", -- catalog id of equipment that must be owned first (goats need the trailer, D71)
  },
  perks = {
    name = "string", -- journal map label (<= ~3 words)
    page = "string", -- journal chapter grouping
    icon = "string", -- sprite id
    line = "string", -- what it does (<= ~8 words)
    needs = "table", -- note ids that make it an idea
    studyNights = "number", -- nights of study to learn it
    startingResources = "table?", -- resource -> amount added at the start of every run
    startingEquipment = "table?", -- catalog equipment ids owned at the start of every run
    truckCharge = "number?", -- kWh in the truck battery at the start of every run
    modifiers = "table?", -- stat -> bonus while known (see src/sim/stats.lua)
  },
  finds = {
    name = "string", -- card title (<= ~3 words)
    line = "string", -- what you get (<= ~8 words)
    icon = "string", -- sprite id
    weight = "number?", -- base selection weight (default 1)
    seasons = "table?", -- season -> weight multiplier
    minYear = "number?", -- first year it can be offered
    maxYear = "number?", -- last year it can be offered
    lacks = "table?", -- boosts the weight when true: { resource, below } | { object } | { equipment }
    effects = "table", -- { resources = { id = n }, objects = { id = n }, equipment = { catalogId }, truckCharge = kWh }
  },
  threats = { -- growing-season threats (GDD §7.9, D67); see src/sim/systems/threats.lua
    name = "string", -- label in toasts and the forecast (<= ~3 words)
    line = "string", -- what it does (<= ~8 words)
    icon = "string", -- sprite id
    season = "string", -- season id it comes in
    startDays = "table", -- { first, last } day of that season it may start on
    span = "table", -- { min, max } days it lasts (a weather-driven threat may strike on any day of it)
    hour = "number", -- in-game hour its effect lands (daily threats roll then)
    minYear = "number", -- first year it can be scheduled
    weight = "number", -- relative odds of being picked for a year
    guard = "string", -- stat whose modifiers turn part of it aside (the countermeasure)
    counter = "string", -- catalog id of the countermeasure (its modifiers name the guard stat)
    strike = "table?", -- weather-driven: { chance = per day before weather, weatherPower = exponent on Weather.threat }; strikes once
    damage = "table?", -- { share = 0..1 of crops hit at strength 1, kill = true, setback = growth lost, ripe = hits ripe crops, unripe = hits growing crops }
    drought = "table?", -- { dryRate = extra drying multiplier at strength 1, witherHours = in-game hours dry before a crop withers }
  },
  task_categories = {
    name = "string",
    startsOff = "boolean?", -- the routine lists it switched Off until the player turns it on (an action the routine only does when asked, D109)
  },
  ftue = { -- first-time tip cards (GDD D69); see src/sim/systems/ftue.lua and the header of content/ftue.lua
    title = "string", -- card title and Tips list label (<= ~3 words)
    text = "string", -- card body; {domain.key} tokens are read from tuning
    trigger = "string?", -- event name, or "start"
    match = "table?", -- { field = value } the event payload must equal
    delay = "number?", -- game seconds from trigger to due (default tuning.ftue.defaultDelay)
    after = "table?", -- { step, seconds }: also due this long after that step was dismissed
    retire = "table?", -- event names after which the step is marked seen without a card
    run = "number?", -- the card belongs to this run of the slot (2 = the second run) and shows even though the first-run tips are over (D99)
    highlight = "string?", -- screen target the scene outlines while the card is up (D89): "button:<id>", "seeds", "chip:<id>", "tile:truck"
    doneFlag = "string?", -- meta flag that means another card already told it
    card = "boolean?", -- false: never queues a card
    replay = "string?", -- "spoil": Tips shows the live spoilage explanation
  },
  routine_conditions = {
    name = "string", -- what the panel's kind button says
    measure = "string", -- "foodDays" | "stock" | "seasonIndex" | "hour"
    resources = "table?", -- stock measure: resource ids summed
    cmp = "string", -- "below" | "atleast" | "is"
    min = "number", -- lowest value the stepper reaches
    max = "number", -- highest value the stepper reaches
    step = "number", -- change per stepper press
    default = "number", -- value when the kind is first picked
    unit = "string", -- what the value counts, for tooltips and docs
    short = "string", -- format with one %s for the value, shown in the routine list
  },
  chips = { -- top-bar chip modals (GDD D72, D112); see the header of content/chips.lua
    name = "string", -- modal title (<= ~3 words)
    status = "table", -- state key -> the headline for that state (a short phrase)
    rows = "table", -- { { key, label, fmt } }: labelled numbers; chip_text fills the value for each key
    why = "table?", -- state key -> one short line saying what to do about that state
    panel = "string?", -- panel the shortcut opens: "pantry" | "power" | "catalog" | "truck" | "load"
    panelLabel = "string?", -- the shortcut button's text
  },
}
