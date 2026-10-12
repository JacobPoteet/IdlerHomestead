-- Spoilage (GDD §7.2): each day, fresh food loses about 1/spoilDays of its stock.
-- Preserved food (no spoilDays) keeps. Emits "food.spoiled" { resource, category, amount } per
-- resource and then one "food.spoilReport" { lost = { { resource, amount }... }, total } per night
-- (D68), which Food records so the UI can say what rotted instead of losing it silently.
--
-- The model is aggregate on purpose (D38): no batches or ages, just a rate per resource. The
-- accessors below describe that rate and tonight's expected loss, so the pantry can warn before it
-- happens; `daily` uses the same expected value, so what the UI says is what the dice are rolled on.

local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")

local Spoilage = {}

--- How much longer fresh food keeps right now (1 = normal). A powered chest freezer stretches it
--- (GDD §7.5); the effect eases in and out with the freezer's inertia.
function Spoilage.keeps(world)
  return 1 + Power.effect(world, "spoilSlow")
end

--- Units of this resource expected to spoil tonight, as a number (0 for food that keeps). The real
--- loss is floor(expected) plus one more with the fractional chance, never more than the stock.
function Spoilage.expected(world, id)
  local res = world.registry:get("resources", id)
  if not res.spoilDays then
    return 0
  end
  local amount = Ledger.get(world, id)
  return math.min(amount, amount / (res.spoilDays * Spoilage.keeps(world)))
end

--- Share of the stock lost per night (0..1; 0 for food that keeps).
function Spoilage.rate(world, id)
  local res = world.registry:get("resources", id)
  if not res.spoilDays then
    return 0
  end
  return math.min(1, 1 / (res.spoilDays * Spoilage.keeps(world)))
end

--- Everything the UI says about one resource's spoilage, or nil if it keeps:
--- { id, stock, rate, percent, band = "fast"|"steady"|"slow", expected, lo, hi, warn }
--- `lo`..`hi` is the range the real loss tonight falls in (hi = lo or lo + 1).
function Spoilage.info(world, id)
  local res = world.registry:get("resources", id)
  if not res.spoilDays then
    return nil
  end
  local cfg = world.tuning.food
  local rate = Spoilage.rate(world, id)
  local expected = Spoilage.expected(world, id)
  local lo = math.floor(expected)
  local band = "steady"
  if rate >= cfg.spoilFastRate then
    band = "fast"
  elseif rate < cfg.spoilSlowRate then
    band = "slow"
  end
  return {
    id = id,
    stock = Ledger.get(world, id),
    rate = rate,
    percent = math.floor(rate * 100 + 0.5),
    band = band,
    expected = expected,
    lo = lo,
    hi = expected > lo and lo + 1 or lo,
    warn = expected >= cfg.spoilWarnUnits,
  }
end

--- Info for every perishable in stock, in content order, plus the total expected loss and whether
--- any of them is worth a warning: { list = { info... }, expected = n, warn = bool }.
function Spoilage.tonight(world)
  local list, total, warn = {}, 0, false
  for _, res in ipairs(world.registry:all("resources")) do
    if res.spoilDays and Ledger.get(world, res.id) > 0 then
      local info = Spoilage.info(world, res.id)
      list[#list + 1] = info
      total = total + info.expected
      warn = warn or info.warn
    end
  end
  return { list = list, expected = total, warn = warn }
end

--- What slows spoilage, as the code really treats it:
--- { freezer = "none"|"off"|"on", keeps, preserves = { [category] = true } }
--- Only a powered freezer slows it (pantry vs crate, season and a "preserve" pin make no difference);
--- a placed processor (the smoker) turns a category into preserved food, which never spoils.
function Spoilage.slowing(world)
  local freezer = "none"
  for _, obj in pairs(world.state.grid.objects) do
    local sink = world.registry:get("objects", obj.id).sink
    if sink and sink.effects and sink.effects.spoilSlow then
      freezer = Power.effect(world, "spoilSlow") > 0 and "on" or "off"
      break
    end
  end
  local preserves = {}
  local stations = {}
  for _, obj in pairs(world.state.grid.objects) do
    local station = world.registry:get("objects", obj.id).station
    if station then
      stations[station] = true
    end
  end
  for _, recipe in ipairs(world.registry:all("recipes")) do
    if stations[recipe.station] then
      preserves[recipe.inputCategory] = true
    end
  end
  return { freezer = freezer, keeps = Spoilage.keeps(world), preserves = preserves }
end

function Spoilage.daily(world)
  local rng = world:rng("spoilage")
  local lost, total = {}, 0
  for _, res in ipairs(world.registry:all("resources")) do
    if res.spoilDays then
      local amount = Ledger.get(world, res.id)
      if amount > 0 then
        local spoiled = math.min(amount, math.floor(Spoilage.expected(world, res.id) + rng:float()))
        if spoiled > 0 then
          Ledger.remove(world, res.id, spoiled, "spoiled")
          world.events:emit("food.spoiled", { resource = res.id, category = res.category, amount = spoiled })
          lost[#lost + 1] = { resource = res.id, amount = spoiled }
          total = total + spoiled
        end
      end
    end
  end
  if total > 0 then
    world.events:emit("food.spoilReport", { lost = lost, total = total })
  end
end

function Spoilage.init(world)
  world.events:on("calendar.newDay", function()
    Spoilage.daily(world)
  end)
end

return Spoilage
