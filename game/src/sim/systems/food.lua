-- Food rules & the sell crate (GDD §6.2).
--
-- The crate is a reservation on ledger stock, not a separate store: crate[id] units are marked for
-- sale but stay in the ledger (still edible in a pinch, still spoiling). Selling removes them.
-- Rules, re-applied every tuning.food.rulesInterval in-game hours:
--   1. Preserved food fills the winter stock first: winterDays of eating.
--   2. Fresh food (has spoilDays) fills the pantry: pantryDays of eating.
--   3. Fresh food that keeps for winter (potatoes) tops up the winter stock.
--   4. Fresh food that a placed processor can preserve is held for preserving while the winter
--      stock is short.
--   5. Everything else that has a sale value goes in the crate (plus autoSell goods like scrap).
-- Per-item pins override: "keep" (never sell), "sell" (always sell), "preserve" (hold to preserve).
-- A separate "truck only" flag per item keeps it out of the roadside stand's daily sale (D62).
-- Automatic pantry (D68, #163): a new run's pantry holds a perishable only up to
-- tuning.food.autoPantryHorizon of its spoilDays, so surplus goes to the crate instead of rotting.
-- Moving the "keep N days" stepper turns the automatic mode off (the number then means what it
-- always did); saves from before D68 have no flag and keep their manual rule.
--
-- State: world.state.food = { pantryDays, winterDays, pantryAuto, pins = { [id] = pin },
--                             truckOnly = { [id] = true }, crate = { [id] = n }, nextSort,
--                             lastLoss = { day, lost = { { resource, amount }... }, total }?,
--                             report = (same shape)? -- last night's spoilage until the UI has said it }
-- Meta: world.meta.spoilExplained once the first-spoil explanation has been shown (D68, #151).

local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")

local Food = {}

Food.PINS = { "keep", "preserve", "sell" }

function Food.init(world)
  local cfg = world.tuning.food
  world.state.food = world.state.food
    or {
      pantryDays = cfg.defaultPantryDays,
      winterDays = cfg.defaultWinterDays,
      pantryAuto = true,
      pins = {},
      crate = {},
      nextSort = 0,
    }
  world.state.food.truckOnly = world.state.food.truckOnly or {} -- older saves predate the stand pin
  -- Last night's spoilage (food.spoilReport): kept for the pantry panel, and held as a pending
  -- report until the UI has shown it (it waits while the homesteader sleeps).
  world.events:on("food.spoilReport", function(e)
    local day = Calendar.now(world).day
    world.state.food.lastLoss = { day = day, lost = e.lost, total = e.total }
    world.state.food.report = { day = day, lost = e.lost, total = e.total }
  end)
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

--- Units of a resource reserved in the sell crate.
function Food.crateOf(world, id)
  return world.state.food.crate[id] or 0
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

--- Is this category something a placed processor (the smoker) can preserve?
function Food.canPreserve(world, category)
  return preservableCategories(world)[category] == true
end

--- Is the pantry in its automatic mode (perishables held only as long as they keep)?
function Food.pantryAuto(world)
  return world.state.food.pantryAuto == true
end

--- Switch the automatic pantry on or off (the stepper turns it off by itself).
function Food.setPantryAuto(world, auto)
  world.state.food.pantryAuto = auto and true or false
  Food.sort(world)
end

--- Days of eating the pantry will hold of this food: the pantry setting, cut to a share of how long
--- the food keeps while the automatic pantry is on.
function Food.pantryHoldDays(world, res)
  local state = world.state.food
  if state.pantryAuto and res.spoilDays then
    return math.min(state.pantryDays, res.spoilDays * world.tuning.food.autoPantryHorizon)
  end
  return state.pantryDays
end

--- Last night's spoilage ({ day, lost = { { resource, amount }... }, total }) or nil.
function Food.lastLoss(world)
  return world.state.food.lastLoss
end

--- Take the spoilage report the UI has not shown yet (nil if none), marking it shown. `first` is
--- true the one time the explanation of spoilage should be shown (it is remembered in the meta,
--- so a new run does not repeat it).
function Food.takeReport(world)
  local state = world.state.food
  local report = state.report
  if not report then
    return nil
  end
  state.report = nil
  report.first = not world.meta.spoilExplained
  world.meta.spoilExplained = true
  return report
end

--- Is a spoilage report waiting to be shown?
function Food.hasReport(world)
  return world.state.food.report ~= nil
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
      -- The automatic pantry holds a perishable only as long as it is eaten before it spoils.
      local room = math.max(0, pantryLeft)
      if state.pantryAuto then
        room = math.min(room, Food.pantryHoldDays(world, res) * daily)
      end
      local keep = math.min(amount, math.ceil(room / res.calories))
      pantryLeft = pantryLeft - keep * res.calories
      local rest = amount - keep
      if rest > 0 and res.keepsForWinter and winterLeft > 0 then
        local store = math.min(rest, math.ceil(winterLeft / res.calories))
        winterLeft = winterLeft - store * res.calories
        rest = rest - store
      end
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

--- Is this resource kept away from the roadside stand (truck trips only)? (D62, #106)
function Food.truckOnly(world, id)
  return world.state.food.truckOnly[id] == true
end

--- "Not at the stand" pin: a truck-only good stays in the crate for the next trip instead of being
--- sold by the stand. Independent of the keep/sell/preserve pins.
function Food.setTruckOnly(world, id, truckOnly)
  world.registry:get("resources", id)
  world.state.food.truckOnly[id] = truckOnly and true or nil
end

function Food.setDays(world, pantryDays, winterDays)
  local cfg, state = world.tuning.food, world.state.food
  local days = math.max(0, math.min(cfg.maxPantryDays, pantryDays))
  if days ~= state.pantryDays then
    state.pantryAuto = false -- the player chose a number: it means what it says
  end
  state.pantryDays = days
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
