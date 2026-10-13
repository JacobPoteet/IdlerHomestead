-- Survival needs (GDD §4.2). Each day the homesteader eats (the food that would spoil first, D94; food
-- that never spoils last) and, in the cold months, burns fuel in the best placed heat source to stay warm
-- through the night (hottest fuel first). Shortfalls cost Condition; a fed, warm day restores some.
--
-- State: world.state.needs = { condition }
-- Emits "needs.ate" { calories, shortfall }, "needs.warmed" { warmth, electric, needed, burned, green,
-- shortfall } (green = units of poor fuel, heat below 1) and "needs.depleted" { hunger, cold, shelter }
-- when Condition hits 0 (the day's shortfalls and the shelter, so the rescue can say what failed).

local Calendar = require("src.sim.systems.calendar")
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

-- Fuels, hottest first (content order breaks ties).
local function fuels(world)
  local list = {}
  for _, res in ipairs(world.registry:all("resources")) do
    if res.heat then
      list[#list + 1] = res
    end
  end
  table.sort(list, function(a, b)
    return a.heat > b.heat
  end)
  return list
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
  for anchor, obj in pairs(world.state.grid.objects) do
    local heat = world.registry:get("objects", obj.id).heatSource
    if heat then
      best = math.max(best, heat * Shelter.heatReach(world, anchor))
    end
  end
  return best
end

--- Warmth the fuel in stock would give in the best heat source.
function Needs.warmthInStock(world)
  local total = 0
  for _, res in ipairs(fuels(world)) do
    total = total + Ledger.get(world, res.id) * res.heat
  end
  return total * Needs.heatEfficiency(world)
end

--- Warmth needed tonight: the season's base, scaled by the winter's severity and any cold snap, then
--- by the best shelter's insulation (D82).
function Needs.warmthNeeded(world)
  return Weather.warmthNeed(world) * Shelter.insulation(world)
end

--- Nights of fuel in stock at tonight's need (math.huge when no fire is needed, D70, #157).
function Needs.fuelNights(world)
  local need = Needs.warmthNeeded(world)
  if need <= 0 then
    return math.huge
  end
  return Needs.warmthInStock(world) / need
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

--- Burn fuel for the night's warmth. Returns the shortfall (0..1).
function Needs.warm(world)
  local cfg = world.tuning.needs
  local need = Needs.warmthNeeded(world)
  local efficiency = Needs.heatEfficiency(world)
  local electric = Power.takeWarmth(world) -- warmth the electric heaters made since the last night (GDD §7.5)
  local warmth, burned, green = 0, 0, 0
  if need > electric and efficiency > 0 then
    for _, res in ipairs(fuels(world)) do
      while warmth + electric < need and Ledger.remove(world, res.id, 1, "burn") do
        warmth = warmth + res.heat * efficiency
        burned = burned + 1
        if res.heat < 1 then
          green = green + 1
        end
      end
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
    green = green,
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
