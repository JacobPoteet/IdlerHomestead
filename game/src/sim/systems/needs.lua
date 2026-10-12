-- Survival needs (GDD §4.2). Each day the homesteader eats (freshest food first: content order of
-- food resources) and, in the cold months, burns fuel in the best placed heat source to stay warm
-- through the night (hottest fuel first). Shortfalls cost Condition; a fed, warm day restores some.
--
-- State: world.state.needs = { condition }
-- Emits "needs.ate" { calories, shortfall }, "needs.warmed" { warmth, needed, burned, green,
-- shortfall } (green = units of poor fuel, heat below 1) and "needs.depleted" when Condition hits 0.

local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")

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

--- Efficiency of the best placed heat source (0 = nothing to burn fuel in).
function Needs.heatEfficiency(world)
  local best = 0
  for _, obj in pairs(world.state.grid.objects) do
    best = math.max(best, world.registry:get("objects", obj.id).heatSource or 0)
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

--- Warmth needed per night this season.
function Needs.warmthNeeded(world)
  return world.tuning.needs.dailyWarmth[Calendar.now(world).season]
end

--- Eat today's food. Returns the shortfall (0..1).
function Needs.eat(world)
  local cfg = world.tuning.needs
  local need = cfg.dailyCalories
  local eaten = 0
  for _, res in ipairs(foods(world)) do
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
  local warmth, burned, green = 0, 0, 0
  if need > 0 and efficiency > 0 then
    for _, res in ipairs(fuels(world)) do
      while warmth < need and Ledger.remove(world, res.id, 1, "burn") do
        warmth = warmth + res.heat * efficiency
        burned = burned + 1
        if res.heat < 1 then
          green = green + 1
        end
      end
    end
  end
  local shortfall = need > 0 and math.max(0, need - warmth) / need or 0
  if shortfall > 0 then
    hurt(world, cfg.coldDamage * shortfall)
  end
  world.events:emit("needs.warmed", { warmth = warmth, needed = need, burned = burned, green = green, shortfall = shortfall })
  return shortfall
end

--- The daily draw: food and warmth. A day with neither short restores some Condition.
function Needs.daily(world)
  local hungry = Needs.eat(world)
  local cold = Needs.warm(world)
  local cfg, state = world.tuning.needs, world.state.needs
  if hungry == 0 and cold == 0 then
    state.condition = math.min(cfg.conditionMax, state.condition + cfg.dailyRecovery)
  end
  if state.condition <= 0 then
    world.events:emit("needs.depleted", {})
  end
end

function Needs.init(world)
  world.state.needs = world.state.needs or { condition = world.tuning.needs.conditionMax }
  world.events:on("calendar.newDay", function()
    Needs.daily(world)
  end)
end

return Needs
