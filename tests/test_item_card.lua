-- The store's item card text (#266, D107): every catalog item gets a description from content and its facts
-- (cost, needs, replaces, cap) from the sim; no scene hard-codes item text.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local ItemText = require("src.ui.item_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(5))
end

local function find(info, label)
  for _, line in ipairs(info.lines) do
    if line.label == label then
      return line
    end
  end
end

T.test("item card: every catalog item has a description, a price line and a buy cost", function()
  local world = newWorld()
  for _, item in ipairs(reg:all("catalog")) do
    for _, pickup in ipairs({ false, true }) do
      local info = ItemText.build(world, item.id, pickup)
      T.truthy(info.desc and info.desc ~= "", item.id .. " has no description")
      T.truthy(info.price:find("%$"), item.id .. " price line")
      T.eq(
        info.cost,
        require("src.sim.systems.market").itemPrice(world, item.id) + (pickup and 0 or tun.economy.deliveryFee)
      )
      T.truthy(find(info, "Needs"), item.id .. " has no needs line")
    end
  end
end)

T.test("item card: needs, cap and refusal reasons", function()
  local world = newWorld()
  -- Goats need the trailer and a pen; they are sold in town only.
  local goats = ItemText.build(world, "goats", false)
  T.truthy(goats.reason ~= nil)
  local needs = {}
  for _, line in ipairs(goats.lines) do
    if line.label == "Needs" then
      needs[#needs + 1] = line
    end
  end
  T.truthy(#needs >= 2, "goats list their needs")
  for _, line in ipairs(needs) do
    T.eq(line.tone, "warn", "unmet need " .. line.text)
  end
  -- Gear is one per run and says so once owned.
  local rod = ItemText.build(world, "basic_rod", false)
  T.eq(find(rod, "Limit").text, tun.ui.itemCard.limitOne)
  world.state.inventory.equipment.basic_rod = nil
  T.eq(ItemText.build(world, "basic_rod", false).reason, "not enough money")
  world.state.inventory.equipment.basic_rod = true
  T.eq(ItemText.build(world, "basic_rod", false).reason, "owned")
  -- Stocks say how much the store holds.
  local seeds = ItemText.build(world, "canned_food", false)
  T.truthy(find(seeds, "Gets"))
end)
