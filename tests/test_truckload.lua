-- Keep targets, surplus and the truck load (GDD §6.2, §6.4, D75, #196, #195).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Food = require("src.sim.systems.food")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Spoilage = require("src.sim.systems.spoilage")
local Load = require("src.scenes.load")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local CARGO = tun.economy.cargoCapacity

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.market.prices = {} -- plain prices (x1) so the order is the content values
  return world
end

--- Add `n` of a resource and keep none, so it is all surplus.
local function spare(world, id, n)
  Ledger.add(world, id, n)
  Food.setKeep(world, id, 0)
end

local function goTown(world)
  world.state.power.charge[world.state.land.truck] = tun.economy.tripCost
  T.truthy(Market.startTrip(world))
end

-- Values (#195) --------------------------------------------------------------------------------------

T.test("values: wood, stone and scrap can be sold", function()
  for _, id in ipairs({ "wood", "stone", "scrap" }) do
    T.truthy(Food.sellable(newWorld(), id), id)
    T.truthy(reg:get("resources", id).value > 0, id)
  end
end)

T.test("values: a broke player can fill the truck with wood and sell it", function()
  local world = newWorld()
  Ledger.add(world, "wood", 60)
  T.eq(Food.surplus(world, "wood"), 0, "the automatic keep holds the wood the winter will burn")
  local loaded, reason = Market.setLoad(world, "wood", CARGO)
  T.eq(reason, "reserve", "loading kept wood asks first")
  T.eq(loaded, 0)
  loaded = Market.setLoad(world, "wood", CARGO, true)
  T.eq(loaded, CARGO, "confirmed: the truck takes a full cargo of wood")
  goTown(world)
  local money = Ledger.get(world, "money")
  local factor = Market.satFactor(world, "wood", CARGO)
  local earned = Market.sellLoad(world)
  T.eq(earned, math.floor(CARGO * Market.sellPrice(world, "wood") * factor + 0.5))
  T.eq(Ledger.get(world, "money"), money + earned)
  T.eq(Ledger.get(world, "wood"), 60 - CARGO)
end)

-- Surplus ---------------------------------------------------------------------------------------------

T.test("surplus: stock above the keep, never negative, totals add up", function()
  local world = newWorld()
  Ledger.add(world, "scrap", 12)
  Ledger.add(world, "stone", 5)
  Food.setKeep(world, "stone", 8)
  T.eq(Food.surplus(world, "scrap"), 12)
  T.eq(Food.surplus(world, "stone"), 0, "more kept than in stock: no surplus")
  local all, total = Food.surpluses(world)
  T.eq(all.scrap, 12)
  T.eq(all.stone, nil)
  local sum = 0
  for _, n in pairs(all) do
    sum = sum + n
  end
  T.eq(total, sum)
end)

-- Loading ---------------------------------------------------------------------------------------------

T.test("load: limited by cargo and by stock", function()
  local world = newWorld()
  spare(world, "scrap", CARGO + 15)
  spare(world, "stone", 5)
  local n, reason = Market.setLoad(world, "scrap", CARGO + 15)
  T.eq(n, CARGO)
  T.eq(reason, "cargo full")
  T.eq(Market.cargoLeft(world), 0)
  n, reason = Market.setLoad(world, "stone", 3)
  T.eq(n, 0, "no room left")
  T.eq(reason, "cargo full")
  Market.setLoad(world, "scrap", 10)
  n, reason = Market.setLoad(world, "stone", 9)
  T.eq(n, 5, "only what is in stock")
  T.eq(reason, "stock")
  T.eq(Market.loadUnits(world), 15)
  T.eq(Market.setLoad(world, "seed_radish", 1), 0, "goods with no value can't be loaded")
end)

T.test("load: equipment with a cargo modifier raises the limit", function()
  local world = newWorld()
  T.eq(Market.cargoCapacity(world), CARGO)
  local found
  for _, item in ipairs(reg:all("catalog")) do
    if item.equipment and item.modifiers and item.modifiers.cargo then
      found = item
    end
  end
  if found then
    Inventory.addEquipment(world, found.id)
    T.eq(Market.cargoCapacity(world), CARGO + found.modifiers.cargo)
  end
end)

T.test("auto-load: highest price first, then what spoils soonest, never below a keep", function()
  local world = newWorld()
  spare(world, "rainbow_trout", 2) -- $15
  spare(world, "sunfish", 10) -- $3, spoils in 2 days
  spare(world, "milk", 10) -- $3, spoils in 2 days, later in content order
  spare(world, "stone", 50) -- $1
  Ledger.add(world, "brook_trout", 30) -- $7, automatic keep holds some back
  Spoilage.ageStock(world, "milk", 1) -- the milk spoils sooner than the sunfish now
  local troutKeep = Food.keep(world, "brook_trout")
  local added = Market.autoLoad(world)
  T.eq(added, CARGO)
  T.eq(Market.loaded(world, "rainbow_trout"), 2)
  T.eq(Market.loaded(world, "brook_trout"), 30 - troutKeep, "only the trout above its keep")
  local left = CARGO - 2 - (30 - troutKeep)
  local milk = math.min(10, left)
  T.eq(Market.loaded(world, "milk"), milk, "the milk spoils first")
  T.eq(Market.loaded(world, "sunfish"), math.min(10, left - milk))
  T.eq(Market.loaded(world, "stone"), math.max(0, left - milk - 10), "the cheapest last")
  T.eq(Market.autoLoad(world), 0, "a full truck takes nothing more")
end)

T.test("auto-load: fills what is left around a manual load", function()
  local world = newWorld()
  spare(world, "scrap", 30)
  spare(world, "stone", 30)
  Market.setLoad(world, "stone", 25)
  Market.autoLoad(world)
  T.eq(Market.loaded(world, "stone"), 25, "the manual load stays")
  T.eq(Market.loaded(world, "scrap"), CARGO - 25)
end)

T.test("load: can't change the load in town (the goods are at home)", function()
  local world = newWorld()
  spare(world, "scrap", 10)
  goTown(world)
  local n, reason = Market.setLoad(world, "scrap", 5)
  T.eq(n, 0)
  T.eq(reason, "in town")
  T.eq(Market.autoLoad(world), 0)
end)

T.test("load: follows the stock when goods are eaten or spoil", function()
  local world = newWorld()
  spare(world, "radish", 10)
  Market.setLoad(world, "radish", 10)
  Ledger.remove(world, "radish", 4, "eat")
  T.eq(Market.loaded(world, "radish"), 6)
  Ledger.remove(world, "radish", 6, "spoiled")
  T.eq(Market.loaded(world, "radish"), 0)
  T.eq(Market.loadUnits(world), 0)
end)

-- Reserve guard ----------------------------------------------------------------------------------------

T.test("reserve guard: loading into a keep target asks, and says what winter would lack", function()
  local world = newWorld()
  Ledger.add(world, "wood", 10) -- 14 with the starting kit
  T.eq(Food.surplus(world, "wood"), 0)
  local w = Market.loadWarning(world, "wood", 4)
  T.truthy(w)
  T.eq(w.kind, "fuel")
  T.eq(w.below, 4)
  local n, reason = Market.setLoad(world, "wood", 4)
  T.eq(reason, "reserve")
  T.eq(n, 0, "nothing changes without confirmation")
  T.eq(Market.setLoad(world, "wood", 4, true), 4)
  T.eq(Market.loadWarning(world, "wood", 2), nil, "unloading never asks")
  local title, message = Load.warningText(world, w)
  T.truthy(title:find("wood", 1, true), title)
  T.truthy(message:find("4 Wood", 1, true), message)
  -- Food: the warning names the days of food in stock.
  Ledger.add(world, "potato", 10)
  local food = Market.loadWarning(world, "potato", 10)
  T.eq(food.kind, "food")
  local _, text = Load.warningText(world, food)
  T.truthy(text:find(string.format("%.1f days of food", Needs.foodDays(world)), 1, true), text)
  -- Within the surplus there is nothing to ask.
  spare(world, "scrap", 5)
  T.eq(Market.loadWarning(world, "scrap", 5), nil)
  T.eq(select(2, Market.setLoad(world, "scrap", 5)), nil)
  -- A good the player keeps on purpose asks too, in plain words.
  Ledger.add(world, "stone", 6)
  Food.setKeep(world, "stone", 6)
  local stone = Market.loadWarning(world, "stone", 2)
  T.eq(stone.kind, "stock")
  T.truthy(select(2, Load.warningText(world, stone)):find("from the 6 you keep", 1, true))
end)

-- Selling -------------------------------------------------------------------------------------------------

T.test("sell the load: sells exactly what is loaded; everything else stays home", function()
  local world = newWorld()
  spare(world, "scrap", 20)
  spare(world, "sunfish", 6)
  Market.setLoad(world, "scrap", 12)
  local sold = {}
  world.events:on("market.sold", function(e)
    sold[#sold + 1] = e
  end)
  T.eq(Market.sellLoad(world), 0, "not in town")
  goTown(world)
  local expected = 12 * Market.sellPrice(world, "scrap")
  T.eq(Market.sellLoad(world), expected)
  T.eq(Ledger.get(world, "scrap"), 8)
  T.eq(Ledger.get(world, "sunfish"), 6, "unloaded goods stayed home")
  T.eq(Market.loadUnits(world), 0)
  T.eq(#sold, 1)
  T.eq(sold[1].units, 12)
  T.eq(Market.sellLoad(world), 0, "nothing left to sell")
  T.eq(#sold, 1, "an empty sale says nothing")
end)

T.test("sell the load: the home panel's numbers match the sale", function()
  local world = newWorld()
  spare(world, "scrap", 9)
  Market.autoLoad(world)
  local trip = Market.tripStatus(world)
  goTown(world)
  T.eq(Market.sellLoad(world), trip.value)
end)

-- Determinism and saves ------------------------------------------------------------------------------------

T.test("truck load: deterministic, and the load survives a save", function()
  local function run(seed)
    local world = newWorld(seed)
    spare(world, "creek_chub", 15)
    spare(world, "radish", 30)
    spare(world, "stone", 20)
    Spoilage.ageStock(world, "radish", 2)
    Market.autoLoad(world)
    return world, serialize.encode(world.state.market.load)
  end
  local a, la = run(3)
  local _, lb = run(3)
  T.eq(la, lb)
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  T.eq(Market.loadUnits(restored), Market.loadUnits(a))
  T.eq(Market.loaded(restored, "creek_chub"), Market.loaded(a, "creek_chub"))
end)
