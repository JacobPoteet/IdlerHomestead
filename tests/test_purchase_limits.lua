-- Purchase limits and upgrade chains (GDD D114-D116, issues #252, #253): unique items are bought once, upgrades
-- replace what they supersede, the shack goes up over the camp, and the stand's tiers show on the stand.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Placement = require("src.sim.systems.placement")
local PlaceText = require("src.ui.place_text")
local Stand = require("src.sim.systems.stand")
local Stats = require("src.sim.stats")
local ItemText = require("src.ui.item_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.control = "active"
  return world
end

-- Everything known, plenty of money: only the purchase rules decide.
local function richWorld(seed)
  local world = newWorld(seed)
  for _, item in ipairs(reg:all("catalog")) do
    world.meta.journal = world.meta.journal or { known = {} }
    world.meta.journal.known[item.id] = true
  end
  Ledger.add(world, "money", 5000)
  return world
end

-- Deliver every order due now (jump the clock a day).
local function deliverAll(world)
  world.state.calendar.elapsed = world.state.calendar.elapsed + 2 * world.tuning.time.dayLength
  Market.tick(world)
end

--- A tile where the camp (2x2) fits and a shack (3x2) over it also fits.
local function campSpot(world)
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "camp", i) and Inventory.canPlace(world, "shack", i) then
      return i
    end
  end
end

-- The classification table (D114): the single source the content must match.
local UNIQUE = {
  "roadside_stand", "woodshed", "wood_stove", "electric_heater", "chest_freezer", "smoker", "cheese_press",
  "goat_trailer", "shelter_cat", "camp", "shack", "sturdy_rod", "big_bucket", "stand_sign", "stand_cooler",
  "stand_display",
}
local REPEATABLE = {
  "chicken_coop", "goat_pen", "cistern", "solar_array", "used_panel", "battery_bank", "wind_turbine",
  "micro_hydro", "generator", "lamp", "drip_line", "sprinkler", "auto_harvester", "well", "hand_pump", "dc_pump",
}
local CONSUMABLE = { "radish_seeds", "potato_seeds", "canned_food", "bait", "fuel_can", "chicken_feed", "hay_bales", "hens", "goats" }

T.test("purchase limits: the content matches the classification table", function()
  for _, id in ipairs(UNIQUE) do
    local item = reg:get("catalog", id)
    T.truthy(item.unique == true, id .. " is unique")
  end
  for _, id in ipairs(REPEATABLE) do
    local item = reg:get("catalog", id)
    T.truthy(not item.unique and not item.equipment, id .. " is repeatable")
  end
  for _, id in ipairs(CONSUMABLE) do
    local item = reg:get("catalog", id)
    T.truthy(not item.unique and not item.equipment and item.gives, id .. " is a consumable")
  end
  -- Equipment can only be had once, so it must never be flagged repeatable above.
  for _, item in ipairs(reg:all("catalog")) do
    if item.replaces then
      T.truthy(item.unique, item.id .. " upgrades are unique")
    end
  end
end)

T.test("purchase limits: a unique building is refused while ordered, delivered, or placed", function()
  for _, id in ipairs({ "woodshed", "wood_stove", "smoker", "roadside_stand", "chest_freezer", "cheese_press", "electric_heater" }) do
    local world = richWorld()
    local item = reg:get("catalog", id)
    T.eq(Market.cannotBuy(world, id, false), nil, id .. " buyable at first")
    T.truthy(Market.order(world, id))
    T.eq(Market.cannotBuy(world, id, false), "ordered", id .. " ordered counts")
    local ok, reason = Market.order(world, id)
    T.falsy(ok)
    T.eq(reason, "ordered")
    deliverAll(world)
    T.eq(Inventory.objectCount(world, item.object), 1)
    T.eq(Market.cannotBuy(world, id, false), "owned", id .. " in the inventory counts")
    for i = 1, #world.state.grid.terrain do
      if Inventory.canPlace(world, item.object, i) then
        T.truthy(Inventory.place(world, item.object, i))
        break
      end
    end
    T.eq(Inventory.objectCount(world, item.object), 0, id .. " was placed")
    T.eq(Market.cannotBuy(world, id, false), "owned", id .. " placed counts")
  end
end)

T.test("purchase limits: a destroyed unique building can be bought again", function()
  local world = richWorld()
  Market.order(world, "woodshed")
  deliverAll(world)
  local spot
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "woodshed", i) then
      spot = i
      break
    end
  end
  Inventory.place(world, "woodshed", spot)
  T.eq(Market.cannotBuy(world, "woodshed", false), "owned")
  T.truthy(Placement.destroy(world, spot))
  T.eq(Market.cannotBuy(world, "woodshed", false), nil)
end)

T.test("purchase limits: repeatable items can be ordered again", function()
  for _, id in ipairs({ "chicken_coop", "goat_pen", "cistern", "solar_array", "battery_bank", "lamp", "drip_line", "sprinkler", "auto_harvester", "generator" }) do
    local world = richWorld()
    T.truthy(Market.order(world, id), id)
    T.truthy(Market.order(world, id), id .. " twice")
    deliverAll(world)
    T.truthy(Market.order(world, id), id .. " after delivery")
  end
end)

T.test("upgrade chain: the sturdy rod replaces the basic rod and the two never add up", function()
  local world = richWorld()
  T.truthy(Inventory.hasEquipment(world, "basic_rod"))
  T.eq(Stats.modifier(world, "rod"), 1)
  T.eq(Market.cannotBuy(world, "basic_rod", false), "owned")
  Market.order(world, "sturdy_rod")
  T.eq(Market.cannotBuy(world, "basic_rod", false), "owned", "owned wins over the pending upgrade")
  deliverAll(world)
  T.truthy(Inventory.hasEquipment(world, "sturdy_rod"))
  T.falsy(Inventory.hasEquipment(world, "basic_rod"), "the old tier is dropped")
  T.eq(Stats.modifier(world, "rod"), 1, "one rod, not two")
  T.eq(Market.cannotBuy(world, "basic_rod", false), "replaced")
  T.eq(Market.cannotBuy(world, "sturdy_rod", false), "owned")
end)

T.test("upgrade chain: a starting sturdy rod swallows a basic rod added after it", function()
  local world = newWorld()
  Inventory.addEquipment(world, "sturdy_rod")
  Inventory.addEquipment(world, "basic_rod")
  T.falsy(Inventory.hasEquipment(world, "basic_rod"))
  T.eq(Stats.modifier(world, "rod"), 1)
end)

T.test("upgrade chain: the big bucket is one purchase and says what it replaces", function()
  local world = richWorld()
  Market.order(world, "big_bucket")
  deliverAll(world)
  T.eq(Market.cannotBuy(world, "big_bucket", false), "owned")
  local card = ItemText.build(world, "big_bucket", false)
  T.truthy(card.owned)
  local text = {}
  for _, line in ipairs(card.lines) do
    text[#text + 1] = line.label .. ":" .. line.text
  end
  T.truthy(table.concat(text, "|"):find("Replaces:the plain bucket", 1, true), "card names the plain bucket")
end)

T.test("item card: an owned unique item shows Owned and the upgrade names what it replaces", function()
  local world = richWorld()
  local card = ItemText.build(world, "shack", false)
  local found
  for _, line in ipairs(card.lines) do
    if line.label == "Replaces" then
      found = line.text
    end
  end
  T.eq(found, "the camp")
  T.falsy(card.owned)
  Inventory.addObject(world, "shack")
  card = ItemText.build(world, "shack", false)
  T.truthy(card.owned)
  T.eq(card.reason, "owned")
end)

-- Camp -> shack --------------------------------------------------------------------------------------------

T.test("shack: bought after the camp, it goes over the camp and removes it, no refund", function()
  local world = richWorld()
  local spot = campSpot(world)
  T.truthy(spot, "found room")
  Inventory.addObject(world, "camp")
  T.truthy(Inventory.place(world, "camp", spot))
  Market.order(world, "shack")
  T.eq(Market.cannotBuy(world, "camp", false), "owned", "camp still owned while the shack is on its way")
  deliverAll(world)
  T.eq(Inventory.objectCount(world, "shack"), 1)
  local money = Ledger.get(world, "money")

  local preview = Placement.preview(world, "shack", spot)
  T.truthy(preview.ok, "over the camp is legal")
  T.eq(#preview.replaces, 1)
  T.eq(preview.replaces[1], spot)
  T.truthy(preview.immediate, "no clearing needed")
  T.eq(PlaceText.replaceTag(world, "shack", preview), "replaces camp")
  local card = PlaceText.confirm(world, "shack", preview, { text = {}, dim = {}, warn = {} })
  T.truthy(card.title:find("camp", 1, true) and card.title:find("shack", 1, true), card.title)
  T.truthy(card.lines[1].text:find("removed", 1, true) and card.lines[1].text:find("camp", 1, true))

  local removed = {}
  world.events:on("object.replaced", function(e)
    removed[#removed + 1] = e
  end)
  T.eq(Placement.request(world, "shack", spot), "placed")
  T.eq(#removed, 1)
  T.eq(removed[1].old, "camp")
  T.eq(world.state.grid.objects[spot].id, "shack")
  T.eq(Inventory.objectCount(world, "shack"), 0)
  T.eq(Ledger.get(world, "money"), money, "no refund and no extra charge")
  local camps = 0
  for _, obj in pairs(world.state.grid.objects) do
    if obj.id == "camp" then
      camps = camps + 1
    end
  end
  T.eq(camps, 0)
  T.eq(Market.cannotBuy(world, "camp", false), "replaced", "the camp cannot be bought back")
  T.eq(Market.cannotBuy(world, "shack", false), "owned")
end)

T.test("shack: the camp stays until the shack is placed; cancelling keeps it", function()
  local world = richWorld()
  local spot = campSpot(world)
  Inventory.addObject(world, "camp")
  Inventory.place(world, "camp", spot)
  Inventory.addObject(world, "shack")
  Placement.preview(world, "shack", spot) -- looking does nothing
  T.eq(world.state.grid.objects[spot].id, "camp")
  T.eq(Inventory.objectCount(world, "shack"), 1)
end)

T.test("shack: with a camp standing it must go over the camp, otherwise anywhere legal", function()
  local world = richWorld()
  local spot = campSpot(world)
  Inventory.addObject(world, "shack")
  -- No camp placed: anywhere legal works.
  local free
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "shack", i) then
      free = i
      break
    end
  end
  local preview = Placement.preview(world, "shack", free)
  T.truthy(preview.ok)
  T.eq(#preview.replaces, 0)
  T.eq(PlaceText.replaceTag(world, "shack", preview), nil)
  local far
  for i = 1, #world.state.grid.terrain do
    if Grid.distance(world.state.grid, spot, i) > 4 and Inventory.canPlace(world, "shack", i) then
      far = i
      break
    end
  end
  T.truthy(far, "a far tile")
  Inventory.addObject(world, "camp")
  Inventory.place(world, "camp", spot)
  -- With the camp standing, a far-off tile is refused with the replace rule.
  preview = Placement.preview(world, "shack", far)
  T.falsy(preview.ok)
  T.eq(preview.rule, "replace")
  T.eq(Placement.request(world, "shack", far), nil)
  T.truthy(PlaceText.reason(world, preview.reason, preview.rule):find("replaces", 1, true))
end)

T.test("shack: not while the homesteader sleeps in the camp; the order waits for morning", function()
  local world = richWorld()
  local spot = campSpot(world)
  Inventory.addObject(world, "camp")
  Inventory.place(world, "camp", spot)
  Inventory.addObject(world, "shack")
  Actors.homesteader(world).asleep = true
  local preview = Placement.preview(world, "shack", spot)
  T.falsy(preview.ok)
  T.eq(preview.rule, "replaceAsleep")
  Actors.homesteader(world).asleep = false
  T.truthy(Placement.preview(world, "shack", spot).ok)
end)

T.test("shack: an unplaced camp in the inventory is dropped when the shack goes up", function()
  local world = richWorld()
  Inventory.addObject(world, "camp")
  Inventory.addObject(world, "shack")
  local free
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "shack", i) then
      free = i
      break
    end
  end
  T.truthy(Inventory.place(world, "shack", free))
  T.eq(Inventory.objectCount(world, "camp"), 0)
  T.falsy(Inventory.owns(world, "camp"))
end)

-- Stand tiers ----------------------------------------------------------------------------------------------

T.test("stand tiers: each upgrade is a catalog tier with an overlay sprite and shows in the stand's list", function()
  local world = newWorld()
  local sprites = require("assets.manifest").sprites
  local tiers = Stand.tiers(world)
  T.eq(#tiers, 3)
  for _, tier in ipairs(tiers) do
    T.falsy(tier.owned)
    local item = reg:get("catalog", tier.id)
    T.eq(item.upgrades, "roadside_stand")
    T.truthy(sprites[item.overlay], tier.id .. " has an overlay sprite")
  end
  Inventory.addEquipment(world, "stand_cooler")
  local owned = {}
  for _, tier in ipairs(Stand.tiers(world)) do
    owned[tier.id] = tier.owned
  end
  T.truthy(owned.stand_cooler)
  T.falsy(owned.stand_sign)
end)
