-- What is limiting the homestead (D202, #377, docs/PLAN_DEPTH.md §2 goal 3, §10.2 "Simplified (D184)"): the one line the
-- Progress panel shows under the pressing goal. Accessors only (no state, no events): every figure is read through the
-- system that owns it, so the line cannot disagree with the field, the stores, the power panel or the truck screen.
--
-- The plan's ladder is water, then labour, then storage, then power, then market, then land; Bottleneck.current asks in
-- that order and names the first that holds now, so an early homestead hears about water and a grown one about the market.
-- The tests are first guesses (tuning.progress.bottleneck, M9 tunes them):
--   water    at least `waterShare` of the growing crops (and at least `minCrops` of them) are dry, and it is not raining.
--   labour   ripe crops whose store has room and weedy tiles past the routine's pull level are waiting on at least
--            `labourShare` of the field's tiles (and at least `minJobs` of them): the work outruns the hands.
--   storage  a store of a good the homestead makes (categories `storageCategories`) is full.
--   power    a sink tier (not a charging tier) was served less than it wanted today (Power.shortToday).
--   market   the spare produce (categories `marketCategories`) waiting to be sold is more than `marketLoads` truckloads,
--            or the town now pays under `marketPrice` of full price for the good with the most spare units.
-- Land is not asked: owned land is deferred to M10 (D184, #380), so land never limits a run yet.
-- Nothing holding: nil. There is no workload meter (D184).

local Crops = require("src.sim.systems.crops")
local Food = require("src.sim.systems.food")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local Soil = require("src.sim.systems.soil")
local Weather = require("src.sim.systems.weather")

local Bottleneck = {}

-- The ladder, in the order it is asked.
Bottleneck.ORDER = { "water", "labour", "storage", "power", "market" }

local function cfg(world)
  return world.tuning.progress.bottleneck
end

local function inList(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

--- Dry crops: { id = "water", dry, growing } or nil.
local function water(world)
  if Weather.isRaining(world) then
    return nil -- the rain is watering them
  end
  local dry, growing = 0, 0
  for _, i in ipairs(Crops.plantedTiles(world)) do
    if not Crops.isRipeAt(world, i) then
      growing = growing + 1
      if Crops.needsWaterAt(world, i) then
        dry = dry + 1
      end
    end
  end
  local c = cfg(world)
  if dry >= c.minCrops and dry >= growing * c.waterShare then
    return { id = "water", dry = dry, growing = growing }
  end
  return nil
end

--- Field work waiting: { id = "labour", ripe, weeds, jobs, tiles } or nil.
local function labour(world)
  local ripe = 0
  for _, i in ipairs(Crops.plantedTiles(world)) do
    if Crops.isRipeAt(world, i) then
      local produce = world.registry:get("crops", Crops.cropIdAt(world, i)).produce
      if not Ledger.isFull(world, produce) then -- a harvest held back by a full store is storage's, not the hands'
        ripe = ripe + 1
      end
    end
  end
  local weeds, pullAt = 0, world.tuning.soil.weedPullAt
  for _, i in ipairs(Soil.weedTiles(world)) do
    if Soil.weeds(world, i) >= pullAt then
      weeds = weeds + 1
    end
  end
  local jobs, tiles, c = ripe + weeds, #Crops.fieldTiles(world), cfg(world)
  if jobs >= c.minJobs and jobs >= tiles * c.labourShare then
    return { id = "labour", ripe = ripe, weeds = weeds, jobs = jobs, tiles = tiles }
  end
  return nil
end

--- A full store: { id = "storage", resource, name, have, capacity } or nil (the first in content order).
local function storage(world)
  local categories = cfg(world).storageCategories
  for _, res in ipairs(world.registry:all("resources")) do
    if inList(categories, res.category) and Ledger.isFull(world, res.id) then
      return {
        id = "storage",
        resource = res.id,
        name = res.name,
        have = Ledger.get(world, res.id),
        capacity = Ledger.capacity(world, res.id),
      }
    end
  end
  return nil
end

--- A power tier short today: { id = "power", tier, name } or nil.
local function power(world)
  local tier = Power.shortToday(world)[1]
  return tier and { id = "power", tier = tier, name = Power.tierName(world, tier) } or nil
end

--- Goods piling up for the town: { id = "market", spare, cargo, good?, name?, factor? } or nil (`good` when the price,
--- not the amount, is what holds: the spare good the town has had too much of lately).
local function market(world)
  local c = cfg(world)
  local spare, top, topUnits = 0, nil, 0
  for _, res in ipairs(world.registry:all("resources")) do
    if inList(c.marketCategories, res.category) and Food.sellable(world, res.id) then
      local units = Market.spare(world, res.id)
      spare = spare + units
      if units > topUnits then
        top, topUnits = res.id, units
      end
    end
  end
  local cargo = Market.cargoCapacity(world)
  if spare > 0 and spare >= cargo * c.marketLoads then
    return { id = "market", spare = spare, cargo = cargo }
  end
  if top then
    local factor = Market.satFactor(world, top, 1)
    if factor < c.marketPrice then
      local name = world.registry:get("resources", top).name
      return { id = "market", spare = spare, cargo = cargo, good = top, name = name, factor = factor }
    end
  end
  return nil
end

local ASK = { water = water, labour = labour, storage = storage, power = power, market = market }

--- Every limit that holds now, in ladder order: { { id, ...figures } } (for tests and the harness).
function Bottleneck.all(world)
  local out = {}
  for _, id in ipairs(Bottleneck.ORDER) do
    local found = ASK[id](world)
    if found then
      out[#out + 1] = found
    end
  end
  return out
end

--- What limits the homestead most now: the first limit on the ladder that holds, { id, ...figures }, or nil.
function Bottleneck.current(world)
  for _, id in ipairs(Bottleneck.ORDER) do
    local found = ASK[id](world)
    if found then
      return found
    end
  end
  return nil
end

return Bottleneck
