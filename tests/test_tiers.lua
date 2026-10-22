-- Tiered upgrades (D198, #382, PLAN_DEPTH 11.1): the cost curve, the ladder rules (replace, require, reputation gate), the
-- buildings' stat hooks and the item card's "next tier" line.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Contracts = require("src.sim.systems.contracts")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Stats = require("src.sim.stats")
local Tiers = require("src.sim.systems.tiers")
local ItemText = require("src.ui.item_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.economy.tiers

local function newWorld()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(1))
  world.control = "active"
  return world
end

-- Everything known, plenty of money: only the purchase rules decide.
local function richWorld()
  local world = newWorld()
  world.meta.journal = world.meta.journal or { known = {} }
  for _, item in ipairs(reg:all("catalog")) do
    world.meta.journal.known[item.id] = true
  end
  Ledger.add(world, "money", 100000)
  return world
end

local function deliverAll(world)
  world.state.calendar.elapsed = world.state.calendar.elapsed + 2 * world.tuning.time.dayLength
  Market.tick(world)
end

local function families()
  local byFamily, order = {}, {}
  for _, item in ipairs(reg:all("catalog")) do
    if item.family then
      if not byFamily[item.family] then
        byFamily[item.family] = {}
        order[#order + 1] = item.family
      end
      byFamily[item.family][item.tier] = item
    end
  end
  return byFamily, order
end

T.test("tiers: the eleven families run tier I to III with no gaps", function()
  local byFamily, order = families()
  T.eq(#order, 11, "rod, bucket, axe, stove, cistern, smoker, panel array, stand, coop and pen, plus the truck bed")
  for _, name in ipairs(order) do
    local tiers = byFamily[name]
    T.truthy(tiers[2] and tiers[3], name .. " has tiers II and III")
    T.eq(tiers[cfg.max + 1], nil, name .. " stops at the cap")
    for n = 2, cfg.max do
      local item = tiers[n]
      T.truthy(item.equipment and item.unique, item.id .. " is unique equipment")
      if tiers[n - 1] then -- the plain bucket (tier I) is not an item, so the big bucket needs nothing
        T.eq(item.requires, tiers[n - 1].id, item.id .. " needs the tier below owned (#264)")
      end
      T.eq(item.price, nil, item.id .. " is priced by the curve")
    end
    T.eq(tiers[3].requires, tiers[2].id, name .. ": III needs II")
    T.eq(tiers[3].replaces, tiers[2].id, name .. ": III replaces II")
  end
end)

T.test("tiers: the price is the exponential curve from the tier I price", function()
  local world = newWorld()
  local byFamily, order = families()
  for _, name in ipairs(order) do
    local tiers = byFamily[name]
    local base = tiers[1] and tiers[1].price or tiers[2].tierBase
    T.truthy(base, name .. " has a reference price")
    local last = 0
    for n = 1, cfg.max do
      local want = math.floor(base * cfg.growth ^ (n - 1) + 0.5)
      if tiers[n] then -- the bucket's tier I is the plain bucket, not an item
        T.eq(Tiers.price(world, tiers[n]), want, tiers[n].id .. " follows the curve")
        T.truthy(want > last, tiers[n].id .. " costs more than the tier below")
      end
      last = want
    end
  end
  -- Known values at growth 2.5: the rod 10 / 25 / 63 and the bucket 5 / 13 / 31.
  T.eq(Tiers.price(world, reg:get("catalog", "sturdy_rod")), 25)
  T.eq(Tiers.price(world, reg:get("catalog", "fine_rod")), 63)
  T.eq(Tiers.price(world, reg:get("catalog", "big_bucket")), 13)
end)

T.test("tiers: Market.itemPrice reads the curve, and a special still discounts it", function()
  local world = richWorld()
  local item = reg:get("catalog", "iron_stove")
  T.eq(Market.itemPrice(world, "iron_stove"), Tiers.price(world, item))
  world.state.market.specials.iron_stove = true
  T.eq(Market.itemPrice(world, "iron_stove"), math.floor(Tiers.price(world, item) * tun.economy.specialDiscount + 0.5))
end)

T.test("tiers: a tier needs the one below, and tier III needs reputation", function()
  local world = richWorld()
  T.eq(Market.cannotBuy(world, "felling_axe", false), "needs the axe")
  T.truthy(Market.order(world, "axe"))
  deliverAll(world)
  T.eq(Market.cannotBuy(world, "felling_axe", false), nil, "tier I owned opens tier II")
  T.eq(Market.cannotBuy(world, "broad_axe", false), "needs contracts", "reputation is checked first")
  world.state.contracts.done = cfg.minDone[3]
  T.eq(Market.cannotBuy(world, "broad_axe", false), "needs the felling axe")
  T.truthy(Market.order(world, "felling_axe"))
  deliverAll(world)
  T.eq(Market.cannotBuy(world, "broad_axe", false), nil)
  T.eq(Contracts.reputation(world), cfg.minDone[3])
end)

T.test("tiers: a higher tier drops the lower ones and they cannot be bought back", function()
  local world = richWorld()
  world.state.contracts.done = cfg.minDone[3]
  Inventory.addEquipment(world, "axe")
  T.eq(Stats.modifier(world, "chopSpeed"), 1)
  Market.order(world, "felling_axe")
  deliverAll(world)
  T.eq(Stats.modifier(world, "chopSpeed"), 2, "tier II replaces tier I, not on top of it")
  Market.order(world, "broad_axe")
  deliverAll(world)
  T.eq(Stats.modifier(world, "chopSpeed"), 3)
  T.falsy(Inventory.hasEquipment(world, "axe"))
  T.falsy(Inventory.hasEquipment(world, "felling_axe"))
  T.eq(Market.cannotBuy(world, "felling_axe", false), "replaced")
  T.eq(Market.cannotBuy(world, "axe", false), "replaced", "the whole ladder below is covered")
  T.eq(Market.cannotBuy(world, "broad_axe", false), "owned")
end)

T.test("tiers: a starting top tier swallows every tier below it", function()
  local world = newWorld()
  Inventory.addEquipment(world, "basic_rod")
  Inventory.addEquipment(world, "sturdy_rod")
  Inventory.addEquipment(world, "fine_rod")
  T.falsy(Inventory.hasEquipment(world, "basic_rod"))
  T.falsy(Inventory.hasEquipment(world, "sturdy_rod"))
  T.eq(Stats.modifier(world, "rod"), 1)
  T.eq(Stats.modifier(world, "maxTension"), reg:get("catalog", "fine_rod").modifiers.maxTension)
end)

T.test("tiers: the stove, array, cistern, coop and pen tiers size every building of the kind", function()
  local world = richWorld()
  local function place(id)
    Inventory.addObject(world, id)
    for i = 1, #world.state.grid.terrain do
      if Inventory.canPlace(world, id, i) then
        T.truthy(Inventory.place(world, id, i))
        return i
      end
    end
    error("no room for " .. id)
  end
  place("cistern")
  place("chicken_coop")
  place("goat_pen")
  place("solar_array")
  place("wood_stove")
  local heat = Needs.heatEfficiency(world)
  local peak = Power.peak(world)
  T.eq(Ledger.capacity(world, "water"), 60)
  T.eq(Ledger.capacity(world, "hen"), 6)
  T.eq(Ledger.capacity(world, "goat"), 3)
  Inventory.addEquipment(world, "lined_cistern")
  Inventory.addEquipment(world, "roomy_coop")
  Inventory.addEquipment(world, "big_pen")
  Inventory.addEquipment(world, "better_cells")
  Inventory.addEquipment(world, "iron_stove")
  T.eq(Ledger.capacity(world, "water"), 90, "a lined cistern holds half again as much")
  T.eq(Ledger.capacity(world, "hen"), 9)
  T.eq(Ledger.capacity(world, "goat"), 5)
  T.near(Power.peak(world), peak + 3 * reg:get("catalog", "better_cells").modifiers.solarOutput, 1e-9)
  T.truthy(
    Needs.heatEfficiency(world) > heat,
    "the stove burns wood further (the starting campfire is the bar to beat)"
  )
  T.near(
    Stats.scale(world, reg:get("objects", "wood_stove")),
    1 + reg:get("catalog", "iron_stove").modifiers.stoveHeat,
    1e-9
  )
  Inventory.addEquipment(world, "deep_cistern")
  T.eq(Ledger.capacity(world, "water"), 120, "tier III replaces tier II: twice, not 1.5 + 1")
end)

T.test("tiers: the smoker tiers shorten a batch", function()
  T.eq(Stats.timeFactor(richWorld(), "smokerSpeed"), 1)
  local world = richWorld()
  Inventory.addEquipment(world, "smoker_flue")
  T.near(Stats.timeFactor(world, "smokerSpeed"), 1 / 1.5, 1e-9)
  T.eq(reg:get("recipes", "smoke_fish").speedStat, "smokerSpeed")
end)

T.test("tiers: the item card names the tier and the next one with its price", function()
  local world = richWorld()
  local function lineOf(card, label)
    for _, line in ipairs(card.lines) do
      if line.label == label then
        return line.text
      end
    end
  end
  local card = ItemText.build(world, "sturdy_rod", false)
  T.eq(lineOf(card, "Tier"), "II of III")
  T.eq(lineOf(card, "Next tier"), "Split-cane rod, $63")
  card = ItemText.build(world, "fine_rod", false)
  T.eq(lineOf(card, "Tier"), "III of III")
  T.eq(lineOf(card, "Next tier"), nil, "the top tier has no next")
  card = ItemText.build(world, "wood_stove", false)
  T.eq(lineOf(card, "Tier"), "I of III")
  T.eq(lineOf(card, "Next tier"), "Cast-iron stove, $150")
  T.eq(
    ItemText.build(world, "radish_seeds", false).lines[1].label ~= "Tier",
    true,
    "items outside a ladder have no tier line"
  )
end)

T.test("tiers: tier III shows why it is locked", function()
  local world = richWorld()
  local card = ItemText.build(world, "hen_house", false)
  T.truthy(card.reason and card.reason:find("contracts", 1, true))
end)
