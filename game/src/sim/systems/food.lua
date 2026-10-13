-- Keep targets and surplus (GDD §6.2, D75; replaces the sell crate of D31 and the rules of D38/D68).
--
-- Every good that can be eaten or sold has one **keep target**: the units the homestead holds on to.
-- Stock above it is **surplus**, which is what the roadside stand and the truck load sell. Nothing is
-- moved or reserved here: keep and surplus are numbers read against the ledger, so ages (D73) and
-- storage holds (D59) belong to the stock as before.
--
-- A target is either set by the player in the Pantry (state.food.keep[id], units) or automatic,
-- worked out from the stock every time it is asked for:
--   Food   pantry days of eating (tuning.food.defaultPantryDays) in fresh food, each perishable held
--          only for autoPantryHorizon of its shelf life (D68); winter days (defaultWinterDays) in
--          preserved food first, then fresh food that keeps for winter (potatoes), then fresh food a
--          placed processor can preserve (held for the smoker while the winter stock is short).
--   Fuel   the warmth from tonight to the end of the coming winter (during a winter, the next one
--          too), cautious where the forecast is silent (Readiness.warmthAhead), hottest fuel first.
--   Wood   all of it (tuning.firewood.splitFrom): the woodpile is next year's firewood.
--   Other  0 (scrap, stone: all surplus).
-- Food and fuel the player set by hand count first, so automatic targets fill only what is left.
-- A per-good "truck only" flag keeps a good away from the roadside stand (D62).
--
-- State: world.state.food = { keep = { [id] = units }, truckOnly = { [id] = true },
--                             lastLoss = { day, lost = { { resource, amount }... }, total }?,
--                             report = (same shape)? -- last night's spoilage until the UI has said it }
-- Meta: world.meta.spoilExplained once the first-spoil explanation has been shown (D68, #151).

local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Spoilage = require("src.sim.systems.spoilage")

local Food = {}

function Food.init(world)
  world.state.food = world.state.food or { keep = {}, truckOnly = {} }
  -- Last night's spoilage (food.spoilReport): kept for the pantry panel, and held as a pending
  -- report until the UI has shown it (it waits while the homesteader sleeps).
  world.events:on("food.spoilReport", function(e)
    local day = Calendar.now(world).day
    world.state.food.lastLoss = { day = day, lost = e.lost, total = e.total }
    world.state.food.report = { day = day, lost = e.lost, total = e.total }
  end)
end

--- Can this resource be sold (it has a sale value)?
function Food.sellable(world, id)
  return world.registry:get("resources", id).value ~= nil
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

--- Days of eating the automatic keep holds of this fresh food: the pantry days, cut to a share of how
--- long the food keeps (D68).
function Food.pantryHoldDays(world, res)
  local cfg = world.tuning.food
  local life = Spoilage.shelfLife(world, res.id)
  if life then
    return math.min(cfg.defaultPantryDays, life * cfg.autoPantryHorizon)
  end
  return cfg.defaultPantryDays
end

-- Fuels, hottest first (content order breaks ties), as Needs burns them.
local function fuels(world)
  local list = {}
  for index, res in ipairs(world.registry:all("resources")) do
    if res.heat then
      list[#list + 1] = { res = res, index = index }
    end
  end
  table.sort(list, function(a, b)
    if a.res.heat ~= b.res.heat then
      return a.res.heat > b.res.heat
    end
    return a.index < b.index
  end)
  return list
end

--- Every keep target at once: keep = { [id] = units }, auto = { [id] = true when automatic }.
--- Covers every resource that can be eaten, burned or sold (and wood, the fuel source).
function Food.keeps(world)
  local cfg = world.tuning.food
  local state = world.state.food
  local daily = world.tuning.needs.dailyCalories
  local pantryLeft = cfg.defaultPantryDays * daily
  local winterLeft = cfg.defaultWinterDays * daily
  local resources = world.registry:all("resources")
  local keep, auto = {}, {}

  -- Targets the player set: their food counts toward the pantry, then the winter stock.
  for _, res in ipairs(resources) do
    local set = state.keep[res.id]
    if set then
      keep[res.id] = set
      if res.calories then
        local cal = math.min(Ledger.get(world, res.id), set) * res.calories
        local fromPantry = math.min(math.max(0, pantryLeft), cal)
        pantryLeft = pantryLeft - fromPantry
        winterLeft = winterLeft - (cal - fromPantry)
      end
    end
  end

  -- Preserved food fills the winter stock.
  for _, res in ipairs(resources) do
    if not keep[res.id] and res.calories and not Spoilage.perishable(world, res.id) then
      local n = math.min(Ledger.get(world, res.id), math.ceil(math.max(0, winterLeft) / res.calories))
      winterLeft = winterLeft - n * res.calories
      keep[res.id], auto[res.id] = n, true
    end
  end
  -- Fresh food fills the pantry for as long as it keeps, then tops up the winter stock if it keeps
  -- for winter, then waits for a processor that can preserve it while winter is short.
  local preservable = preservableCategories(world)
  for _, res in ipairs(resources) do
    if not keep[res.id] and res.calories and Spoilage.perishable(world, res.id) then
      local stock = Ledger.get(world, res.id)
      local room = math.min(math.max(0, pantryLeft), Food.pantryHoldDays(world, res) * daily)
      local n = math.min(stock, math.ceil(room / res.calories))
      pantryLeft = pantryLeft - n * res.calories
      if n < stock and res.keepsForWinter and winterLeft > 0 then
        local store = math.min(stock - n, math.ceil(winterLeft / res.calories))
        winterLeft = winterLeft - store * res.calories
        n = n + store
      end
      if n < stock and preservable[res.category] and winterLeft > 0 then
        n = stock -- held for the processor
      end
      keep[res.id], auto[res.id] = n, true
    end
  end

  -- Fuel for the nights to the end of winter (cautious where the forecast is silent), hottest first.
  local efficiency = Needs.heatEfficiency(world)
  local need = Readiness.warmthAhead(world) / (efficiency > 0 and efficiency or 1)
  for _, entry in ipairs(fuels(world)) do
    local res = entry.res
    local stock = Ledger.get(world, res.id)
    if keep[res.id] then
      need = need - math.min(stock, keep[res.id]) * res.heat
    else
      local n = math.min(stock, math.ceil(math.max(0, need) / res.heat))
      need = need - n * res.heat
      keep[res.id], auto[res.id] = n, true
    end
  end
  -- The woodpile is next year's fuel (and the smoker's): all of it is kept unless the player says
  -- otherwise. Selling the fuel the coming winter needs only would leave the winter after short (the
  -- balance harness lost two scripted runs that way, D75).
  local source = world.tuning.firewood.splitFrom
  if not keep[source] then
    keep[source], auto[source] = Ledger.get(world, source), true
  end

  -- Everything else that sells is all surplus unless the player keeps some.
  for _, res in ipairs(resources) do
    if not keep[res.id] and res.value then
      keep[res.id], auto[res.id] = 0, true
    end
  end
  return keep, auto
end

--- The keep target of one good (units) and whether it is automatic.
function Food.keep(world, id)
  local keep, auto = Food.keeps(world)
  return keep[id] or 0, auto[id] == true
end

--- Units above the keep target: what the stand and the truck may sell (0 for goods with no value).
function Food.surplus(world, id)
  if not Food.sellable(world, id) then
    return 0
  end
  return math.max(0, Ledger.get(world, id) - (Food.keep(world, id)))
end

--- Surplus of every sellable good: { [id] = units } (goods with none left out), and the total.
function Food.surpluses(world)
  local keep = Food.keeps(world)
  local out, total = {}, 0
  for _, res in ipairs(world.registry:all("resources")) do
    if res.value then
      local n = math.max(0, Ledger.get(world, res.id) - (keep[res.id] or 0))
      if n > 0 then
        out[res.id] = n
        total = total + n
      end
    end
  end
  return out, total
end

--- Units of the stock inside the keep target (what the homestead holds on to; processors draw on it).
function Food.held(world, id)
  return math.min(Ledger.get(world, id), (Food.keep(world, id)))
end

--- Set a keep target in units (clamped to 0..tuning.food.maxKeep), or nil to go back to automatic.
function Food.setKeep(world, id, units)
  world.registry:get("resources", id)
  if units ~= nil then
    units = math.max(0, math.min(world.tuning.food.maxKeep, math.floor(units)))
  end
  world.state.food.keep[id] = units
end

--- Is this resource kept away from the roadside stand (truck trips only)? (D62, #106)
function Food.truckOnly(world, id)
  return world.state.food.truckOnly[id] == true
end

--- "Not at the stand" pin: a truck-only good's surplus waits for the truck instead of being sold by
--- the stand. Independent of the keep target.
function Food.setTruckOnly(world, id, truckOnly)
  world.registry:get("resources", id)
  world.state.food.truckOnly[id] = truckOnly and true or nil
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

return Food
