-- Survival needs (GDD §4.2, D104, D160). Each day the homesteader eats (the food that would spoil first, D94; food
-- that never spoils last), drinks (the cistern stock first, then the canteen) and, on cold nights (none in summer, partial in spring and autumn, the most in
-- winter: Weather.baseWarmth), burns wood in the best placed heat source to stay warm through the night.
-- Shortfalls cost Condition; a fed, warm day restores some.
--
-- Statuses (D166) scale the warmth and water needs and the daily recovery, and drain Condition (status.lua).
--
-- State: world.state.needs = { condition, canteen?, thirstDays? }. `canteen` (water units in hand) is absent
-- until it first changes and then counts as full; `thirstDays` (dry days in a row) is absent while 0, so a
-- fresh game's saved shape does not change.
-- Emits "needs.ate" { calories, shortfall }, "needs.drank" { water, shortfall, damage, thirstDays },
-- "needs.warmed" { warmth, electric, needed, burned, shortfall, shelter } and "needs.depleted" { hunger,
-- thirst, cold, shelter } when Condition hits 0 (the day's shortfalls, `thirst` already scaled by the
-- build-up of a run of dry days, and the shelter, so the rescue can say what failed).

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Sandbox = require("src.sim.systems.sandbox")
local Shelter = require("src.sim.systems.shelter")
local Spoilage = require("src.sim.systems.spoilage")
local Stats = require("src.sim.stats")
local Weather = require("src.sim.systems.weather")

local Needs = {}

local function foods(world)
  local list = {}
  for _, res in ipairs(world.registry:all("resources")) do
    if res.calories then
      list[#list + 1] = res
    end
  end
  return list
end

-- The one fuel: the resource with a `heat` (wood, D104).
local function fuel(world)
  for _, res in ipairs(world.registry:all("resources")) do
    if res.heat then
      return res
    end
  end
  error("no resource has a heat value")
end

local function hurt(world, amount)
  if world.debugInvincible then
    return -- the in-game editor is open (Needs.setInvincible): nothing hurts
  end
  local state = world.state.needs
  -- A sandbox slot never reaches 0 (D134).
  state.condition = math.max(Sandbox.conditionFloor(world), state.condition - amount)
end

--- The foods in the order today's meal eats them (D94): the one whose oldest batch spoils soonest
--- first (`Spoilage.info(...).daysLeft`), ties in content-file order, food that never spoils last.
function Needs.mealOrder(world)
  local list = foods(world)
  local rank = {}
  for i, res in ipairs(list) do
    local info = Spoilage.info(world, res.id)
    rank[res.id] = { left = info and info.daysLeft or math.huge, index = i }
  end
  table.sort(list, function(a, b)
    local ra, rb = rank[a.id], rank[b.id]
    if ra.left ~= rb.left then
      return ra.left < rb.left
    end
    return ra.index < rb.index
  end)
  return list
end

--- Total calories in stock.
function Needs.calories(world)
  local total = 0
  for _, res in ipairs(foods(world)) do
    total = total + Ledger.get(world, res.id) * res.calories
  end
  return total
end

--- Days of food in stock at the current daily need.
function Needs.foodDays(world)
  return Needs.calories(world) / world.tuning.needs.dailyCalories
end

--- Efficiency of the best placed heat source (0 = nothing to burn fuel in). A source beyond the
--- sleeping shelter's heater slot delivers only part of its warmth (D82, Shelter.heatReach).
function Needs.heatEfficiency(world)
  local best = 0
  local objects = world.state.grid.objects
  -- The cached index of heat sources (D58), not a scan of every placed object: the HUD asks every frame.
  for _, anchor in ipairs(Grid.anchorsWith(world, "heatSource")) do
    best = math.max(
      best,
      world.registry:get("objects", objects[anchor].id).heatSource.efficiency * Shelter.heatReach(world, anchor)
    )
  end
  return best
end

--- The id of the fuel resource (wood).
function Needs.fuelId(world)
  return fuel(world).id
end

--- Warmth one unit of wood gives in the best placed heat source (0 with no fire placed).
function Needs.warmthPerWood(world)
  return fuel(world).heat * Needs.heatEfficiency(world)
end

--- Warmth the wood in stock would give in the best heat source.
function Needs.warmthInStock(world)
  return Ledger.get(world, fuel(world).id) * Needs.warmthPerWood(world)
end

--- Warmth needed tonight: the season's base, scaled by the winter's severity and any cold snap, then
--- by the best shelter's insulation (D82), today's clothes (D149) and the statuses (D166: a fever needs more).
function Needs.warmthNeeded(world)
  local natural = Weather.warmthNeed(world) * Shelter.nightInsulation(world)
  local need = natural * Stats.factor(world, "warmthNeed")
  if need > natural then
    -- The ceiling on bad luck (D169, PLAN_DEPTH 6.5): what statuses (and later events) add never lifts the night past
    -- `maxWarmthMultiplier` times the season's base need, nor past what the weather and shelter alone already ask.
    local now = Calendar.now(world)
    local ceiling = Weather.baseWarmth(world, now.season, now.dayOfSeason)
      * world.tuning.events.mercy.maxWarmthMultiplier
    need = math.min(need, math.max(natural, ceiling))
  end
  return need
end

--- Take Condition off as an event outcome (D169): at most `amount`, never under `floor` (the mercy rule that an event is
--- never the killing blow, PLAN_DEPTH 6.5). Honours the editor's invincibility and a sandbox slot's floor. Returns the
--- Condition actually lost.
function Needs.injure(world, amount, floor)
  local state = world.state.needs
  local before = state.condition
  local lost = math.max(0, math.min(amount, before - (floor or 0)))
  if lost > 0 then
    hurt(world, lost)
  end
  return before - state.condition
end

--- The wood outlook (D104), the one accessor behind the HUD wood chip, the Pantry row and the alerts:
---   { stock (wood in the ledger), perNight (wood tonight's fire burns, after the electric heaters'
---     forecast share, D101), nights (stock / that need; math.huge when no fire is needed, D70),
---     noFire (a fire is needed but none is placed), perWood (warmth one wood gives) }
function Needs.woodOutlook(world)
  local need = Needs.warmthNeeded(world)
  local electric = math.min(need, Power.heatPerNight(world, Calendar.now(world).season))
  local fireNeed = need - electric
  local perWood = Needs.warmthPerWood(world)
  local stock = Ledger.get(world, fuel(world).id)
  local out = { stock = stock, perNight = 0, nights = math.huge, noFire = need > 0 and perWood <= 0, perWood = perWood }
  if fireNeed > 0 then
    out.nights = stock * perWood / fireNeed
    out.perNight = perWood > 0 and math.ceil(fireNeed / perWood - 1e-9) or 0
  end
  return out
end

--- Nights of wood in stock at tonight's need (math.huge when no fire is needed, D70, #157).
function Needs.fuelNights(world)
  return Needs.woodOutlook(world).nights
end

-- Drinking water (D160) ---------------------------------------------------------------------------

local WATER = "water" -- the ledger stock the cistern fills (the same pool as irrigation)

--- Water units the homesteader drinks each day: the figure the Tonight card, the Footing "water source"
--- test and readiness read, like `warmthNeeded`.
function Needs.waterNeeded(world)
  return world.tuning.needs.dailyWater * Stats.factor(world, "waterNeed") -- D166: a fever drinks more
end

--- Water units in the canteen (a new run starts with it full).
function Needs.canteen(world)
  local held = world.state.needs.canteen
  if held == nil then
    return world.tuning.needs.canteenCapacity
  end
  return held
end

--- Dry days in a row (0 when the last day's drink was met).
function Needs.thirstDays(world)
  return world.state.needs.thirstDays or 0
end

--- The drinking-water outlook, the one accessor behind the drink chip, alerts and readiness:
---   { perDay (units drunk each day), cistern (units in the ledger stock), canteen (units in hand),
---     stock (both), days (stock / perDay), thirstDays (dry days in a row), room (canteen room left) }
function Needs.waterOutlook(world)
  local perDay = Needs.waterNeeded(world)
  local cistern, canteen = Ledger.get(world, WATER), Needs.canteen(world)
  local stock = cistern + canteen
  return {
    perDay = perDay,
    cistern = cistern,
    canteen = canteen,
    stock = stock,
    days = perDay > 0 and stock / perDay or math.huge,
    thirstDays = Needs.thirstDays(world),
    room = math.max(0, world.tuning.needs.canteenCapacity - canteen),
  }
end

--- Days of drinking water in stock at the daily need.
function Needs.waterDays(world)
  return Needs.waterOutlook(world).days
end

--- Pour up to `units` into the canteen (what a creek, well or melted snow gives). Returns what fit.
function Needs.fillCanteen(world, units)
  local added = math.min(units, Needs.waterOutlook(world).room)
  if added > 0 then
    world.state.needs.canteen = Needs.canteen(world) + added
  end
  return added
end

--- Debug and editor tool: while on, hunger and cold cannot lower Condition. A runtime flag on the world,
--- not in the state, so it is never saved (like Market.setCheat, D126).
function Needs.setInvincible(world, on)
  world.debugInvincible = on and true or nil
end

function Needs.invincible(world)
  return world.debugInvincible == true
end

--- The homesteader's Condition (health).
function Needs.condition(world)
  return world.state.needs.condition
end

--- Eat today's food. Returns the shortfall (0..1).
function Needs.eat(world)
  local cfg = world.tuning.needs
  local need = cfg.dailyCalories
  local eaten = 0
  for _, res in ipairs(Needs.mealOrder(world)) do
    while eaten < need and Ledger.remove(world, res.id, 1, "eat") do
      eaten = eaten + res.calories
    end
  end
  local shortfall = math.max(0, need - eaten) / need
  if shortfall > 0 then
    hurt(world, cfg.hungerDamage * shortfall)
  end
  world.events:emit("needs.ate", { calories = eaten, shortfall = shortfall })
  return shortfall
end

--- Drink the day's water: the cistern stock first (the pool irrigation uses), then the canteen. A dry day
--- adds to the run of thirsty days and hurts more each time (never all at once). Returns the shortfall (0..1).
function Needs.drink(world)
  local cfg, state = world.tuning.needs, world.state.needs
  local need = Needs.waterNeeded(world)
  local drunk = 0
  local fromStock = math.min(need, Ledger.get(world, WATER))
  if fromStock > 0 and Ledger.remove(world, WATER, fromStock, "drink") then
    drunk = fromStock
  end
  local fromCanteen = math.min(need - drunk, Needs.canteen(world))
  if fromCanteen > 0 then
    state.canteen = Needs.canteen(world) - fromCanteen
    drunk = drunk + fromCanteen
  end
  local shortfall = need > 0 and math.max(0, need - drunk) / need or 0
  local damage = 0
  if shortfall > 0 then
    local run = math.min(Needs.thirstDays(world), cfg.thirstBuildDays)
    damage = cfg.thirstDamage * shortfall * (1 + cfg.thirstBuild * run)
    state.thirstDays = Needs.thirstDays(world) + 1
    hurt(world, damage)
  else
    state.thirstDays = nil
  end
  world.events:emit("needs.drank", {
    water = drunk,
    shortfall = shortfall,
    damage = damage,
    thirstDays = Needs.thirstDays(world),
  })
  return shortfall, damage
end

--- Burn wood for the night's warmth. Returns the shortfall (0..1).
function Needs.warm(world)
  local cfg = world.tuning.needs
  local need = Needs.warmthNeeded(world)
  local perWood = Needs.warmthPerWood(world)
  local electric = Power.takeWarmth(world) -- warmth the electric heaters made since the last night (GDD §7.5)
  local warmth, burned = 0, 0
  if need > electric and perWood > 0 then
    while warmth + electric < need and Ledger.remove(world, fuel(world).id, 1, "burn") do
      warmth = warmth + perWood
      burned = burned + 1
    end
  end
  local shortfall = need > 0 and math.max(0, need - warmth - electric) / need or 0
  if shortfall > 0 then
    hurt(world, cfg.coldDamage * shortfall)
  end
  world.events:emit("needs.warmed", {
    warmth = warmth,
    electric = math.min(electric, need),
    needed = need,
    burned = burned,
    shortfall = shortfall,
    shelter = Shelter.id(world), -- where the night was spent (notes: truck_cold, camp_cold)
  })
  return shortfall
end

--- The daily draw: food, water and warmth. A day with none short restores some Condition.
function Needs.daily(world)
  local hungry = Needs.eat(world)
  local thirsty, thirstDamage = Needs.drink(world)
  local cold = Needs.warm(world)
  local cfg, state = world.tuning.needs, world.state.needs
  if hungry == 0 and thirsty == 0 and cold == 0 then
    state.condition = math.min(
      cfg.conditionMax,
      state.condition + cfg.dailyRecovery * Shelter.recovery(world) * Stats.factor(world, "conditionRecovery")
    )
  end
  -- A status's drain (D166): Condition lost each day, but never under the drain floor (an injury cannot kill; PLAN_DEPTH
  -- §6.5) and never while the editor's invincibility is on or under a sandbox slot's floor.
  local drain = Stats.factor(world, "conditionDrain")
  if drain > 0 and not world.debugInvincible then
    local floor = math.max(world.tuning.status.drainFloor, Sandbox.conditionFloor(world))
    if state.condition > floor then
      state.condition = math.max(floor, state.condition - drain)
    end
  end
  if state.condition <= 0 then
    -- What the last day lacked (0..1 shortfalls; thirst as its damage in units of thirstDamage, so a run of dry
    -- days counts for more) and where the night was spent (D99).
    world.events:emit("needs.depleted", {
      hunger = hungry,
      thirst = thirstDamage / cfg.thirstDamage,
      cold = cold,
      shelter = Shelter.id(world),
    })
  end
end

function Needs.init(world)
  world.state.needs = world.state.needs or { condition = world.tuning.needs.conditionMax }
  world.events:on("calendar.newDay", function()
    Needs.daily(world)
  end)
end

return Needs
