-- Survival needs (GDD §4.2). M1: food. The homesteader eats once a day, freshest food first
-- (content order of food resources). Shortfalls cost Condition; full days restore some.
--
-- State: world.state.needs = { condition }
-- Emits "needs.ate" { calories, shortfall } and "needs.depleted" when Condition reaches 0.

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
  local state = world.state.needs
  if shortfall > 0 then
    state.condition = math.max(0, state.condition - cfg.hungerDamage * shortfall)
  else
    state.condition = math.min(cfg.conditionMax, state.condition + cfg.dailyRecovery)
  end
  world.events:emit("needs.ate", { calories = eaten, shortfall = shortfall })
  if state.condition <= 0 then
    world.events:emit("needs.depleted", {})
  end
end

function Needs.init(world)
  world.state.needs = world.state.needs or { condition = world.tuning.needs.conditionMax }
  world.events:on("calendar.newDay", function()
    Needs.eat(world)
  end)
end

return Needs
