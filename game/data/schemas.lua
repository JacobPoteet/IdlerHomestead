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
    kind = "string?", -- the family it counts as for notes, sounds and shade ("tree" for every species); absent = its own id
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
    sprinkler = "table?", -- sprinkler: { radius = tiles }; like `drip` but spends tuning.water.sprinklerUnitsPerWatering a crop (D118)
    battery = "number?", -- kWh of storage
    station = "string?", -- processor station id used by recipes (e.g. "smoker")
    shelter = "boolean?", -- the homesteader sleeps here (GDD §5.3 shelter ladder, D82)
    replaces = "string?", -- object id this one is placed over and removes (the shack over the camp, D115); with one placed, this must overlap it
    book = "string?", -- a tap opens the book page this tuning.ui.book.shortcuts name stands for (truck, camp, shack; D143)
    shelterRank = "number?", -- shelter: higher is better; Sleep picks the best reachable (truck 0, camp 1, shack 2)
    insulation = "number?", -- shelter: multiplier on the night's warmth need (1 = none, lower keeps more heat)
    recovery = "number?", -- shelter: multiplier on the daily Condition recovery of a fed, warm day
    heaterRadius = "number?", -- shelter: tiles within which a heat source delivers its warmth in full (beyond it: tuning.shelter.farHeat)
    studySpeed = "number?", -- shelter: study speed added while resting there (a desk)
    tierStat = "string?", -- the stat whose modifier (1 + it) sizes this building: the stove's heat, a store, a source's output (D198, Stats.scale)
    heatSource = "table?", -- burns wood for warmth (D104): { efficiency = share of the wood's heat that reaches the night; the best placed fire counts }
    light = "table?", -- night light (D84, shaders/light.glsl): { on = "heat" | "power" | "shelter", radius = art pixels, color, flicker = 0..1, at = { x, y } pixel on the sprite, windows? = { { x, y, w, h } } sprite pixels that glow }
    flat = "boolean?", -- lies on the ground, so it casts no shadow (drip lines, sprinklers)
    dapple = "boolean?", -- a leafy canopy: sun flecks show through its cast shadow (leaf dapple, shaders/shadow_composite.glsl)
    sway = "table?", -- wind sway (D84, shaders/sway.glsl): { weight = multiplier on the wind amplitude, root = 0..1 share of the sprite height from the bottom that stays still }
    chop = "boolean?", -- an axe (chopSpeed) speeds up clearing it
    storage = "table?", -- resource -> extra storage capacity while placed
    pen = "table?", -- goat pen (D71): { pail = milk held, manger = hay units held, trough = water units held, guard = 0..1 chance a night raid is turned back }; see src/sim/systems/animals.lua
    compost = "table?", -- compost bin (D181): { raw = units of raw material (manure, residue, spoiled food) it holds }; see src/sim/systems/compost.lua
    coop = "table?", -- hen house: { nest = eggs held, feeder = feed units held, waterer = water units held, guard = 0..1 chance a night raid is turned back }; see src/sim/systems/animals.lua
  },
  crops = {
    name = "string",
    seed = "string", -- resource consumed to plant
    produce = "string", -- resource gained on harvest
    growDays = "number", -- watered game days to mature
    yield = "number", -- base produce per harvest, scaled by soil
    seedReturn = "table", -- { min, max } seeds back per harvest
    plantSeasons = "table", -- season ids the plant task sows it in (D177); growth after planting is not limited to them
    frost = "string", -- tender (the freeze kills it) | hardy (survives the freeze dormant)
    waterAppetite = "number", -- multiplier on how fast a watering dries (1 = the base rate)
    fertilityDraw = "number", -- share of a tile's fertility a harvest draws; negative adds (legumes); read by D2
    family = "string", -- rotation family, one of tuning.farming.families; read by D3
    qualitySensitivity = "number", -- 0..1 how strongly quality follows fertility, weeding and tending (quality.lua, D182)
    perennial = "table?", -- planted once and bears every year (D183): { fruitSeason = season id, vulnerable = { animal ids a young plant draws } }; see crops.lua
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
    speedStat = "string?", -- the stat whose modifier shortens the load (Stats.timeFactor, D198: the smoker tiers)
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
  milestones = { -- run milestones (D163, #342); see the header of content/milestones.lua
    name = "string", -- the checklist line (<= ~4 words)
    hint = "string", -- what to do, written as an action (<= ~8 words)
    event = "string", -- world event that reaches it
    match = "table?", -- event field -> value, a list of values (any one), or { min = n } / { max = n }
    count = "number?", -- matching events needed (default 1)
  },
  statuses = { -- injury and condition statuses (D166, #345); see the header of content/statuses.lua
    name = "string", -- the chip's title
    line = "string", -- the one effect that matters (<= ~8 words)
    family = "string", -- statuses of one family escalate, they never stack
    severity = "number", -- 1.. within the family
    duration = "number?", -- days it lasts, counted after each night's draw; absent = until cleared
    clearedBy = "string", -- "time" | "rest" | "item"
    escalatesTo = "string?", -- id of the next severity of the family
    modifiers = "table", -- name -> multiplier (1 = none); conditionDrain is Condition lost a day
  },
  events = { -- misfortune events (D169, #347); see the header of content/events.lua
    title = "string", -- the card's title (<= ~3 words)
    line = "string", -- what happens, one sentence
    class = "string", -- "body" | "home" | "land" | "visitors": the standing-order class (B5)
    when = "string", -- "night" | "morning" | "day": when it is offered
    bad = "boolean", -- a misfortune: not drawn while Footing is slipped, Condition is low or the statuses are full
    wake = "boolean?", -- may wake the homesteader (the card never freezes time)
    seasons = "table?", -- season id -> weight multiplier; absent = every season at 1
    minYear = "number?", -- earliest year it can come
    minDay = "number?", -- earliest day of the run it can come
    conditions = "table?", -- all must hold (when drawn and when offered): weather, frozen, status, noStatus, noColdNight, placed, coldNight, thirsty, feet, outfit, planted, equipment, noEquipment; see the header of content/events.lua
    drawConditions = "table?", -- the same keys, checked only when the dusk draw picks the event
    fall = "boolean?", -- the weight is multiplied by the statuses' fall chance
    terms = "table?", -- weight terms: { { <a condition key>, mult } }, each that holds multiplies the weight
    weight = "number", -- relative weight among the events that can come now
    exposure = "number?", -- 0..1: how much night exposure shapes this event's weight (0 = none, 1 = fully)
    cooldown = "number?", -- days before it can come again
    once = "boolean?", -- at most once a run
    journalNote = "string?", -- note id written the first time it is offered (Journal.write)
    options = "table", -- exactly two { label, cost?, meal?, trade?, effect, risk, careful?, bold?, known? = { [perk id] = { label?, cost?, effect?, risk? } } }
    extras = "table?", -- further options while their `requires` = { known? = perk id, have? = resource id } hold (Techniques and the first-aid kit, D199)
    ignore = "table", -- { label, effect, risk }: applies when nobody answers in the window; free, safe, never escalates
  },
  night_threats = { -- night threats (D187, #355); see the header of content/night_threats.lua
    name = "string", -- label (<= ~3 words)
    handler = "string", -- "cat" | "animals" | "raiders": the system whose nightPlan and nightLand draw and land it
    seasons = "table?", -- list of season ids it can come in; absent = every season
    minDay = "number?", -- earliest day of the run
    minYear = "number?", -- earliest year
    weight = "number", -- relative weight when more than one threat hits the same night
    exposure = "number", -- 0..1: how much night exposure shapes its chance
    guard = "string?", -- stat whose modifiers turn it aside
    counter = "string?", -- catalog id of the item that answers it
    warn = "table", -- { line }: the dusk sign on the Tonight card
    outcomes = "table", -- { turned = { report }, landed = { capital?, lesser?, sparedReport? } }
    wake = "string?", -- id of a night event offered once it has resolved
    journalNote = "string?", -- note id written the first time it lands
  },
  contracts = { -- the town's board (D197, #372); see the header of content/contracts.lua
    name = "string", -- who asks (<= ~4 words)
    item = "string", -- resource id asked for
    min = "number", -- fewest units an offer asks
    max = "number", -- most units an offer asks
    minDone = "number?", -- contracts finished before this one is offered (reputation, a count); absent = from the start
    standing = "boolean?", -- the repeating weekly order: one at a time, renewed each week, the idle income
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
    replaces = "string?", -- catalog id of the item this one supersedes (D115): owning this makes that one unavailable ("Owned"), equipment drops the old one's modifiers, an object replaces the old one at placement (objects.replaces); the card says "Replaces the ..."
    replacesLabel = "string?", -- what an upgrade supersedes when that is not a catalog item (the plain bucket); the card says "Replaces the ..."
    unique = "boolean?", -- one ever (D114): a second purchase is refused while the first is owned (in the inventory, placed, or ordered); equipment is always unique
    family = "string?", -- tier ladder this item belongs to (D198, #382): the rod, the stove, the roadside stand, ... Tiers.find / Tiers.nextTier read it
    tier = "number?", -- 1 to tuning.economy.tiers.max within its family; a tier past I replaces and requires the one below
    tierBase = "number?", -- the tier I reference price for the cost curve when tier I is not an item (the plain bucket)
    overlay = "string?", -- sprite id drawn over the upgraded building while this is owned (placeholder art until #107); a higher tier keeps the lower tiers' looks
    page = "string", -- catalog page / journal chapter grouping
    price = "number?", -- $; omitted on a tier past I, whose price is the exponential curve (Tiers.price, D198)
    starter = "boolean?", -- known from the start; others are learned in the Field Journal
    needs = "table?", -- note ids that make this an idea (non-starter items)
    studyNights = "number?", -- nights of study to learn it (non-starter items)
    gives = "table?", -- resource -> amount delivered
    object = "string?", -- placeable object added to inventory
    equipment = "boolean?", -- kept for the run; applies `modifiers`
    modifiers = "table?", -- stat -> additive bonus (see src/sim/stats.lua)
    pickupOnly = "boolean?", -- only available on a truck trip
    requires = "string?", -- catalog id of equipment that must be owned first (goats need the trailer, D71)
    requiresFooting = "boolean?", -- the gate flag (D164, #343): shown but locked ("opens at Footing") until Footing is held; read by Footing.isOpen, never hard-coded per feature
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
    startingObjects = "table?", -- placeable object ids put beside the truck at the start of every run (#215)
    truckCharge = "number?", -- kWh in the truck battery at the start of every run
    modifiers = "table?", -- stat -> bonus while known (see src/sim/stats.lua)
  },
  loadouts = { -- starting loadouts (D201, #386); see the header of content/loadouts.lua
    name = "string", -- the card's title (<= ~2 words)
    line = "string", -- what it brings (<= ~8 words)
    penaltyLine = "string", -- what it costs, in words (<= ~6 words)
    unlock = "string", -- Journal node id (catalog item or perk) that must be known
    startingResources = "table?", -- resource -> amount added to the starting stock
    penalty = "table", -- resource -> amount taken off the starting stock (never below zero)
    startingEquipment = "table?", -- catalog equipment ids owned at the start
    startingObjects = "table?", -- placeable object ids put beside the truck
    truckCharge = "number?", -- kWh in the truck battery at the start
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
    blight = "table?", -- disease (D185): { chance = per day, per crop on a tile at full pest pressure, that a rainy day marks it so its harvest is spoiled, dryFactor = its share on a dry day }
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
  garments = { -- the homesteader's wardrobe (GDD D149); see src/sim/systems/wardrobe.lua and the header of content/garments.lua
    name = "string", -- display name (<= ~3 words)
    slot = "string", -- head | torso | legs | feet | extra (the order is tuning.wardrobe.slots)
    class = "string", -- light | mid | heavy: a key of tuning.wardrobe.classes
    hint = "string?", -- the locked tile's one line; a %d is the unlock threshold from tuning.wardrobe.unlocks
    starter = "boolean?", -- owned from the first day of a slot (one per slot)
    default = "boolean?", -- worn when a saved id is unknown (one per slot, the starter)
    unlock = "table?", -- { kind, ... }: how it is earned (see the header of content/garments.lua); absent only for a starter
    look = "table", -- the Character look fields this garment sets (src/render/character.lua)
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
