-- Shelf-life batches (D73, #183), the loss report, the automatic pantry and the gentler start
-- (D68, #151, #163, #161).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Weather = require("src.sim.systems.weather")
local Readiness = require("src.sim.systems.readiness")
local Spoilage = require("src.sim.systems.spoilage")
local Food = require("src.sim.systems.food")
local SpoilText = require("src.ui.spoil_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local DAILY = tun.needs.dailyCalories

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

-- Ages as plain numbers, oldest first: "8@1 4@0" (units@days).
local function shape(world, id)
  local parts = {}
  for _, b in ipairs(Spoilage.batches(world, id)) do
    parts[#parts + 1] = string.format("%g@%g", b.n, b.age)
  end
  return table.concat(parts, " ")
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

-- Shelf lives -----------------------------------------------------------------

T.test("shelf lives: the issue's numbers, from tuning; preserved food keeps", function()
  local world = newWorld(1)
  T.eq(Spoilage.shelfLife(world, "radish"), 7)
  T.eq(Spoilage.shelfLife(world, "egg"), 14)
  T.eq(Spoilage.shelfLife(world, "milk"), 2)
  T.truthy(Spoilage.shelfLife(world, "potato") >= 14, "potatoes keep for weeks")
  for _, res in ipairs(reg:all("resources")) do
    if res.category == "fish" then
      T.truthy(Spoilage.shelfLife(world, res.id) <= 2, res.id .. " keeps a day or two")
    end
    if res.category == "preserved" or not res.calories then
      T.falsy(Spoilage.perishable(world, res.id), res.id .. " never spoils")
    elseif res.category ~= "preserved" then
      T.truthy(Spoilage.perishable(world, res.id), res.id .. " is fresh food with a shelf life")
    end
  end
end)

-- Batches -----------------------------------------------------------------------

T.test("batches: each day's harvest is one batch, older batches age nightly", function()
  local world = newWorld(1)
  Ledger.add(world, "radish", 5, "harvest")
  Ledger.add(world, "radish", 3, "harvest")
  T.eq(shape(world, "radish"), "8@0", "same-day pickings merge")
  Spoilage.daily(world)
  Ledger.add(world, "radish", 4, "harvest")
  T.eq(shape(world, "radish"), "8@1 4@0")
  Spoilage.daily(world)
  T.eq(shape(world, "radish"), "8@2 4@1")
  T.eq(Ledger.get(world, "radish"), 12, "the ledger holds the amounts")
end)

T.test("batches: eating and a truck sale take the oldest first (FIFO)", function()
  local world = newWorld(1)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories and Ledger.get(world, res.id) > 0 then
      Ledger.remove(world, res.id, Ledger.get(world, res.id)) -- only radishes to eat
    end
  end
  local eaten = math.ceil(DAILY / reg:get("resources", "radish").calories)
  Ledger.add(world, "radish", eaten + 2)
  Spoilage.ageStock(world, "radish", 3)
  Ledger.add(world, "radish", 10)
  T.eq(shape(world, "radish"), (eaten + 2) .. "@3 10@0")
  Needs.eat(world)
  T.eq(shape(world, "radish"), "2@3 10@0", "eaten from the old batch")
  -- Keep none and load it all; a truck sale takes the rest of the old batch and then the new.
  Food.setKeep(world, "radish", 0)
  Market.setLoad(world, "radish", 12)
  world.state.market.inTown = true
  Market.sellLoad(world)
  T.eq(Ledger.get(world, "radish"), 0)
  T.eq(shape(world, "radish"), "")
  world.state.market.inTown = false
  -- A partial truck sale takes the oldest units: what stays home is the newest.
  Ledger.add(world, "radish", 5)
  Spoilage.daily(world)
  Ledger.add(world, "radish", 7)
  Market.setLoad(world, "radish", 9)
  world.state.market.inTown = true
  Market.sellLoad(world)
  world.state.market.inTown = false
  T.eq(shape(world, "radish"), "3@0", "the old batch and 4 of the new were sold")
  -- A partial stand sale: the newest units are what is left.
  Ledger.remove(world, "radish", Ledger.get(world, "radish"))
  Ledger.add(world, "radish", 6)
  Spoilage.daily(world)
  Ledger.add(world, "radish", 6)
  Ledger.remove(world, "radish", 8, "stand")
  T.eq(shape(world, "radish"), "4@0")
end)

T.test("batches: keep targets and the truck load never change ages", function()
  local world = newWorld(2)
  Ledger.add(world, "radish", 40)
  Spoilage.ageStock(world, "radish", 3)
  Ledger.add(world, "radish", 10)
  local before = shape(world, "radish")
  T.truthy(Food.surplus(world, "radish") > 0, "the automatic keep leaves some surplus")
  Food.setKeep(world, "radish", 50)
  T.eq(Food.surplus(world, "radish"), 0)
  Food.setKeep(world, "radish", 0)
  T.eq(Food.surplus(world, "radish"), 50)
  Market.setLoad(world, "radish", 30)
  Market.autoLoad(world)
  Market.clearLoad(world)
  Food.setKeep(world, "radish", nil)
  T.eq(shape(world, "radish"), before, "keep and load are counts: ages belong to the stock")
end)

T.test("batches: stock that predates the subscription is reconciled as fresh", function()
  local world = newWorld(3)
  -- The starting kit may be food; whatever perishable stock exists has batches that add up.
  for _, res in ipairs(reg:all("resources")) do
    if Spoilage.perishable(world, res.id) then
      local n = 0
      for _, b in ipairs(Spoilage.batches(world, res.id)) do
        n = n + b.n
      end
      T.eq(n, Ledger.get(world, res.id), res.id)
    end
  end
  -- A test or tool that writes the ledger directly: the accessors read through it, the night fixes it.
  world.state.ledger.amounts.radish = 5
  T.eq(Spoilage.info(world, "radish").stock, 5)
  T.eq(shape(world, "radish"), "5@0")
  Spoilage.daily(world)
  T.eq(shape(world, "radish"), "5@1")
end)

-- The shelf-life boundary -------------------------------------------------------

T.test("shelf life: nothing spoils before it, a share rots each night after it", function()
  local world = newWorld(1)
  local life = Spoilage.shelfLife(world, "radish")
  Ledger.add(world, "radish", 10)
  T.eq(Spoilage.info(world, "radish").daysLeft, life)
  for night = 1, life do
    Spoilage.daily(world)
    T.eq(Ledger.get(world, "radish"), 10, "night " .. night .. ": still fresh")
  end
  local info = Spoilage.info(world, "radish")
  T.eq(info.daysLeft, 0, "it spoils tonight")
  T.eq(info.tonight, math.ceil(10 * tun.food.rotShare))
  T.truthy(info.warn)
  T.eq(info.rotting, 0, "not past its shelf life yet")
  Spoilage.daily(world)
  T.eq(Ledger.get(world, "radish"), 10 - info.tonight, "the first night past the shelf life")
  T.truthy(Spoilage.info(world, "radish").rotting > 0)
  for _ = 1, 10 do
    Spoilage.daily(world)
  end
  T.eq(Ledger.get(world, "radish"), 0, "it all goes within a few nights")
  T.eq(Spoilage.info(world, "radish").daysLeft, nil)
end)

T.test("the playtest complaint: radishes picked in the evening lose nothing overnight", function()
  local world = newWorld(5)
  setTime(world, 3, 20)
  local spoiled = 0
  world.events:on("food.spoiled", function(e)
    spoiled = spoiled + e.amount
  end)
  Ledger.add(world, "radish", 40, "harvest")
  local step = 1 / tun.time.tickRate
  for _ = 1, math.ceil(tun.time.dayLength * 10 / 24 / step) do -- 20:00 to 06:00 next morning
    world:tick(step)
  end
  T.eq(world.state.calendar.day, 4, "a night went by")
  T.eq(spoiled, 0, "nothing rotted (the old model took about a quarter)")
  T.eq(Spoilage.batches(world, "radish")[1].age, 1)
end)

T.test("shelf life: fish keep a day or two, eggs two weeks", function()
  local world = newWorld(1)
  Ledger.add(world, "creek_chub", 4)
  Ledger.add(world, "egg", 4)
  for _ = 1, Spoilage.shelfLife(world, "creek_chub") do
    Spoilage.daily(world)
  end
  T.eq(Ledger.get(world, "creek_chub"), 4)
  Spoilage.daily(world)
  T.truthy(Ledger.get(world, "creek_chub") < 4, "fish rot after their shelf life")
  T.eq(Ledger.get(world, "egg"), 4, "eggs keep")
end)

-- Freezer and preserved food ------------------------------------------------------

T.test("freezer: a powered freezer stretches shelf lives", function()
  local world = newWorld(1)
  Ledger.add(world, "creek_chub", 8)
  T.eq(Spoilage.slowing(world).freezer, "none")
  T.eq(Spoilage.info(world, "creek_chub").daysLeft, 2)
  world.state.power.flow.effects.spoilSlow = 3
  T.near(Spoilage.keeps(world), 4, 1e-9)
  local info = Spoilage.info(world, "creek_chub")
  T.near(info.shelfLife, 8, 1e-9)
  T.eq(info.daysLeft, 8)
  for _ = 1, 8 do
    Spoilage.daily(world)
  end
  T.eq(Ledger.get(world, "creek_chub"), 8, "eight frozen nights are two fresh days")
  Spoilage.daily(world)
  T.truthy(Ledger.get(world, "creek_chub") < 8)
  T.truthy(SpoilText.slowing(world):find("freezer", 1, true))
end)

T.test("preserved food never spoils", function()
  local world = newWorld(1)
  for _, id in ipairs({ "smoked_fish", "canned_food", "cheese" }) do
    Ledger.add(world, id, 5)
    T.eq(Spoilage.info(world, id), nil, id)
    T.eq(#Spoilage.batches(world, id), 0)
  end
  local cans = Ledger.get(world, "canned_food")
  for _ = 1, 60 do
    Spoilage.daily(world)
  end
  T.eq(Ledger.get(world, "smoked_fish"), 5)
  T.eq(Ledger.get(world, "cheese"), 5)
  T.eq(Ledger.get(world, "canned_food"), cans)
end)

T.test("spoilage: slowing notes follow what is placed", function()
  local world = newWorld(1)
  T.falsy(Spoilage.slowing(world).preserves.fish)
  T.truthy(SpoilText.slowing(world):find("Only a powered chest freezer", 1, true))
  T.truthy(SpoilText.slowing(world):find("no difference", 1, true), "pantry vs crate is stated")
end)

-- Accessors and words ------------------------------------------------------------

T.test("accessors: the warning only when something rots tonight", function()
  local world = newWorld(1)
  Ledger.add(world, "radish", 12)
  Ledger.add(world, "creek_chub", 3)
  local tonight = Spoilage.tonight(world)
  T.falsy(tonight.warn, "fresh food is no warning")
  T.eq(tonight.units, 0)
  T.eq(#tonight.list, 2)
  T.truthy(SpoilText.ageLine(Spoilage.info(world, "radish")):find("spoils in 7 days", 1, true))
  Spoilage.daily(world)
  T.truthy(SpoilText.ageLine(Spoilage.info(world, "creek_chub")):find("tomorrow night", 1, true))
  Spoilage.daily(world)
  tonight = Spoilage.tonight(world)
  T.truthy(tonight.warn, "the fish rot tonight")
  T.eq(tonight.units, math.ceil(3 * tun.food.rotShare))
  T.truthy(SpoilText.ageLine(Spoilage.info(world, "creek_chub")):find("spoils tonight", 1, true))
  Spoilage.daily(world)
  T.truthy(SpoilText.ageLine(Spoilage.info(world, "creek_chub")):find("past their shelf life", 1, true))
end)

T.test("words: the explanation names the shelf lives from tuning", function()
  local text = SpoilText.explanation(newWorld(1))
  T.truthy(text:find("fish and milk 2 days", 1, true), text)
  T.truthy(text:find("radish 7 days", 1, true), text)
  T.truthy(text:find("oldest", 1, true))
end)

-- The report and the first-time flag --------------------------------------------

-- Stock at the end of its shelf life, so tonight takes some.
local function addOld(world, id, n)
  Ledger.add(world, id, n)
  Spoilage.ageStock(world, id, Spoilage.shelfLife(world, id))
end

T.test("spoilage: one report a night adds up the per-resource events", function()
  local world = newWorld(3)
  addOld(world, "radish", 40)
  addOld(world, "creek_chub", 10)
  local events, report = 0, nil
  world.events:on("food.spoiled", function(e)
    events = events + e.amount
  end)
  world.events:on("food.spoilReport", function(e)
    report = e
  end)
  Spoilage.daily(world)
  T.truthy(report, "a report was sent")
  T.eq(report.total, events)
  T.eq(report.total, math.ceil(40 * tun.food.rotShare) + math.ceil(10 * tun.food.rotShare))
  local sum = 0
  for _, entry in ipairs(report.lost) do
    sum = sum + entry.amount
  end
  T.eq(sum, report.total)
  T.truthy(Food.hasReport(world))
  T.eq(Food.lastLoss(world).total, report.total)
  T.truthy(SpoilText.summary(world, report):find("Spoiled overnight", 1, true))
end)

T.test("spoilage: no loss, no report", function()
  local world = newWorld(3)
  Ledger.add(world, "radish", 40)
  Spoilage.daily(world)
  T.falsy(Food.hasReport(world))
  T.eq(Food.lastLoss(world), nil)
  T.eq(Food.takeReport(world), nil)
end)

T.test("spoilage: the explanation is flagged once, in the meta", function()
  local meta = {}
  local world = newWorld(3, meta)
  addOld(world, "creek_chub", 10)
  Spoilage.daily(world)
  local first = Food.takeReport(world)
  T.truthy(first.first, "the first report carries the explanation")
  T.truthy(meta.spoilExplained)
  T.falsy(Food.hasReport(world), "taking clears it")
  addOld(world, "creek_chub", 10)
  Spoilage.daily(world)
  T.falsy(Food.takeReport(world).first, "not again")
  -- A new run on the same slot (same meta) does not repeat it either.
  local later = newWorld(4, meta)
  addOld(later, "creek_chub", 10)
  Spoilage.daily(later)
  T.falsy(Food.takeReport(later).first)
end)

T.test("spoilage: the pending report and the batches survive a save", function()
  local meta = {}
  local world = newWorld(3, meta)
  addOld(world, "creek_chub", 10)
  Ledger.add(world, "radish", 6)
  Spoilage.daily(world)
  local data = serialize.decode(serialize.encode({ run = world.state, meta = meta }))
  local restored = World.new({ registry = reg, tuning = tun, meta = data.meta }, data.run)
  T.truthy(Food.hasReport(restored))
  T.truthy(Food.takeReport(restored).first)
  T.eq(shape(restored, "radish"), shape(world, "radish"))
  T.eq(shape(restored, "creek_chub"), shape(world, "creek_chub"))
end)

T.test("spoilage is deterministic", function()
  local function history(seed)
    local world = newWorld(seed)
    local out = {}
    for day = 1, 12 do
      Ledger.add(world, "radish", day * 3)
      Ledger.add(world, "creek_chub", day % 4)
      Ledger.remove(world, "radish", math.min(Ledger.get(world, "radish"), 5), "eat")
      Spoilage.daily(world)
      out[day] = shape(world, "radish") .. "/" .. shape(world, "creek_chub")
    end
    return table.concat(out, " | ")
  end
  T.eq(history(11), history(11))
  T.eq(history(11), history(12), "no dice: the seed does not matter")
end)

-- The automatic pantry (#163) ---------------------------------------------------

T.test("automatic keep: a perishable is held only as long as it is eaten before it spoils", function()
  local world = newWorld(4)
  Ledger.add(world, "radish", 40)
  local radish = reg:get("resources", "radish")
  local keep, auto = Food.keep(world, "radish")
  T.truthy(auto, "new runs start automatic")
  T.eq(keep, math.ceil(Food.pantryHoldDays(world, radish) * DAILY / radish.calories))
  Ledger.add(world, "creek_chub", 30)
  local chub = reg:get("resources", "creek_chub")
  local days = Spoilage.shelfLife(world, "creek_chub") * tun.food.autoPantryHorizon
  T.eq(Food.pantryHoldDays(world, chub), days)
  -- The radishes came first and filled the pantry, so the fish is all surplus; alone it keeps a day.
  Ledger.remove(world, "radish", 40)
  T.eq(Food.keep(world, "creek_chub"), math.ceil(days * DAILY / chub.calories))
end)

T.test("automatic keep: a small stock is all kept, and potatoes keep up to the pantry days", function()
  local world = newWorld(4)
  Ledger.add(world, "creek_chub", 5)
  T.eq(Food.surplus(world, "creek_chub"), 0)
  -- Potatoes: their shelf life * the horizon is more than the 3-day setting, so the setting rules.
  T.eq(Food.pantryHoldDays(world, reg:get("resources", "potato")), tun.food.defaultPantryDays)
  T.truthy(Food.pantryHoldDays(world, reg:get("resources", "creek_chub")) < tun.food.defaultPantryDays)
end)

T.test("automatic keep: wood is kept for the nights to the end of winter, whatever the store holds (D104)", function()
  local world = newWorld(4)
  local need = Readiness.warmthAhead(world)
  T.truthy(need > 0, "a winter is coming")
  local perWood = Needs.warmthPerWood(world)
  local logs = math.ceil(need / perWood - 1e-9)
  Ledger.add(world, "wood", 5)
  T.eq(Food.surplus(world, "wood"), 0, "far less wood than winter needs: all kept")
  Ledger.setCapacity(world, "wood", math.huge) -- (what woodsheds do)
  Ledger.add(world, "wood", logs + 7 - Ledger.get(world, "wood"))
  T.eq(Food.surplus(world, "wood"), 7, "exactly the wood beyond the cautious need is spare")
  Food.setKeep(world, "wood", 0)
  T.eq(Food.surplus(world, "wood"), Ledger.get(world, "wood"), "the player can sell it all")
end)

T.test("readiness: the wood to keep is cautious until the forecast is known, and spans two winters in winter", function()
  local world = newWorld(4)
  local t, w = tun.time, tun.weather
  local function nightSum(season, from)
    local sum = 0
    for d = from or 1, t.daysPerSeason do
      sum = sum + Weather.baseWarmth(world, season, d)
    end
    return sum
  end
  -- Day 1 of year 1, nothing forecast: every season to the end of winter at the worst severity, plus
  -- the longest cold snap on the hardest winter night.
  local worst = w.severityMax
  local peak = tun.needs.warmthPeak
  local expected = nightSum("spring") + nightSum("summer") + nightSum("autumn") + nightSum("winter") * worst
    + peak * worst * w.snapDaysMax * (w.snapMultiplier - 1)
  local winters = tun.food.keepWinters
  tun.food.keepWinters = 1 -- one winter ahead: exactly the nights to the end of this winter
  T.near(Readiness.warmthAhead(world), expected, 1e-6)
  tun.food.keepWinters = winters
  T.truthy(Readiness.warmthAhead(world) > expected, "the tuned horizon (keepWinters = " .. winters .. ") reaches into the winter after")
  tun.food.keepWinters = 1
  -- A frozen day counts the rest of this winter and all of the next year.
  local day = 3 * t.daysPerSeason + 2
  world.state.calendar.elapsed = ((day - 1 + 12 / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
  local thisWinter = nightSum("winter", 2) * (w.severityMax + w.severityPerYear) * w.snapMultiplier
  local frozen = Readiness.warmthAhead(world)
  tun.food.keepWinters = winters
  T.truthy(frozen > thisWinter, "in winter the keep still covers the next winter")
  T.truthy(Readiness.warmthAhead(world) > frozen, "and a longer tuned horizon keeps more")
end)

-- The gentler start (#161) ------------------------------------------------------

T.test("gentler start: the kit has the cans and the dollars from tuning", function()
  local world = newWorld(2)
  T.eq(Ledger.get(world, "canned_food"), tun.run.startingResources.canned_food)
  T.eq(Ledger.get(world, "money"), tun.run.startingResources.money)
  T.truthy(tun.run.startingResources.money > 0)
  -- The first catalog order (the cheapest starter item plus the delivery fee) is within reach.
  local cheapest = math.huge
  for _, item in ipairs(reg:all("catalog")) do
    if item.starter then
      cheapest = math.min(cheapest, item.price)
    end
  end
  T.truthy(tun.run.startingResources.money >= cheapest + tun.economy.deliveryFee, "the cheapest starter order is affordable on day one")
end)

-- Meal order (D94, #189) -----------------------------------------------------

local function clearFood(world)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories and Ledger.get(world, res.id) > 0 then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
end

local function stockedOrder(world)
  local order = {}
  for _, res in ipairs(Needs.mealOrder(world)) do
    if Ledger.get(world, res.id) > 0 then
      order[#order + 1] = res.id
    end
  end
  return table.concat(order, " ")
end

T.test("meal order: the food whose oldest batch spoils first is eaten first; preserved food last", function()
  local world = newWorld(1)
  clearFood(world)
  Ledger.add(world, "potato", 5)
  Spoilage.ageStock(world, "potato", 20) -- shelf life 21 days: spoils tomorrow
  Ledger.add(world, "radish", 5) -- fresh, 7 days
  Ledger.add(world, "egg", 5) -- fresh, 14 days
  Ledger.add(world, "milk", 5) -- fresh, 2 days
  Ledger.add(world, "smoked_fish", 5) -- never spoils
  T.eq(stockedOrder(world), "potato milk radish egg smoked_fish")
end)

T.test("meal order: a day's meal eats the old potatoes before fresh radishes", function()
  local world = newWorld(1)
  clearFood(world)
  local spuds = math.ceil(DAILY / reg:get("resources", "potato").calories)
  Ledger.add(world, "potato", spuds)
  Spoilage.ageStock(world, "potato", 20)
  Ledger.add(world, "radish", 10)
  Needs.eat(world)
  T.eq(Ledger.get(world, "potato"), 0, "the soon-to-rot food was eaten")
  T.eq(Ledger.get(world, "radish"), 10, "the fresh radishes were left")
end)

T.test("meal order: equal days left fall back to content-file order", function()
  local world = newWorld(1)
  clearFood(world)
  Ledger.add(world, "radish", 5)
  Ledger.add(world, "potato", 5)
  Spoilage.ageStock(world, "potato", 14) -- 7 days left, like the fresh radishes
  T.eq(Spoilage.info(world, "radish").daysLeft, Spoilage.info(world, "potato").daysLeft)
  T.eq(stockedOrder(world), "radish potato")
end)
