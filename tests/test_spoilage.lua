-- Spoilage accessors, the loss report, the automatic pantry and the gentler start (D68, #151, #163, #161).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Ledger = require("src.sim.systems.ledger")
local Spoilage = require("src.sim.systems.spoilage")
local Food = require("src.sim.systems.food")
local SpoilText = require("src.ui.spoil_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local DAILY = tun.needs.dailyCalories

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

-- Accessors ------------------------------------------------------------------

T.test("spoilage info: rate, expected loss, band and warning", function()
  local world = newWorld(1)
  Ledger.add(world, "radish", 12)
  local info = Spoilage.info(world, "radish")
  T.near(info.rate, 1 / reg:get("resources", "radish").spoilDays, 1e-9)
  T.eq(info.percent, 25)
  T.near(info.expected, 3, 1e-9)
  T.eq(info.lo, 3)
  T.eq(info.hi, 3)
  T.eq(info.band, "fast")
  T.truthy(info.warn, "3 expected tonight is a warning")
  Ledger.add(world, "potato", 4)
  local potato = Spoilage.info(world, "potato")
  T.eq(potato.band, "slow")
  T.falsy(potato.warn)
  T.eq(potato.lo, 0)
  T.eq(potato.hi, 1, "a fraction can still take one")
  T.eq(Spoilage.info(world, "canned_food"), nil, "preserved food keeps")
  T.eq(Spoilage.rate(world, "canned_food"), 0)
  T.eq(Spoilage.expected(world, "canned_food"), 0)
end)

T.test("spoilage info: a small stock is not a warning", function()
  local world = newWorld(1)
  Ledger.add(world, "radish", 2) -- 0.5 expected
  local info = Spoilage.info(world, "radish")
  T.falsy(info.warn)
  T.eq(info.lo, 0)
  T.eq(info.hi, 1)
  T.falsy(Spoilage.tonight(world).warn)
  Ledger.add(world, "creek_chub", 4) -- 2 expected
  local tonight = Spoilage.tonight(world)
  T.truthy(tonight.warn)
  T.near(tonight.expected, 2.5, 1e-9)
  T.eq(#tonight.list, 2)
end)

T.test("spoilage: the real loss stays in the shown range and averages the expected loss", function()
  local sum, n = 0, 400
  for seed = 1, n do
    local world = newWorld(seed)
    Ledger.add(world, "radish", 5)
    local info = Spoilage.info(world, "radish")
    Spoilage.daily(world)
    local lost = 5 - Ledger.get(world, "radish")
    T.truthy(lost >= info.lo and lost <= info.hi, "loss " .. lost .. " outside " .. info.lo .. ".." .. info.hi)
    sum = sum + lost
  end
  T.near(sum / n, 5 / reg:get("resources", "radish").spoilDays, 0.1)
end)

T.test("spoilage: a powered freezer slows the rate the accessors report", function()
  local world = newWorld(1)
  Ledger.add(world, "creek_chub", 8)
  T.near(Spoilage.rate(world, "creek_chub"), 0.5, 1e-9)
  T.eq(Spoilage.slowing(world).freezer, "none")
  world.state.power.flow.effects.spoilSlow = 3
  T.near(Spoilage.keeps(world), 4, 1e-9)
  T.near(Spoilage.rate(world, "creek_chub"), 0.125, 1e-9)
  T.near(Spoilage.expected(world, "creek_chub"), 1, 1e-9)
  T.truthy(SpoilText.slowing(world):find("freezer", 1, true))
end)

T.test("spoilage: slowing notes follow what is placed", function()
  local world = newWorld(1)
  T.falsy(Spoilage.slowing(world).preserves.fish)
  T.truthy(SpoilText.slowing(world):find("Only a powered chest freezer", 1, true))
  T.truthy(SpoilText.slowing(world):find("no difference", 1, true), "pantry vs crate is stated")
end)

-- The report and the first-time flag --------------------------------------------

T.test("spoilage: one report a night adds up the per-resource events", function()
  local world = newWorld(3)
  Ledger.add(world, "radish", 40)
  Ledger.add(world, "creek_chub", 10)
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
  Spoilage.daily(world)
  T.falsy(Food.hasReport(world))
  T.eq(Food.lastLoss(world), nil)
  T.eq(Food.takeReport(world), nil)
end)

T.test("spoilage: the explanation is flagged once, in the meta", function()
  local meta = {}
  local world = newWorld(3, meta)
  Ledger.add(world, "creek_chub", 10)
  Spoilage.daily(world)
  local first = Food.takeReport(world)
  T.truthy(first.first, "the first report carries the explanation")
  T.truthy(meta.spoilExplained)
  T.falsy(Food.hasReport(world), "taking clears it")
  Ledger.add(world, "creek_chub", 10)
  Spoilage.daily(world)
  T.falsy(Food.takeReport(world).first, "not again")
  -- A new run on the same slot (same meta) does not repeat it either.
  local later = newWorld(4, meta)
  Ledger.add(later, "creek_chub", 10)
  Spoilage.daily(later)
  T.falsy(Food.takeReport(later).first)
end)

T.test("spoilage: the pending report survives a save", function()
  local meta = {}
  local world = newWorld(3, meta)
  Ledger.add(world, "creek_chub", 10)
  Spoilage.daily(world)
  local data = serialize.decode(serialize.encode({ run = world.state, meta = meta }))
  local restored = World.new({ registry = reg, tuning = tun, meta = data.meta }, data.run)
  T.truthy(Food.hasReport(restored))
  T.truthy(Food.takeReport(restored).first)
end)

T.test("spoilage is deterministic for a seed", function()
  local function history(seed)
    local world = newWorld(seed)
    Ledger.add(world, "radish", 30)
    Ledger.add(world, "creek_chub", 14)
    local out = {}
    for day = 1, 8 do
      Spoilage.daily(world)
      out[day] = Ledger.get(world, "radish") .. "/" .. Ledger.get(world, "creek_chub")
    end
    return table.concat(out, " ")
  end
  T.eq(history(11), history(11))
end)

-- The automatic pantry (#163) ---------------------------------------------------

T.test("automatic pantry: a perishable is held only as long as it is eaten before it spoils", function()
  local world = newWorld(4)
  T.truthy(Food.pantryAuto(world), "new runs start automatic")
  Ledger.add(world, "radish", 40)
  Food.sort(world)
  local radish = reg:get("resources", "radish")
  local held = 40 - world.state.food.crate.radish
  T.eq(held, math.ceil(radish.spoilDays * tun.food.autoPantryHorizon * DAILY / radish.calories))
  T.truthy(held * radish.calories <= radish.spoilDays * tun.food.autoPantryHorizon * DAILY + radish.calories)
  Ledger.add(world, "creek_chub", 30)
  Food.sort(world)
  local chub = reg:get("resources", "creek_chub")
  T.eq(30 - world.state.food.crate.creek_chub, math.ceil(chub.spoilDays * tun.food.autoPantryHorizon * DAILY / chub.calories))
end)

T.test("automatic pantry: a small stock is all kept, and potatoes keep up to the pantry setting", function()
  local world = newWorld(4)
  Ledger.add(world, "creek_chub", 5)
  Food.sort(world)
  T.eq(world.state.food.crate.creek_chub, nil)
  -- Potatoes: 20 days * the horizon is more than the 3-day setting, so the setting rules.
  T.eq(Food.pantryHoldDays(world, reg:get("resources", "potato")), tun.food.defaultPantryDays)
  T.truthy(Food.pantryHoldDays(world, reg:get("resources", "creek_chub")) < tun.food.defaultPantryDays)
end)

T.test("automatic pantry: explicit pins work exactly as before", function()
  local world = newWorld(4)
  Ledger.add(world, "radish", 40)
  Food.setPin(world, "radish", "keep")
  T.eq(world.state.food.crate.radish, nil)
  Food.setPin(world, "radish", "sell")
  T.eq(world.state.food.crate.radish, 40)
  Food.setPin(world, "radish", "preserve")
  T.eq(world.state.food.crate.radish, nil)
  Food.setPin(world, "radish", nil)
  T.truthy(world.state.food.crate.radish > 0)
  T.truthy(Food.pantryAuto(world), "pins do not touch the mode")
end)

T.test("automatic pantry: moving the stepper makes the number mean what it says", function()
  local world = newWorld(4)
  Ledger.add(world, "radish", 60)
  Food.setDays(world, world.state.food.pantryDays, 5) -- winter stepper only
  T.truthy(Food.pantryAuto(world))
  Food.setDays(world, 4, 5)
  T.falsy(Food.pantryAuto(world))
  T.eq(world.state.food.crate.radish, 60 - math.ceil(4 * DAILY / 300))
  Food.setPantryAuto(world, true)
  T.truthy(world.state.food.crate.radish > 60 - math.ceil(4 * DAILY / 300), "automatic holds less")
end)

T.test("automatic pantry: an older save keeps its saved rule", function()
  local meta = {}
  local world = newWorld(4, meta)
  world.state.food.pantryAuto = nil -- how a pre-D68 save looks
  local data = serialize.decode(serialize.encode({ run = world.state, meta = meta }))
  local old = World.new({ registry = reg, tuning = tun, meta = data.meta }, data.run)
  T.falsy(Food.pantryAuto(old))
  Ledger.add(old, "radish", 40)
  Food.sort(old)
  T.eq(old.state.food.crate.radish, 40 - math.ceil(tun.food.defaultPantryDays * DAILY / 300), "three whole days, as before")
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
