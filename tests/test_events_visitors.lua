-- The visitors and luck events pack (B9, D194, docs/PLAN_DEPTH.md §6.2, data/content/events.lua): the lost hiker, the traveling
-- peddler, the neighbor on the radio, the stray dog and the windfall. Each option, the free ignore, the supper and market prices.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local EventText = require("src.ui.event_text")
local Events = require("src.sim.systems.events")
local Finds = require("src.sim.systems.finds")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Status = require("src.sim.systems.status")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local VISITORS = { "lost_hiker", "peddler", "radio_neighbor", "stray_dog", "windfall" }

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true
  -- An empty homestead, so every amount in the tests is the one the event moved.
  for _, res in ipairs(reg:all("resources")) do
    local have = Ledger.get(world, res.id)
    if have > 0 then
      Ledger.remove(world, res.id, have)
    end
  end
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function tick(world, n)
  for _ = 1, n or 1 do
    world:tick(STEP)
  end
end

-- Days: spring 1-7, summer 8-14, autumn 15-21, winter 22-28 (daysPerSeason 7).
local SPRING, AUTUMN, WINTER = 5, 16, 25

local function open(world, id)
  world.state.events.budget.day = 0
  T.truthy(Events.force(world, id), "the card opens")
end

local function option(world, index)
  return Events.pending(world).options[index]
end

T.test("visitors: clean two-option content, a free ignore, a note, and nothing is a misfortune", function()
  local world = newWorld()
  T.same(Events.audit(world), {}, "the audit finds nothing: " .. table.concat(Events.audit(world), "; "))
  for _, id in ipairs(VISITORS) do
    local d = reg:get("events", id)
    T.eq(d.class, "visitors", id)
    T.eq(d.bad, false, id)
    T.eq(d.options[1].careful, true, id)
    T.eq(d.options[2].bold, true, id)
    T.eq(d.ignore.cost, nil, id)
    T.eq(next(d.ignore.effect), nil, id .. ": ignoring does nothing at all")
    T.truthy(d.journalNote and reg:has("notes", d.journalNote), id)
    for _, o in ipairs({ d.options[1], d.options[2], d.ignore }) do
      T.falsy(o.risk:find("%d") or o.risk:find("%%"), id .. ": the risk is in words: " .. o.risk)
    end
  end
  T.eq(reg:get("events", "lost_hiker").wake, true, "only the hiker wakes you")
  T.eq(reg:get("events", "peddler").wake, false)
end)

T.test("visitors: ignoring each one leaves the homestead exactly as it was", function()
  for _, id in ipairs(VISITORS) do
    local world = newWorld()
    setTime(world, AUTUMN, 13)
    Inventory.addEquipment(world, "radio")
    world.state.needs.condition = 90
    Ledger.add(world, "wood", 10)
    Ledger.add(world, "money", 10)
    open(world, id)
    T.truthy(Events.ignore(world))
    T.eq(Needs.condition(world), 90, id)
    T.eq(Ledger.get(world, "wood"), 10, id)
    T.eq(Ledger.get(world, "money"), 10, id)
    T.eq(#Status.active(world), 0, id)
    T.eq(#world.state.events.delayed, 0, id)
    T.eq(Inventory.hasEquipment(world, "farm_dog"), false, id)
  end
end)

T.test("visitors: an ignored card expires on its own without a penalty", function()
  local world = newWorld()
  setTime(world, AUTUMN, 13)
  open(world, "peddler")
  Events.advanceReal(world, tun.events.ignoreMinSeconds + 1)
  tick(world, math.ceil(tun.events.ignoreHours * Calendar.hourLength(world) / STEP) + 5)
  T.eq(#world.state.events.pending, 0)
  T.eq(Events.history(world)[1].how, "ignored")
  T.eq(Ledger.get(world, "money"), 0)
end)

T.test("lost hiker: waits for day 5, comes at night, and wakes", function()
  local world = newWorld()
  setTime(world, 3, 22)
  T.eq(Events.weight(world, "lost_hiker"), 0, "not before day 5")
  setTime(world, SPRING, 22)
  T.truthy(Events.weight(world, "lost_hiker") > 0)
  T.eq(reg:get("events", "lost_hiker").when, "night")
  open(world, "lost_hiker")
  T.eq(Events.pending(world).wake, true)
  T.eq(world.state.events.wakeNight > 0, true, "it counts as the night's wake")
end)

T.test("lost hiker: a supper and a fire pay a tip; sending them on is free and leaves a note", function()
  local world = newWorld()
  setTime(world, SPRING, 22)
  Ledger.add(world, "wood", 10)
  open(world, "lost_hiker")
  local cost = option(world, 1).cost
  T.eq(cost.wood, 3, "a night of fuel")
  T.eq(option(world, 1).affordable, false, "no food in the pantry for a supper")
  T.falsy(Events.choose(world, 1))
  T.eq(Ledger.get(world, "wood"), 10, "nothing was taken")

  Ledger.add(world, "egg", 40)
  T.eq(option(world, 1).affordable, true)
  local eggs = option(world, 1).cost.egg
  T.eq(
    eggs,
    math.ceil(tun.events.visitors.mealCalories / reg:get("resources", "egg").calories),
    "the cheapest food that makes a supper"
  )
  T.truthy(Events.choose(world, 1))
  T.eq(Ledger.get(world, "wood"), 7)
  T.eq(Ledger.get(world, "egg"), 40 - eggs)
  T.eq(Ledger.get(world, "money"), 6, "a thank-you in coin")
  T.truthy(Journal.hasNote(world, "kind_stranger"))
  T.eq(#Status.active(world), 0)

  local road = newWorld()
  setTime(road, SPRING, 22)
  Ledger.add(road, "wood", 10)
  open(road, "lost_hiker")
  T.truthy(Events.choose(road, 2))
  T.eq(Ledger.get(road, "wood"), 10)
  T.truthy(Journal.hasNote(road, "turned_hiker"), "a small guilt note, and nothing worse")
  T.eq(Needs.condition(road), Needs.condition(newWorld()))
end)

T.test("lost hiker: the supper is the cheapest stocked food, and canned food is named when there is none", function()
  local world = newWorld()
  open(world, "lost_hiker")
  T.eq(option(world, 1).lacking, "canned_food", "the empty pantry names the fallback food")
  Events.ignore(world)
  Ledger.add(world, "canned_food", 5)
  Ledger.add(world, "egg", 40)
  open(world, "lost_hiker")
  T.truthy(option(world, 1).cost.egg, "eggs are cheaper per supper than a can")
  T.eq(option(world, 1).cost.canned_food, nil)
end)

T.test("peddler: the price comes from the market, in money or in eggs at this week's price", function()
  local world = newWorld()
  setTime(world, SPRING, 13)
  T.truthy(Events.weight(world, "peddler") > 0)
  setTime(world, WINTER, 13)
  T.eq(Events.weight(world, "peddler"), 0, "no cart in the snow")
  setTime(world, SPRING, 13)
  local shop = Market.itemPrice(world, "berries_seeds")
  local fair = shop * tun.events.visitors.peddlerPrice
  open(world, "peddler")
  T.eq(option(world, 1).cost.money, math.ceil(fair), "a share of the shop price")
  T.truthy(option(world, 1).cost.money < shop, "cheaper than the shop")
  local egg = Market.sellPrice(world, "egg")
  T.eq(option(world, 2).cost.egg, math.ceil(fair / egg))
  -- The price follows the week's market.
  world.state.market.prices.egg = 2
  T.eq(option(world, 2).cost.egg, math.ceil(fair / Market.sellPrice(world, "egg")))
  -- The bundle is the catalog item's own.
  T.same(reg:get("events", "peddler").options[1].effect.gain, reg:get("catalog", "berries_seeds").gives)
end)

T.test(
  "peddler: buying pays money and gives the canes; bartering pays eggs; neither is possible without the goods",
  function()
    local world = newWorld()
    setTime(world, SPRING, 13)
    open(world, "peddler")
    T.falsy(Events.choose(world, 1), "no money")
    T.falsy(Events.choose(world, 2), "no eggs")
    local price = option(world, 1).cost.money
    Ledger.add(world, "money", price + 5)
    T.truthy(Events.choose(world, 1))
    T.eq(Ledger.get(world, "money"), 5)
    T.eq(Ledger.get(world, "seed_berries"), 2)

    local barter = newWorld()
    setTime(barter, SPRING, 13)
    open(barter, "peddler")
    local eggs = option(barter, 2).cost.egg
    Ledger.add(barter, "egg", eggs + 3)
    T.truthy(Events.choose(barter, 2))
    T.eq(Ledger.get(barter, "egg"), 3)
    T.eq(Ledger.get(barter, "seed_berries"), 2)
  end
)

T.test("radio neighbor: needs the radio; lending a hand costs an hour and pays, declining is free", function()
  local world = newWorld()
  setTime(world, AUTUMN, 13)
  T.eq(Events.weight(world, "radio_neighbor"), 0, "no radio, no call")
  Inventory.addEquipment(world, "radio")
  T.truthy(Events.weight(world, "radio_neighbor") > 0)
  open(world, "radio_neighbor")
  T.truthy(Events.choose(world, 1))
  T.truthy(Status.has(world, "tending"), "an hour of work")
  T.eq(Ledger.get(world, "money"), 8)
  T.truthy(Journal.hasNote(world, "radio_friend"))

  local decline = newWorld()
  setTime(decline, AUTUMN, 13)
  Inventory.addEquipment(decline, "radio")
  open(decline, "radio_neighbor")
  T.truthy(Events.choose(decline, 2))
  T.eq(Ledger.get(decline, "money"), 0)
  T.eq(#Status.active(decline), 0)
end)

T.test("radio: a find and a catalog item, one per run, and the find is not offered once it is owned", function()
  local item = reg:get("catalog", "radio")
  T.eq(item.equipment, true)
  T.eq(item.unique, true)
  local find = reg:get("finds", "old_radio")
  T.eq(find.effects.equipment[1], "radio")
  local world = newWorld()
  T.truthy(Finds.weight(world, "old_radio") > 0)
  Inventory.addEquipment(world, "radio")
  T.eq(Finds.weight(world, "old_radio"), 0)
end)

T.test("stray dog: once per run, only without a dog; keeping it costs a supper and brings the farm dog", function()
  local world = newWorld()
  setTime(world, AUTUMN, 13)
  T.truthy(Events.weight(world, "stray_dog") > 0)
  Inventory.addEquipment(world, "farm_dog")
  T.eq(Events.weight(world, "stray_dog"), 0, "a dog already keeps watch")

  local keep = newWorld()
  setTime(keep, AUTUMN, 13)
  Ledger.add(keep, "egg", 40)
  open(keep, "stray_dog")
  T.truthy(option(keep, 1).cost.egg)
  T.truthy(Events.choose(keep, 1))
  T.eq(Inventory.hasEquipment(keep, "farm_dog"), true)
  tick(keep, 2)
  T.eq(keep.state.dog.here, true, "the dog arrives on the next tick")
  T.eq(Events.weight(keep, "stray_dog"), 0, "once per run")

  local shoo = newWorld()
  setTime(shoo, AUTUMN, 13)
  open(shoo, "stray_dog")
  T.truthy(Events.choose(shoo, 2))
  T.eq(Inventory.hasEquipment(shoo, "farm_dog"), false)
  T.eq(Events.weight(shoo, "stray_dog"), 0, "it has been seen this run")
end)

T.test("windfall: hauling it is certain, marking it for later may leave nothing", function()
  local world = newWorld()
  setTime(world, AUTUMN, 13)
  open(world, "windfall")
  T.truthy(Events.choose(world, 1))
  T.eq(Ledger.get(world, "wood"), 6)
  T.eq(Ledger.get(world, "scrap"), 3)
  T.truthy(Status.has(world, "tending"))

  for _, chance in ipairs({ 1, 0 }) do
    local later = newWorld()
    later.tuning.events.chances.windfallStays = chance
    setTime(later, AUTUMN, 13)
    open(later, "windfall")
    T.truthy(Events.choose(later, 2))
    T.eq(Ledger.get(later, "wood"), 0, "nothing yet")
    T.eq(#Status.active(later), 0, "no work done")
    setTime(later, AUTUMN + 1, 14)
    tick(later)
    T.eq(Ledger.get(later, "wood"), chance == 1 and 6 or 0)
    T.eq(Ledger.get(later, "scrap"), chance == 1 and 3 or 0)
  end
end)

T.test("visitors: the card says it in words, including the dog that stays", function()
  local env = {
    status = function(id)
      return reg:get("statuses", id)
    end,
    name = function(id)
      return reg:get("resources", id).name
    end,
    item = function(id)
      return reg:get("catalog", id).name
    end,
  }
  local dog = EventText.effectWords(reg:get("events", "stray_dog").options[1].effect, env)
  T.eq(dog[1], "Gain a farm dog for the run")
  local maybe = EventText.effectWords(reg:get("events", "windfall").options[2].effect, env)
  T.truthy(table.concat(maybe, "|"):find("Later, it may"), table.concat(maybe, "|"))
end)

T.test(
  "visitors: standing orders answer them; Careful respects the wood keep, and a short supper falls back",
  function()
    local world = newWorld()
    setTime(world, SPRING, 22)
    world.meta.journal.known[tun.events.ordersPerk] = true
    T.eq(Events.ordersUnlocked(world), true)
    Events.setOrder(world, "visitors", "careful")
    Ledger.add(world, "wood", 20)
    open(world, "lost_hiker")
    T.eq(#world.state.events.pending, 0, "the order answered it")
    local last = Events.history(world)[#Events.history(world)]
    T.eq(last.how, "ignored", "no supper in the pantry: the ignore outcome, nothing lost")
    T.eq(Ledger.get(world, "wood"), 20)

    Events.setOrder(world, "visitors", "bold")
    open(world, "windfall")
    T.eq(#world.state.events.pending, 0)
    T.eq(Events.history(world)[#Events.history(world)].option, 2, "Bold marks the stash for later")
  end
)
