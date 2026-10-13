-- Play policies for the balance harness (issue #31, GDD §12.5).
--
-- A policy drives the real World the way a player would, using only public sim calls (player
-- orders via Actors.order, catalog orders via Market, study via Journal, ...). Nothing is mocked.
--
--   idle      The player never acts. The idle routine runs from the first second: it clears the
--             easy clutter, fishes, splits wood, and harvests/waters/plants only what was planned
--             (nothing, since the player plans nothing). The "install it and walk away" floor.
--   scripted  A fixed opening and then the routine, no direct orders. On day 1 it plans one field
--             tile per starting seed near the creek. Keep targets stay automatic. Every morning
--             it: auto-loads the truck and sells the load when the truck can make the trip, orders the next catalog item from a fixed buy list, places
--             delivered objects near the truck, and fills the study queue from a fixed study list.
--   active    A reasonable engaged player on top of everything `scripted` does. It keeps the wood
--             its winter plan needs (a keep target, D75) and issues orders
--             itself (harvest, water, plant, till, load the smoker/woodshed, split wood, fell
--             trees for the winter, clear junk for cash, fish by hand with the rod), grows the field
--             as seeds come in, buys seeds, and hands control to the routine after the takeover
--             delay when it has nothing to order. It sleeps at night (no orders at bedtime), so
--             study progresses. Fishing is abstracted: the mini-game outcome is a dice roll
--             (POLICY.fishSkill) and takes a plausible length of game time.
--
-- Everything in POLICY is *player behaviour*, not game balance; game numbers are always read from
-- tuning and content.

local Actors = require("src.sim.systems.actors")
local Animals = require("src.sim.systems.animals")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Features = require("features")
local Fishing = require("src.sim.systems.fishing")
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Rng = require("src.core.rng")
local Sleep = require("src.sim.systems.sleep")
local Stats = require("src.sim.stats")
local Weather = require("src.sim.systems.weather")

local Policies = {}

-- Player behaviour knobs (not game balance).
local POLICY = {
  -- Catalog items to buy, in order of preference.
  buyList = { "woodshed", "wood_stove", "axe", "smoker", "big_bucket", "sturdy_rod", "used_panel" },
  -- Ideas to study first, in order; anything else available follows.
  studyList = { "woodshed", "wood_stove", "axe", "smoker", "big_bucket", "sturdy_rod", "used_panel" },
  minTripValue = 5, -- $ the auto-loaded truck must be worth before a trip is worth the charge
  placeFromRing = 2, -- tiles from the truck at which delivered objects are placed (leaves a walkway)
  placeToRing = 10, -- farthest ring tried when placing
  maxFieldTiles = 48, -- active: most tiles the player will keep in fields
  blacklistSeconds = 60, -- seconds an unreachable target is skipped
  fishSkill = 0.75, -- active: chance the tension mini-game ends in a landed fish
  fightPadding = 3, -- active: seconds of reeling on top of the fish's stamina
  seedMoneyReserve = 6, -- active: $ kept back when buying seeds
  junkMoneyGoal = 60, -- active: stop clearing junk for cash once money passes this
  urgentFuelNights = 3, -- active: nights of the coming season's warmth in stock below which firewood jumps the queue
  frostMargin = 1, -- active: days of slack when judging whether a crop can mature before the freeze
  holdTripsUntilDay = 14, -- power feature: last day of the run on which trips wait for the truck battery to fill once (the "Full battery" note unlocks the power items)
  featureReserve = 8, -- $ kept back when buying feature items (power, water, stand, cat) so seeds and bait stay affordable
}
Policies.POLICY = POLICY

-- Helpers ------------------------------------------------------------------------------------

local function homesteader(world)
  return Actors.homesteader(world)
end

local function dist2(actor, grid, i)
  local x, y = Grid.coords(grid, i)
  local dx, dy = x - actor.x, y - actor.y
  return dx * dx + dy * dy
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- Tiles of the (static) creek, nearest the spawn first.
local function waterTiles(world, wantWaterOnly)
  local grid, list = world.state.grid, {}
  for i = 1, #grid.terrain do
    local t = world.registry:get("terrain", grid.terrain[i])
    if t.water and (not wantWaterOnly or not t.walkable) then
      list[#list + 1] = i
    end
  end
  return list
end

local function chebyshev(grid, a, b)
  return Grid.distance(grid, a, b)
end

local function ownsOrPending(world, id)
  if Inventory.owns(world, id) then
    return true
  end
  for _, order in ipairs(world.state.market.orders) do
    if order.item == id then
      return true
    end
  end
  return false
end

--- Place `id` from the inventory on the nearest free tile in the rings around the truck.
local function placeNearTruck(world, id)
  local grid = world.state.grid
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for r = POLICY.placeFromRing, POLICY.placeToRing do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r and Grid.inBounds(grid, tx + dx, ty + dy) then
          local i = Grid.index(grid, tx + dx, ty + dy)
          if Inventory.canPlace(world, id, i) and world.registry:get("terrain", grid.terrain[i]).id ~= "road" then
            if Inventory.place(world, id, i) then
              return true
            end
          end
        end
      end
    end
  end
  return false
end

-- Seconds of game time -> ticks.
local function ticks(world, seconds)
  return math.floor(seconds * world.tuning.time.tickRate + 0.5)
end

-- Days until the freeze starts (0 when frozen already); counts today.
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

--- Warmth the player should have in hand from tonight until the end of this year's winter:
--- worst-case severity and the longest cold snap, since the forecast is not trusted.
local function warmthPlan(world)
  local t = world.tuning
  local now = Calendar.now(world)
  local cfg = t.weather
  local severity = cfg.severityMax + cfg.severityPerYear * (now.year - 1)
  local total = 0
  for s = now.seasonIndex, #t.time.seasons do
    local season = t.time.seasons[s]
    local left = s == now.seasonIndex and (t.time.daysPerSeason - now.dayOfSeason + 1) or t.time.daysPerSeason
    local base = t.needs.dailyWarmth[season]
    if Weather.isFrozenSeason(world, season) then
      total = total + base * severity * (left + cfg.snapDaysMax * (cfg.snapMultiplier - 1))
    else
      total = total + base * left
    end
  end
  return total
end

--- Warmth still missing for the plan, counting unsplit wood as green firewood.
local function warmthDeficit(world, includeWood)
  local cfg = world.tuning.firewood
  local eff = math.max(Needs.heatEfficiency(world), 1)
  local stock = Needs.warmthInStock(world)
  if includeWood then
    stock = stock + Ledger.get(world, cfg.splitFrom) * world.registry:get("resources", cfg.splitInto).heat * eff
  end
  return warmthPlan(world) - stock
end

-- Base policy: the daily "manager" chores shared by scripted and active ----------------------------

local Base = {}
Base.__index = Base

local function newBase(world, seed, extra, features)
  features = features or {}
  local self = setmetatable({
    rng = Rng.new(Rng.deriveSeed(seed, "policy")),
    bad = {}, -- tile -> tick until which it is skipped
    control = "idle",
    features = features, -- set of optional behaviours (see features.lua)
    shopping = Features.shopping(features),
  }, Base)
  for k, v in pairs(extra or {}) do
    self[k] = v
  end
  return self
end

--- Pick `n` field tiles: tillable, free, close to the creek and the truck, good soil.
function Base:fieldTiles(world, n)
  local grid = world.state.grid
  self.water = self.water or waterTiles(world, false)
  local spawn = world.state.land.spawn
  local fields = world.state.fields
  local scored = {}
  for i = 1, #grid.terrain do
    if
      Grid.terrain(world, i).tillable
      and not world.occupancy[i]
      and not fields.tilled[i]
      and not fields.plan[i]
      and not world.state.crops[i]
    then
      local nearest = math.huge
      for _, w in ipairs(self.water) do
        nearest = math.min(nearest, chebyshev(grid, i, w))
      end
      local score = nearest + 0.5 * chebyshev(grid, i, spawn) - 4 * grid.soil[i]
      scored[#scored + 1] = { i = i, score = score }
    end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then
      return a.score < b.score
    end
    return a.i < b.i
  end)
  local tiles = {}
  for k = 1, math.min(n, #scored) do
    tiles[k] = scored[k].i
  end
  return tiles
end

--- Plan one tile per crop seed in hand that isn't already claimed by a planned, unplanted tile.
function Base:planField(world, cap)
  local fields = world.state.fields
  local planned = 0
  for _ in pairs(fields.plan) do
    planned = planned + 1
  end
  local room = (cap or math.huge) - planned
  if room <= 0 then
    return
  end
  for _, crop in ipairs(world.registry:all("crops")) do
    local seeds = Ledger.get(world, crop.seed)
    local claimed = 0
    for i, c in pairs(fields.plan) do
      if c == crop.id and not world.state.crops[i] then
        claimed = claimed + 1
      end
    end
    local want = math.min(seeds - claimed, room)
    if want > 0 and self:canMature(world, crop) then
      for _, i in ipairs(self:fieldTiles(world, want)) do
        Crops.setPlan(world, i, crop.id)
        room = room - 1
      end
    end
  end
end

--- Would a crop planted today ripen before the freeze, with a day of slack for watering lag?
function Base:canMature(world, crop)
  return daysToFreeze(world) >= crop.growDays + POLICY.frostMargin
end

function Base:start(world)
  -- Scripted opening: one tile per starting seed.
  self:planField(world, nil)
end

function Base:trip(world)
  if not Market.canTrip(world) then
    return
  end
  -- The power items unlock on the "Full battery" note, which a truck that keeps driving never fills.
  if self.features.power and Features.holdTrip(world, POLICY.holdTripsUntilDay) then
    return
  end
  -- D75: load the truck with Auto-load (spare goods only, never below a keep target) and judge the
  -- trip by what is loaded. A trip not worth taking empties the truck again, so the stand can sell.
  Market.autoLoad(world)
  local _, total = Market.loadQuote(world)
  local wantsPickup = false
  for _, id in ipairs(POLICY.buyList) do
    local item = world.registry:get("catalog", id)
    if item.pickupOnly and Market.isKnown(world, id) and not ownsOrPending(world, id) then
      wantsPickup = true
    end
  end
  local extra = Features.tripItems(world, self.features)
  if total < POLICY.minTripValue and not wantsPickup and #extra == 0 then
    Market.clearLoad(world)
    return
  end
  if Market.startTrip(world) then
    Market.sellLoad(world)
    for _, id in ipairs(POLICY.buyList) do
      if not ownsOrPending(world, id) then
        Market.buyInTown(world, id)
      end
    end
    for _, id in ipairs(extra) do
      Market.buyInTown(world, id)
    end
    Market.endTrip(world)
  end
end

function Base:buy(world)
  Features.buy(world, self.shopping.early, POLICY.featureReserve)
  for _, id in ipairs(POLICY.buyList) do
    if not ownsOrPending(world, id) and Market.cannotBuy(world, id, false) == nil then
      Market.order(world, id)
    end
  end
  Features.buy(world, self.shopping.rest, POLICY.featureReserve)
end

function Base:place(world)
  for _, id in ipairs(sortedKeys(world.state.inventory.objects)) do
    for _ = 1, Inventory.objectCount(world, id) do
      local placed
      if Features.handles(self.features, id) then
        placed = Features.place(world, id, POLICY.placeFromRing)
      else
        placed = placeNearTruck(world, id)
      end
      if not placed then
        break
      end
    end
  end
end

--- Which find to take from a pending offer: by need with the `finds` feature, else the first.
function Base:chooseFind(world, offer)
  if self.features.finds then
    return Features.chooseFind(world, offer, { warmthDeficit = warmthDeficit })
  end
  return offer.choices[1]
end

function Base:study(world)
  local queue = Journal.queue(world)
  local size = world.tuning.study.queueSize
  local ideas = Journal.ideas(world)
  local byId = {}
  for _, def in ipairs(ideas) do
    byId[def.id] = def
  end
  local order = {}
  local wanted = { unpack(POLICY.studyList) }
  for _, id in ipairs(Features.studyIds(self.features)) do
    wanted[#wanted + 1] = id
  end
  for _, id in ipairs(wanted) do
    if byId[id] then
      order[#order + 1] = id
      byId[id] = nil
    end
  end
  for _, def in ipairs(ideas) do
    if byId[def.id] then
      order[#order + 1] = def.id
    end
  end
  for _, id in ipairs(order) do
    if #queue >= size then
      break
    end
    Journal.study(world, id)
  end
end

--- The morning routine, run on every new day.
function Base:daily(world)
  self:trip(world)
  self:buy(world)
  self:place(world)
  Features.daily(world, self.features)
  self:study(world)
end

function Base:step() end
function Base:attach() end

-- idle ---------------------------------------------------------------------------------------

local Idle = {}
Idle.__index = Idle

function Idle.new()
  return setmetatable({ control = "idle" }, Idle)
end
function Idle:attach() end
function Idle:start() end
function Idle:daily() end
function Idle:chooseFind(_, offer)
  return offer.choices[1]
end
function Idle:step(world)
  world.control = "idle"
end

-- scripted -----------------------------------------------------------------------------------

local Scripted = setmetatable({}, { __index = Base })
Scripted.__index = Scripted

local function scriptedNew(world, seed, features)
  local self = newBase(world, seed, {}, features)
  return setmetatable(self, Scripted)
end

function Scripted:step(world)
  world.control = "idle"
end

-- active -------------------------------------------------------------------------------------

local Active = setmetatable({}, { __index = Base })
Active.__index = Active

local function activeNew(world, seed, features)
  local self = newBase(world, seed, { lastInput = -math.huge, fishUntil = nil, fishTile = nil }, features)
  return setmetatable(self, Active)
end

function Active:attach(world)
  world.events:on("fishing.ready", function(e)
    -- The tension mini-game: bite wait plus the fight, decided by a die roll.
    local cfg = world.tuning.fishing
    local baited = Ledger.remove(world, "bait", 1, "fishing")
    local bite = (cfg.biteDelayMin + cfg.biteDelayMax) / 2 * (baited and cfg.baitBiteSpeed or 1)
    local fish = Fishing.rollFish(world, "active")
    self.pendingFish = fish
    local fight = (fish and fish.stamina or 0) + POLICY.fightPadding
    self.fishUntil = world.state.tick + ticks(world, bite + fight)
    self.fishTile = e.tile
  end)
end

--- Keep targets an engaged player sets (D75), before the morning trip: the wood its own worst-case
--- winter plan still needs as firewood, so Auto-load and the stand never sell it.
function Active:keeps(world)
  local fw = world.tuning.firewood
  local heat = world.registry:get("resources", fw.splitInto).heat * math.max(Needs.heatEfficiency(world), 1)
  Food.setKeep(world, fw.splitFrom, fw.keepWood + math.max(0, math.ceil(warmthDeficit(world, false) / heat)))
end

function Active:daily(world)
  self:keeps(world)
  Base.daily(self, world)
  -- Buy seeds for open field room while there is still time to grow them.
  local fields = world.state.fields
  local planned = 0
  for _ in pairs(fields.plan) do
    planned = planned + 1
  end
  if planned < POLICY.maxFieldTiles then
    for _, crop in ipairs(world.registry:all("crops")) do
      local id = crop.seed:gsub("^seed_", "") .. "_seeds"
      if world.registry:has("catalog", id) and self:canMature(world, crop) and Ledger.get(world, crop.seed) <= 0 then
        if Ledger.get(world, "money") >= Market.itemPrice(world, id) + world.tuning.economy.deliveryFee + POLICY.seedMoneyReserve then
          if Market.cannotBuy(world, id, false) == nil then
            Market.order(world, id)
          end
        end
      end
    end
  end
  self:planField(world, POLICY.maxFieldTiles)
  -- Keep a stock of bait for the rod.
  if Fishing.hasRod(world) and Ledger.get(world, "bait") < 2 and Market.cannotBuy(world, "bait", false) == nil then
    if Ledger.get(world, "money") >= Market.itemPrice(world, "bait") + world.tuning.economy.deliveryFee + POLICY.seedMoneyReserve then
      Market.order(world, "bait")
    end
  end
end

local function skip(self, world, i)
  self.bad[i] = world.state.tick + ticks(world, POLICY.blacklistSeconds)
end

local function isSkipped(self, world, i)
  local until_ = self.bad[i]
  if until_ and until_ > world.state.tick then
    return true
  end
  self.bad[i] = nil
  return false
end

--- Try targets nearest-first; returns true once an order sticks.
local function tryOrder(self, world, actor, tiles, opts)
  local grid = world.state.grid
  local list = {}
  for _, i in ipairs(tiles) do
    if not isSkipped(self, world, i) then
      list[#list + 1] = { i = i, d = dist2(actor, grid, i) }
    end
  end
  table.sort(list, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    return a.i < b.i
  end)
  for n = 1, math.min(#list, 4) do
    local i = list[n].i
    if Actors.order(world, actor, i, opts and opts(i) or {}) then
      return true
    end
    skip(self, world, i)
  end
  return false
end

function Active:takeoverTicks(world)
  local idle = world.tuning.idle
  local delay = math.max(idle.minTakeoverDelay, idle.takeoverDelay - Stats.modifier(world, "idleTakeover"))
  return ticks(world, delay)
end

local function cropTiles(world, filter)
  local list = {}
  for i, crop in pairs(world.state.crops) do
    if filter(crop) then
      list[#list + 1] = i
    end
  end
  return list
end

local function plannedTiles(world, filter)
  local list = {}
  for i, cropId in pairs(world.state.fields.plan) do
    if filter(i, cropId) then
      list[#list + 1] = i
    end
  end
  return list
end

-- Stations (smoker, woodshed) and splitters placed on the land.
local function objectAnchors(world, filter)
  local list = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if filter(world.registry:get("objects", obj.id)) then
      list[#list + 1] = anchor
    end
  end
  return list
end

--- Clutter worth clearing: wood-bearing trees and logs when the winter needs fuel, junk for cash.
local function clearTargets(world, wantWood, wantJunk)
  local grid = world.state.grid
  local list = {}
  for anchor, obj in pairs(grid.objects) do
    local def = world.registry:get("objects", obj.id)
    if def.clearable ~= false and def.clearTime then
      local isWood = (def.chop or (def.yields and def.yields.wood ~= nil)) and def.id ~= "brush"
      local isJunk = def.yields and def.yields.money ~= nil
      if (wantWood and isWood) or (wantJunk and isJunk and Ledger.get(world, "money") < POLICY.junkMoneyGoal) then
        list[#list + 1] = anchor
      end
    end
  end
  return list
end

--- Split chopped wood, then fell more. Returns true once an order sticks.
function Active:fuel(world, actor)
  local fuelCfg = world.tuning.firewood
  if warmthDeficit(world, false) > 0 and Ledger.get(world, fuelCfg.splitFrom) > 0 then
    local blocks = objectAnchors(world, function(def)
      return def.splitter == true
    end)
    if #blocks > 0 and tryOrder(self, world, actor, blocks) then
      return true
    end
  end
  if warmthDeficit(world, true) > 0 then
    local trees = clearTargets(world, true, false)
    if #trees > 0 and tryOrder(self, world, actor, trees) then
      return true
    end
  end
  return false
end

--- Is the fuel pile about to run out? (Less than a few nights of the coming season's need.)
local function fuelUrgent(world)
  local t = world.tuning
  local now = Calendar.now(world)
  local upcoming = t.time.seasons[now.seasonIndex % #t.time.seasons + 1]
  local night = math.max(t.needs.dailyWarmth[now.season], t.needs.dailyWarmth[upcoming])
  if Weather.isFrozenSeason(world, upcoming) or Weather.isFrozenSeason(world, now.season) then
    night = night * (t.weather.severityMax + t.weather.severityPerYear * (now.year - 1))
  end
  return warmthDeficit(world, false) > 0 and Needs.warmthInStock(world) < night * POLICY.urgentFuelNights
end

function Active:choose(world, actor)
  local fields = world.state.fields
  -- Harvest what is ripe.
  local ripe = cropTiles(world, Crops.isMature)
  if #ripe > 0 and tryOrder(self, world, actor, ripe) then
    return true
  end
  if fuelUrgent(world) and self:fuel(world, actor) then
    return true
  end
  -- Water: fill the bucket when empty, else water the nearest dry crop.
  local dry = cropTiles(world, Crops.needsWater)
  -- With the weather feature the player lets the rain do the watering.
  local rainDay = self.features.weather and Weather.isRaining(world)
  if #dry > 0 and not rainDay then
    if actor.bucket > 0 then
      if tryOrder(self, world, actor, dry) then
        return true
      end
    else
      self.water = self.water or waterTiles(world, false)
      local candidates = {}
      for _, i in ipairs(self.water) do
        if Weather.waterTarget(world, i) then
          candidates[#candidates + 1] = i
        end
      end
      -- Wells, pumps and cisterns are closer places to fill the bucket (nearest first).
      for _, anchor in ipairs(objectAnchors(world, function(def)
        return def.waterSource ~= nil
      end)) do
        candidates[#candidates + 1] = anchor
      end
      if tryOrder(self, world, actor, candidates) then
        return true
      end
    end
  end
  -- Tend the hens: eggs, feed and water (the routine does this itself, but an active player is quicker).
  if self.features.chickens and Animals.needsTending(world) then
    local coops = objectAnchors(world, function(def)
      return def.coop ~= nil
    end)
    if #coops > 0 and tryOrder(self, world, actor, coops) then
      return true
    end
  end
  -- Tend the goats: milk (it spoils fast), hay and water.
  if self.features.goats and Animals.needsTendingPen(world) then
    local pens = objectAnchors(world, function(def)
      return def.pen ~= nil
    end)
    if #pens > 0 and tryOrder(self, world, actor, pens) then
      return true
    end
  end
  -- Heading into the cold, firewood comes before new planting.
  if daysToFreeze(world) <= world.tuning.time.daysPerSeason and self:fuel(world, actor) then
    return true
  end
  -- Plant and till the planned field.
  if not Weather.isFrozen(world) then
    local plant = plannedTiles(world, function(i, cropId)
      return fields.tilled[i] and not world.state.crops[i] and Ledger.get(world, world.registry:get("crops", cropId).seed) > 0
    end)
    if #plant > 0 and tryOrder(self, world, actor, plant, function(i)
      return { crop = fields.plan[i] }
    end) then
      return true
    end
    local till = plannedTiles(world, function(i)
      return not fields.tilled[i] and not world.occupancy[i]
    end)
    if #till > 0 and tryOrder(self, world, actor, till, function(i)
      return { crop = fields.plan[i] }
    end) then
      return true
    end
  end
  -- Load the smoker / woodshed.
  local stations = objectAnchors(world, function(def)
    return def.station ~= nil
  end)
  if #stations > 0 and tryOrder(self, world, actor, stations) then
    return true
  end
  if self:fuel(world, actor) then
    return true
  end
  -- Clear junk for cash.
  local junk = clearTargets(world, false, true)
  if #junk > 0 and tryOrder(self, world, actor, junk) then
    return true
  end
  -- Fish by hand.
  if Fishing.hasRod(world) then
    self.water = self.water or waterTiles(world, false)
    local candidates = {}
    for _, i in ipairs(self.water) do
      if Grid.terrain(world, i).id == "water" and Weather.waterTarget(world, i) then
        candidates[#candidates + 1] = i
      end
    end
    if tryOrder(self, world, actor, candidates, function()
      return { tool = "rod" }
    end) then
      return true
    end
  end
  return false
end

function Active:step(world)
  local now = world.state.tick
  local actor = homesteader(world)
  -- At the mini-game: the player is fully engaged until it ends.
  if self.fishUntil then
    self.lastInput = now
    if now >= self.fishUntil then
      self.fishUntil = nil
      local fish = self.pendingFish
      self.pendingFish = nil
      if fish then
        if self.rng:chance(POLICY.fishSkill) then
          Fishing.land(world, fish.id, Fishing.rollSize(world, fish), "active")
        else
          Fishing.lose(world, fish.id, "slipped")
        end
      end
    end
  elseif not Sleep.isBedtime(world) and not actor.order and not (actor.job and actor.job.ordered) then
    if self:choose(world, actor) then
      self.lastInput = now
    end
  end
  local engaged = now - self.lastInput < self:takeoverTicks(world)
  world.control = engaged and "active" or "idle"
end

-- Registry ---------------------------------------------------------------------------------------

Policies.list = { "idle", "scripted", "active" }

Policies.describe = {
  idle = "player never acts; the idle routine runs from the first second",
  scripted = "plans a field on day 1, then routine; morning chores: trip, buy list, place, study",
  active = "scripted chores plus direct orders (farm, fuel, clear junk, hand-fish); routine after takeover delay",
}

--- Build a policy instance. It is `attach`ed to the world's events, then `start`ed once.
function Policies.new(name, world, seed, features)
  local inst
  if name == "idle" then
    inst = Idle.new()
  elseif name == "scripted" then
    inst = scriptedNew(world, seed, features)
  elseif name == "active" then
    inst = activeNew(world, seed, features)
  else
    error("unknown policy '" .. tostring(name) .. "' (idle|scripted|active)")
  end
  inst:attach(world)
  inst:start(world)
  return inst
end

--- During recovery the one free study: the first idea on the study list, else any idea.
function Policies.freeStudy(metaWorld)
  local ideas = Journal.ideas(metaWorld)
  local byId = {}
  for _, def in ipairs(ideas) do
    byId[def.id] = true
  end
  for _, id in ipairs(POLICY.studyList) do
    if byId[id] then
      return id
    end
  end
  return ideas[1] and ideas[1].id or nil
end

return Policies
