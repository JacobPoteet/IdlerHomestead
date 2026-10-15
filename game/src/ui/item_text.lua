-- Text for the store's item card (#266, D107). Pure: it reads a catalog definition, the market and the
-- ledger and returns lines; the words live in tuning.ui.itemCard and what an item does is the content's own
-- `desc` (or its one-line `line`), so no scene hard-codes item text.

local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Sandbox = require("src.sim.systems.sandbox")

local ItemText = {}

local function sortedKeys(t)
  local ids = {}
  for k in pairs(t) do
    ids[#ids + 1] = k
  end
  table.sort(ids)
  return ids
end

-- "5 radish seed, 2 canned food" from a gives table, in a stable order.
local function givesText(world, gives)
  local parts = {}
  for _, res in ipairs(sortedKeys(gives)) do
    parts[#parts + 1] = string.format("%d %s", gives[res], world.registry:get("resources", res).name:lower())
  end
  return table.concat(parts, ", ")
end

--- The card for catalog item `id`. pickup = bought in town (no delivery fee).
--- Returns { title, price, desc, lines = { { label, text, tone } }, reason, cost } where tone is "text", "dim" or "warn",
--- reason is Market.cannotBuy's answer (nil when it can be bought) and cost is what the button charges.
function ItemText.build(world, id, pickup)
  local t = world.tuning.ui.itemCard
  local item = world.registry:get("catalog", id)
  local price = Market.itemPrice(world, id)
  local fee = pickup and 0 or world.tuning.economy.deliveryFee
  local reason = Market.cannotBuy(world, id, pickup)
  local lines = {}
  local function add(label, text, tone)
    lines[#lines + 1] = { label = label, text = text, tone = tone or "text" }
  end

  local priceText
  local cheat = Market.cheatOn(world)
  if cheat then
    fee, priceText = 0, Sandbox.on(world) and world.tuning.ui.sandbox.priceFree or t.priceCheat
  elseif pickup then
    priceText = string.format(t.priceTown, price)
  else
    priceText = string.format(t.priceDelivery, price, fee)
  end
  if not cheat and world.state.market.specials[id] then
    priceText = priceText .. " " .. t.sale
  end

  -- What you get.
  if item.object then
    add(t.gets, string.format(t.object, world.registry:get("objects", item.object).name:lower()))
  end
  if item.gives then
    add(t.gets, givesText(world, item.gives))
  end
  if item.equipment then
    add(t.gets, t.equipment)
  end

  -- What it needs.
  local needs = {}
  if item.requires then
    local have = Inventory.hasEquipment(world, item.requires)
    needs[#needs + 1] =
      { text = string.format(t.needsItem, world.registry:get("catalog", item.requires).name:lower()), met = have }
  end
  for res in pairs(item.gives or {}) do
    local def = world.registry:get("resources", res)
    if def.category == "animal" then
      needs[#needs + 1] =
        { text = string.format(t.needsHome, def.housing or "home"), met = Ledger.capacity(world, res) > 0 }
    end
  end
  if item.pickupOnly then
    needs[#needs + 1] = { text = t.needsTown, met = pickup == true }
  end
  for _, need in ipairs(needs) do
    add(t.needs, need.text, need.met and "text" or "warn")
  end
  if #needs == 0 then
    add(t.needs, t.needsNothing, "dim")
  end

  -- What it replaces (an upgrade names the item it supersedes) and its cap.
  if item.replaces then
    add(t.replaces, string.format(t.replacesItem, world.registry:get("catalog", item.replaces).name:lower()))
  elseif item.replacesLabel then
    add(t.replaces, string.format(t.replacesItem, item.replacesLabel))
  end
  local owned = reason == "owned" or reason == "replaced"
  if item.equipment or item.unique then
    add(t.limit, t.limitOne, owned and "warn" or "text")
  end
  for _, res in ipairs(sortedKeys(item.gives or {})) do
    local cap = Ledger.capacity(world, res)
    if cap < math.huge and cap > 0 then -- no store yet (no pen or coop): the Needs line already says so
      add(
        t.limit,
        string.format(t.limitStore, world.registry:get("resources", res).name:lower(), cap, Ledger.get(world, res))
      )
    end
  end

  if reason and reason ~= "unknown" then
    add(t.now, rawget(t.reasons, reason) or reason, "warn")
  elseif cheat then
    add(t.now, Sandbox.on(world) and world.tuning.ui.sandbox.nowFree or t.nowCheat, "dim")
  end
  return {
    title = item.name,
    price = priceText,
    desc = item.desc or item.line,
    lines = lines,
    reason = reason,
    owned = owned,
    cost = cheat and 0 or price + fee,
    cheat = cheat,
  }
end

return ItemText
