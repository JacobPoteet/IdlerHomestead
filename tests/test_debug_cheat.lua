-- Debug cheat mode (GDD D126): the Catalog lists every item, and Market.debugGrant hands one over free and at once.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Income = require("src.sim.systems.income")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local ItemText = require("src.ui.item_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(1))
  world.control = "active"
  return world
end

T.test("cheat: off by default, and the list is gated by the journal", function()
  local world = newWorld()
  T.falsy(Market.cheatOn(world))
  T.falsy(Market.debugGrant(world, "woodshed"))
  T.truthy(#Market.catalogList(world) < #reg:all("catalog"))
end)

T.test("cheat: the list shows every catalog item, even unknown ones", function()
  local world = newWorld()
  Market.setCheat(world, true)
  T.eq(#Market.catalogList(world), #reg:all("catalog"))
  Market.setCheat(world, false)
  T.truthy(#Market.catalogList(world) < #reg:all("catalog"))
end)

T.test("cheat: every catalog item can be granted (prerequisites first), money and stats untouched", function()
  local world = newWorld()
  Market.setCheat(world, true)
  local money = Ledger.get(world, "money")
  local sold = 0
  world.events:on("market.sold", function()
    sold = sold + 1
  end)
  world.events:on("stand.sold", function()
    sold = sold + 1
  end)
  local granted = {}
  for _ = 1, 3 do -- a few passes: animals need their housing placed, goats the trailer
    for _, item in ipairs(reg:all("catalog")) do
      if not granted[item.id] and Market.debugGrant(world, item.id) then
        granted[item.id] = true
        if item.id == "chicken_coop" or item.id == "goat_pen" then
          for i = 1, #world.state.grid.terrain do
            if Inventory.canPlace(world, item.object, i) then
              T.truthy(Inventory.place(world, item.object, i))
              break
            end
          end
        end
      end
    end
  end
  for _, item in ipairs(reg:all("catalog")) do
    local why = Market.cannotBuy(world, item.id, true)
    -- Granted, or a better tier granted later covers it (D115: the basic rod under the sturdy one).
    T.truthy(granted[item.id] or why == "replaced", item.id .. " grantable: " .. tostring(why))
  end
  T.eq(Ledger.get(world, "money"), money)
  T.eq(Income.total(world), 0)
  T.eq(sold, 0)
  T.eq(#world.state.market.orders, 0)
end)

T.test("cheat: a unique item is refused a second time; upgrades replace per D115", function()
  local world = newWorld()
  Market.setCheat(world, true)
  T.truthy(Market.debugGrant(world, "woodshed"))
  T.eq(Inventory.objectCount(world, "woodshed"), 1)
  local ok, reason = Market.debugGrant(world, "woodshed")
  T.falsy(ok)
  T.eq(reason, "owned")
  T.eq(Inventory.objectCount(world, "woodshed"), 1)
  T.truthy(Market.debugGrant(world, "camp"))
  T.truthy(Market.debugGrant(world, "shack"))
  T.eq(Market.cannotBuy(world, "camp", false), "owned") -- the shack replaces it once placed
end)

T.test("cheat: a consumable adds its gives right away, and Market.order is a free grant too", function()
  local world = newWorld()
  Market.setCheat(world, true)
  local money = Ledger.get(world, "money")
  local gives = reg:get("catalog", "radish_seeds").gives
  local res = next(gives)
  local before = Ledger.get(world, res)
  T.truthy(Market.order(world, "radish_seeds"))
  T.eq(Ledger.get(world, res), before + gives[res])
  T.eq(#world.state.market.orders, 0)
  T.eq(Ledger.get(world, "money"), money)
end)

T.test("cheat: the item card says free, and housing limits still refuse", function()
  local world = newWorld()
  Market.setCheat(world, true)
  local info = ItemText.build(world, "woodshed", false)
  T.truthy(info.cheat)
  T.eq(info.cost, 0)
  T.eq(info.reason, nil)
  T.eq(info.lines[#info.lines].label, tun.ui.itemCard.now)
  T.truthy(Market.cannotBuy(world, "hens", false))
end)
