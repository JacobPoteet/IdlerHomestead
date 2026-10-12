-- Optional policy behaviours for the balance harness (issues #80 power, #90 water, #105 stand,
-- #101 weather, #111 finds, #115 cat). `features=` on the command line picks which are on, so a run
-- can be compared with and without them (`features=none` is the harness as it was before these).
--
-- Everything here is *player behaviour* (what to buy, where to put it, which find to take); game
-- numbers still come from tuning and content. Only public sim accessors are used.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")

local Features = {}

--- Feature ids, in the order they are listed in reports.
Features.LIST = { "cat", "stand", "water", "power", "finds", "weather" }

Features.describe = {
  cat = "buy the shelter cat once the Mice note unlocks it (#115)",
  stand = "build the roadside stand, buy its upgrades, report stand vs truck income (#105)",
  water = "buy the water rungs (well, cistern, pump, drip lines), place them by the field (#90)",
  power = "buy and place the power items, keep the truck charged before the bank until winter (#80)",
  finds = "choose finds by need instead of the first option (#111)",
  weather = "active: no hauling water in the rain (#101)",
}

--- Parse a `features=` value: nil/"all" is every feature, "none" is none, else a comma list.
--- Returns a set { [id] = true }.
function Features.parse(spec)
  local set = {}
  if spec == nil or spec == "all" then
    for _, id in ipairs(Features.LIST) do
      set[id] = true
    end
    return set
  end
  if spec == "none" or spec == "" then
    return set
  end
  for id in spec:gmatch("[^,]+") do
    assert(Features.describe[id], "unknown feature '" .. id .. "' (" .. table.concat(Features.LIST, "|") .. "|all|none)")
    set[id] = true
  end
  return set
end

--- The enabled ids of a set as a comma list (for headers).
function Features.label(set)
  local ids = {}
  for _, id in ipairs(Features.LIST) do
    if set[id] then
      ids[#ids + 1] = id
    end
  end
  return #ids == 0 and "none" or table.concat(ids, ",")
end

-- Shopping list ------------------------------------------------------------------------------------

-- How many of a catalog item are held: placed, waiting in the inventory, or still on order.
local function held(world, id)
  local item = world.registry:get("catalog", id)
  if item.equipment then
    return Inventory.hasEquipment(world, id) and 1 or 0
  end
  local n = Inventory.objectCount(world, item.object)
  for _, obj in pairs(world.state.grid.objects) do
    if obj.id == item.object then
      n = n + 1
    end
  end
  for _, order in ipairs(world.state.market.orders) do
    if order.item == id then
      n = n + 1
    end
  end
  return n
end
Features.held = held

local function daysToFreeze(world)
  local time = world.tuning.time
  local now = Calendar.now(world)
  if Weather.isFrozenSeason(world, now.season) then
    return 0
  end
  for n, s in ipairs(time.seasons) do
    if Weather.isFrozenSeason(world, s) then
      return (n - now.seasonIndex) * time.daysPerSeason - now.dayOfSeason + 1
    end
  end
  return math.huge
end

-- Within `seasons` seasons of the freeze (or in it).
local function nearWinter(world, seasons)
  return daysToFreeze(world) <= seasons * world.tuning.time.daysPerSeason
end

--- Strict-priority shopping list: each entry { id, feature, count?, early?, when? }. The policy
--- walks it in order and saves up for the first entry it cannot yet afford rather than skipping it.
local SHOPPING = {
  { id = "shelter_cat", feature = "cat", early = true },
  { id = "roadside_stand", feature = "stand" },
  { id = "well", feature = "water" },
  { id = "cistern", feature = "water" },
  { id = "stand_sign", feature = "stand" },
  { id = "solar_array", feature = "power" },
  { id = "battery_bank", feature = "power" },
  {
    id = "electric_heater",
    feature = "power",
    when = function(world)
      return nearWinter(world, 2)
    end,
  },
  { id = "dc_pump", feature = "water" },
  { id = "drip_line", feature = "water", count = 2 },
  { id = "lamp", feature = "power" },
  {
    id = "wind_turbine",
    feature = "power",
    when = function(world)
      return nearWinter(world, 1)
    end,
  },
  { id = "stand_cooler", feature = "stand" },
  { id = "stand_display", feature = "stand" },
  { id = "hand_pump", feature = "water" },
  { id = "chest_freezer", feature = "power" },
  {
    id = "generator",
    feature = "power",
    when = function(world)
      return held(world, "electric_heater") > 0
    end,
  },
  {
    id = "fuel_can",
    feature = "power",
    when = function(world)
      return held(world, "generator") > 0 and Ledger.get(world, "fuel") < 2 and nearWinter(world, 1)
    end,
  },
  { id = "micro_hydro", feature = "power" },
}

--- The shopping list for a feature set: { early = {...}, rest = {...} } of entries.
function Features.shopping(set)
  local list = { early = {}, rest = {} }
  for _, entry in ipairs(SHOPPING) do
    if set[entry.feature] then
      table.insert(entry.early and list.early or list.rest, entry)
    end
  end
  return list
end

--- Ids to study, in order of preference, for a feature set.
function Features.studyIds(set)
  local ids = {}
  for _, entry in ipairs(SHOPPING) do
    if set[entry.feature] then
      ids[#ids + 1] = entry.id
    end
  end
  return ids
end

--- Order what the list asks for. `reserve` is the money to keep back. Strict: the first wanted entry
--- that cannot be paid for yet stops the walk, so the policy saves up for it.
function Features.buy(world, entries, reserve)
  for _, entry in ipairs(entries) do
    local want = entry.count or 1
    local gated = entry.when and not entry.when(world)
    if not gated and Market.isKnown(world, entry.id) and held(world, entry.id) < want then
      local reason = Market.cannotBuy(world, entry.id, false)
      if reason == nil then
        local cost = Market.itemPrice(world, entry.id) + world.tuning.economy.deliveryFee
        if Ledger.get(world, "money") - cost >= reserve then
          Market.order(world, entry.id)
        else
          return
        end
      elseif reason == "not enough money" then
        return
      end
    end
  end
end

-- Placement ------------------------------------------------------------------------------------------

-- Tiles that are (or will be) field: planned, tilled or planted.
local function fieldTileSet(world)
  local set, list = {}, {}
  local function add(i)
    if not set[i] then
      set[i] = true
      list[#list + 1] = i
    end
  end
  for i in pairs(world.state.fields.plan) do
    add(i)
  end
  for i in pairs(world.state.fields.tilled) do
    add(i)
  end
  for i in pairs(world.state.crops) do
    add(i)
  end
  return set, list
end

local function centroid(world, tiles)
  local grid = world.state.grid
  if #tiles == 0 then
    return Grid.coords(grid, Land.spawn(world))
  end
  local sx, sy = 0, 0
  for _, i in ipairs(tiles) do
    local x, y = Grid.coords(grid, i)
    sx, sy = sx + x, sy + y
  end
  return sx / #tiles, sy / #tiles
end

-- Which objects go by the field instead of by the truck.
local BY_FIELD = { well = true, hand_pump = true, cistern = true, dc_pump = true, drip_line = true }

--- Place one `id` from the inventory where it helps: wells, pumps and cisterns beside the field
--- (a drip line where it waters the most planned tiles), everything else the nearest legal tile to
--- the truck at least `ringFrom` tiles away (a walkway). Returns true when placed.
function Features.place(world, id, ringFrom)
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local fieldSet, fieldList = fieldTileSet(world)
  local cx, cy
  if BY_FIELD[id] then
    cx, cy = centroid(world, fieldList)
  else
    cx, cy = Grid.coords(grid, world.state.land.truck)
  end
  local best, bestScore
  for i = 1, #grid.terrain do
    if Inventory.canPlace(world, id, i) and Grid.terrain(world, i).id ~= "road" then
      local x, y = Grid.coords(grid, i)
      local d = math.max(math.abs(x - cx), math.abs(y - cy))
      if BY_FIELD[id] or d >= ringFrom then
        local score = d
        if def.drip then
          local covered, r = 0, def.drip.radius
          for dy = -r, r do
            for dx = -r, r do
              if Grid.inBounds(grid, x + dx, y + dy) and fieldSet[Grid.index(grid, x + dx, y + dy)] then
                covered = covered + 1
              end
            end
          end
          score = -covered * 100 + d
        end
        if not bestScore or score < bestScore then
          best, bestScore = i, score
        end
      end
    end
  end
  return best ~= nil and Inventory.place(world, id, best)
end

--- Does this object get Features.place instead of the plain ring search around the truck?
function Features.handles(set, id)
  if BY_FIELD[id] then
    return set.water == true
  end
  return (set.stand and id == "roadside_stand") or (set.power and id == "micro_hydro") or false
end

-- Daily switching (power) -------------------------------------------------------------------------------

--- Morning switches: while it is warm the truck is charged before the battery bank; near winter the
--- bank comes first so the heater has stored sun for the dark hours.
function Features.daily(world, set)
  if not set.power then
    return
  end
  local order = Power.order(world)
  local bank, truck
  for i, id in ipairs(order) do
    if id == "bank" then
      bank = i
    elseif id == "truck" then
      truck = i
    end
  end
  if not (bank and truck) then
    return
  end
  local bankFirst = nearWinter(world, 1)
  if bankFirst and bank > truck then
    Power.moveTier(world, "bank", -1)
  elseif not bankFirst and bank < truck then
    Power.moveTier(world, "bank", 1)
  end
end

--- Should today's truck trip wait so the truck battery can fill once? True after the first trip
--- until the "Full battery" note is written, the battery is full, or `untilDay` has passed.
function Features.holdTrip(world, untilDay)
  if Calendar.now(world).day > untilDay or not Journal.hasNote(world, "first_trip") or Journal.hasNote(world, "full_battery") then
    return false
  end
  local truck = Land.truck(world)
  return Power.charge(world, truck) < Power.capacity(world, truck) * world.tuning.power.fullFraction
end

-- Finds ------------------------------------------------------------------------------------------------

-- How much a player wants each find right now (higher is better); unknown finds score 1, and ties
-- keep the offer's order.
local FIND_SCORE = {
  stray_cat = function(world)
    return Inventory.hasEquipment(world, "shelter_cat") and 0 or 6
  end,
  split_stack = function(world, h)
    return h.warmthDeficit(world, false) > 0 and nearWinter(world, 1) and 6 or 1
  end,
  heirloom_seeds = function(world)
    local season = Calendar.now(world).season
    return (season == "spring" or season == "summer") and Ledger.get(world, "seed_potato") < 6 and 5 or 1
  end,
  rusty_axe = function(world)
    return Inventory.hasEquipment(world, "axe") and 0 or 5
  end,
  used_panel = function(world)
    return held(world, "used_panel") > 0 and 0.5 or 4
  end,
  dusty_cans = function(world)
    return Needs.foodDays(world) < 5 and 4 or 1.5
  end,
  loose_cash = function(world)
    return Ledger.get(world, "money") < 50 and 3.5 or 2
  end,
  jump_pack = function(world)
    return Market.canTrip(world) and 1 or 4
  end,
  junk_with_goods = function()
    return 2
  end,
  bait_tin = function(world)
    return Ledger.get(world, "bait") < 2 and 2 or 0.5
  end,
}

--- Pick the find a player in need would take from a pending offer; `h.warmthDeficit` is the
--- policy's fuel check. Returns a find id.
function Features.chooseFind(world, offer, h)
  local best, bestScore
  for _, id in ipairs(offer.choices) do
    local fn = FIND_SCORE[id]
    local score = fn and fn(world, h) or 1
    if not bestScore or score > bestScore then
      best, bestScore = id, score
    end
  end
  return best
end

-- Metrics ----------------------------------------------------------------------------------------------

--- Water facts for the report: waterings by hand / drip, units pumped / rained, cistern owned.
function Features.waterStats(world)
  local s = Water.stats(world)
  return { hand = s.hand, drip = s.drip, pumped = s.pumped, rained = s.rained, cistern = Water.hasCistern(world) and 1 or 0 }
end

return Features
