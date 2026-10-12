-- Food rules & the sell crate (GDD §6.2).
--
-- The crate is a reservation on ledger stock, not a separate store: crate[id] units are marked for
-- sale but stay in the ledger (still edible in a pinch, still spoiling). Selling removes them.
-- Rules, re-applied every tuning.food.rulesInterval in-game hours:
--   1. Preserved food fills the winter stock first: winterDays of eating.
--   2. Fresh food (has spoilDays) fills the pantry: pantryDays of eating.
--   3. Fresh food that a placed processor can preserve is held for preserving while the winter
--      stock is short.
--   4. Everything else that has a sale value goes in the crate (plus autoSell goods like scrap).
-- Per-item pins override: "keep" (never sell), "sell" (always sell), "preserve" (hold to preserve).
--
-- State: world.state.food = { pantryDays, winterDays, pins = { [id] = pin }, crate = { [id] = n }, nextSort }

local Ledger = require("src.sim.systems.ledger")

local Food = {}

Food.PINS = { "keep", "preserve", "sell" }

function Food.init(world)
  local cfg = world.tuning.food
  world.state.food = world.state.food
    or { pantryDays = cfg.defaultPantryDays, winterDays = cfg.defaultWinterDays, pins = {}, crate = {}, nextSort = 0 }
  world.events:on("ledger.changed", function(e)
    -- Eating, spoiling or selling can drop stock below what's reserved.
    local crate = world.state.food.crate
    if crate[e.id] and crate[e.id] > e.total then
      crate[e.id] = e.total > 0 and e.total or nil
    end
  end)
end

--- Units of a resource not reserved for sale.
function Food.available(world, id)
  return Ledger.get(world, id) - (world.state.food.crate[id] or 0)
end

function Food.crateCount(world)
  local n = 0
  for _, count in pairs(world.state.food.crate) do
    n = n + count
  end
  return n
end

-- Categories that some placed processor can turn into preserved food.
local function preservableCategories(world)
  local stations = {}
  for _, obj in pairs(world.state.grid.objects) do
    local station = world.registry:get("objects", obj.id).station
    if station then
      stations[station] = true
    end
  end
  local cats = {}
  for _, recipe in ipairs(world.registry:all("recipes")) do
    if stations[recipe.station] then
      cats[recipe.inputCategory] = true
    end
  end
  return cats
end

--- Re-sort stock into pantry / preserve / crate according to the rules.
function Food.sort(world)
  local state = world.state.food
  local daily = world.tuning.needs.dailyCalories
  local pantryLeft = state.pantryDays * daily
  local winterLeft = state.winterDays * daily
  local preservable = preservableCategories(world)
  local crate = {}
  local resources = world.registry:all("resources")

  -- Preserved goods count toward the winter stock.
  for _, res in ipairs(resources) do
    local amount = Ledger.get(world, res.id)
    if amount > 0 and res.calories and not res.spoilDays then
      local keep = math.min(amount, math.ceil(math.max(0, winterLeft) / res.calories))
      winterLeft = winterLeft - keep * res.calories
      crate[res.id] = amount - keep
    end
  end
  -- Fresh food fills the pantry, then waits to be preserved, then is sold.
  for _, res in ipairs(resources) do
    local amount = Ledger.get(world, res.id)
    if amount > 0 and res.calories and res.spoilDays then
      local keep = math.min(amount, math.ceil(math.max(0, pantryLeft) / res.calories))
      pantryLeft = pantryLeft - keep * res.calories
      local rest = amount - keep
      if rest > 0 and preservable[res.category] and winterLeft > 0 then
        rest = 0 -- hold it for the processor
      end
      crate[res.id] = rest
    end
  end
  -- Non-food goods marked autoSell.
  for _, res in ipairs(resources) do
    if res.autoSell then
      crate[res.id] = Ledger.get(world, res.id)
    end
  end
  -- Pins, and drop anything that can't actually be sold.
  for _, res in ipairs(resources) do
    local pin = state.pins[res.id]
    if pin == "keep" or pin == "preserve" then
      crate[res.id] = nil
    elseif pin == "sell" then
      crate[res.id] = Ledger.get(world, res.id)
    end
    if not res.value or (crate[res.id] or 0) <= 0 then
      crate[res.id] = nil
    end
  end
  state.crate = crate
end

function Food.setPin(world, id, pin)
  world.registry:get("resources", id)
  assert(pin == nil or pin == "keep" or pin == "sell" or pin == "preserve", "bad pin " .. tostring(pin))
  world.state.food.pins[id] = pin
  Food.sort(world)
end

function Food.setDays(world, pantryDays, winterDays)
  local cfg, state = world.tuning.food, world.state.food
  state.pantryDays = math.max(0, math.min(cfg.maxPantryDays, pantryDays))
  state.winterDays = math.max(0, math.min(cfg.maxWinterDays, winterDays))
  Food.sort(world)
end

function Food.tick(world, dt)
  local state = world.state.food
  state.nextSort = state.nextSort - dt
  if state.nextSort <= 0 then
    state.nextSort = world.tuning.food.rulesInterval * world.tuning.time.dayLength / 24
    Food.sort(world)
  end
end

return Food
