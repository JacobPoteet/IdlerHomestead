-- The Techniques page and the first-aid kit (H5 + B10, #388, #354, D199, docs/PLAN_DEPTH.md 12.5): what the player knows and
-- carries changes the options an event offers (a third option, a cost cut, a spared hour), never what is required.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Events = require("src.sim.systems.events")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Status = require("src.sim.systems.status")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(1))
  world.state.footing.held = true
  Ledger.setCapacity(world, "water", 60)
  Ledger.add(world, "wood", 10)
  Ledger.add(world, "water", 5)
  Ledger.add(world, "canned_food", 2)
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function open(world, id)
  world.state.events.budget.day = 0
  T.truthy(Events.force(world, id), "the card opens")
  return Events.pending(world)
end

-- Learn a technique the way the player does: its notes written, then studied.
local function learn(world, id)
  for _, note in ipairs(reg:get("perks", id).needs) do
    Journal.write(world, note)
  end
  T.truthy(Journal.learnNow(world, id), id)
end

local function labels(view)
  local out = {}
  for i, o in ipairs(view.options) do
    out[i] = o.label
  end
  return out
end

T.test("techniques: the content audit passes and the page holds the techniques", function()
  T.same(Events.audit(newWorld()), {})
  local page
  for _, chapter in ipairs(Journal.chapters(newWorld())) do
    if chapter.id == "techniques" then
      page = chapter
    end
  end
  T.truthy(page, "a Techniques chapter")
  local ids = {}
  for _, node in ipairs(page.nodes) do
    ids[#ids + 1] = node.id
  end
  T.same(ids, { "bandaging", "splinting", "haggling" })
end)

T.test("techniques: with nothing known and no kit, the card is the two options it always was", function()
  local world = newWorld()
  for _, id in ipairs({ "sprained_ankle", "torn_ankle", "festering_cut", "back_strain", "stove_burn" }) do
    T.eq(#open(world, id).options, 2, id)
    T.truthy(Events.ignore(world))
  end
end)

T.test("kit: it is a catalog consumable, and a body event offers it as a third option that spends it", function()
  local world = newWorld()
  T.eq(reg:get("catalog", "first_aid_kit").gives.first_aid_kit, 1)
  Ledger.add(world, "first_aid_kit", 2)
  local wood = Ledger.get(world, "wood")
  local view = open(world, "sprained_ankle")
  T.eq(#view.options, 3)
  T.eq(view.options[3].label, "Use a first-aid kit")
  T.eq(view.options[3].cost.first_aid_kit, 1)
  T.truthy(view.options[3].affordable)
  T.truthy(Events.choose(world, 3))
  T.eq(Ledger.get(world, "first_aid_kit"), 1, "one kit spent")
  T.eq(Ledger.get(world, "wood"), wood, "no wood")
  T.eq(Status.count(world), 0, "no slow day")
end)

T.test("kit: a cut dressed from the kit loses no hour, where cleaning it by hand does", function()
  local world = newWorld()
  open(world, "festering_cut")
  T.truthy(Events.choose(world, 1))
  T.truthy(Status.has(world, "tending"), "the hour of work")
  local kit = newWorld()
  Ledger.add(kit, "first_aid_kit", 1)
  T.eq(open(kit, "festering_cut").options[3].label, "Use a first-aid kit")
  T.truthy(Events.choose(kit, 3))
  T.falsy(Status.has(kit, "tending"))
  T.eq(Ledger.get(kit, "water"), 5, "no water either")
end)

T.test("kit: delivery writes the note, and a kit used up takes the option away", function()
  local world = newWorld()
  world.events:emit("market.delivered", { item = "first_aid_kit" })
  T.truthy(Journal.hasNote(world, "kit_bought"))
  Ledger.add(world, "first_aid_kit", 1)
  open(world, "back_strain")
  T.truthy(Events.choose(world, 3))
  T.eq(#open(world, "back_strain").options, 2, "none left")
end)

T.test("splinting: a third option on the sprain and a cheaper splint on the tear", function()
  local world = newWorld()
  T.eq(open(world, "torn_ankle").options[1].cost.canned_food, 1, "the broth, to begin with")
  Events.ignore(world)
  learn(world, "splinting")
  local wood = Ledger.get(world, "wood")
  local sprain = open(world, "sprained_ankle")
  T.same(labels(sprain), { "Splint it", "Power through", "Strap it with a proper splint" })
  T.eq(sprain.options[3].cost.wood, 1)
  T.truthy(Events.choose(world, 3))
  T.eq(Ledger.get(world, "wood"), wood - 1)
  T.falsy(Status.has(world, "ankle_1"), "held firm, no slow day")
  local cans = Ledger.get(world, "canned_food")
  local tear = open(world, "torn_ankle")
  T.same(tear.options[1].cost, { wood = 2 }, "no broth")
  T.truthy(Events.choose(world, 1))
  T.eq(Ledger.get(world, "canned_food"), cans, "the can is kept")
  T.eq(Status.get(world, "ankle_3b").left, 2, "the same two days")
end)

T.test("bandaging: a cut is cleaned without losing the hour", function()
  local world = newWorld()
  learn(world, "bandaging")
  local view = open(world, "festering_cut")
  T.eq(view.options[1].cost.water, 1)
  T.eq(view.options[1].effect.status, nil)
  T.truthy(Events.choose(world, 1))
  T.falsy(Status.has(world, "tending"))
end)

T.test("haggling: the peddler's price comes down by the technique's share", function()
  local world = newWorld()
  setTime(world, 5, 13)
  local fair = Market.itemPrice(world, "berries_seeds") * tun.events.visitors.peddlerPrice
  T.eq(open(world, "peddler").options[1].cost.money, math.ceil(fair))
  Events.ignore(world)
  learn(world, "haggling")
  local share = reg:get("perks", "haggling").modifiers.peddlerDiscount
  T.eq(open(world, "peddler").options[1].cost.money, math.ceil(fair * (1 - share)))
  T.truthy(Events.pending(world).options[1].cost.money < math.ceil(fair))
end)

T.test("techniques: the notes come from play, and a technique is never required", function()
  local world = newWorld()
  T.eq(Journal.status(world, "bandaging"), "unknown")
  world.events:emit("market.delivered", { item = "first_aid_kit" })
  Events.force(world, "festering_cut") -- the first sight of the injury writes its note
  T.eq(Journal.status(world, "bandaging"), "idea")
  Events.ignore(world)
  Events.force(world, "sprained_ankle")
  T.truthy(Events.choose(world, 1), "the base options are always there")
  T.truthy(Journal.hasNote(world, "splint_made"))
  T.eq(Journal.status(world, "splinting"), "idea")
  Events.force(world, "peddler")
  Ledger.add(world, "money", 100)
  T.truthy(Events.choose(world, 1))
  T.eq(Journal.status(world, "haggling"), "idea")
end)

T.test("techniques: a standing order never picks an extra, so a kit or a technique does not change Careful", function()
  local world = newWorld()
  learn(world, "splinting")
  learn(world, "rules_of_thumb")
  Ledger.add(world, "first_aid_kit", 1)
  Ledger.setCapacity(world, "wood", 400)
  Ledger.add(world, "wood", 300) -- enough that paying leaves the wood a winter needs, or Careful falls back (D176)
  local wood = Ledger.get(world, "wood")
  Events.setOrder(world, "body", "careful")
  world.state.events.budget.day = 0
  Events.force(world, "sprained_ankle")
  T.eq(Events.waiting(world), 0, "answered by the order")
  T.eq(Ledger.get(world, "first_aid_kit"), 1, "the kit is kept")
  T.eq(Ledger.get(world, "wood"), wood - 2, "Careful splints it for the base cost")
end)
