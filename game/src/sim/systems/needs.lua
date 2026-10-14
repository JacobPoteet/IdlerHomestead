-- Survival needs (GDD §4.2, D104). Each day the homesteader eats (the food that would spoil first, D94; food
-- that never spoils last) and, on cold nights (none in summer, partial in spring and autumn, the most in
-- winter: Weather.baseWarmth), burns wood in the best placed heat source to stay warm through the night.
-- Shortfalls cost Condition; a fed, warm day restores some.
--
-- State: world.state.needs = { condition }
-- Emits "needs.ate" { calories, shortfall }, "needs.warmed" { warmth, electric, needed, burned, shortfall,
-- shelter } and "needs.depleted" { hunger, cold, shelter } when Condition hits 0 (the day's shortfalls
-- and the shelter, so the rescue can say what failed).

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Shelter = require("src.sim.systems.shelter")
local Spoilage = require("src.sim.systems.spoilage")
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
  local state = world.state.needs
  state.condition = math.max(0, state.condition - amount)
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
--- by the best shelter's insulation (D82).
function Needs.warmthNeeded(world)
  return Weather.warmthNeed(world) * Shelter.insulation(world)
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

--- The daily draw: food and warmth. A day with neither short restores some Condition.
function Needs.daily(world)
  local hungry = Needs.eat(world)
  local cold = Needs.warm(world)
  local cfg, state = world.tuning.needs, world.state.needs
  if hungry == 0 and cold == 0 then
    state.condition = math.min(cfg.conditionMax, state.condition + cfg.dailyRecovery * Shelter.recovery(world))
  end
  if state.condition <= 0 then
    world.events:emit("needs.depleted", { hunger = hungry, cold = cold, shelter = Shelter.id(world) }) -- what the last day lacked (0..1 shortfalls) and where the night was spent (D99)
  end
end

function Needs.init(world)
  world.state.needs = world.state.needs or { condition = world.tuning.needs.conditionMax }
  world.events:on("calendar.newDay", function()
    Needs.daily(world)
  end)
end

return Needs
