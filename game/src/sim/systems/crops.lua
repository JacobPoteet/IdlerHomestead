-- Fields & crops (GDD §5.3, §7.3).
--
-- State:
--   world.state.fields = { tilled = { [i] = true }, plan = { [i] = cropId } }
--     plan: the player's field layout. The idle routine tills, plants and replants planned tiles.
--   world.state.crops = { [i] = { id, growth = 0..1, moisture = 0..1 } }
-- Crops grow only while moist; one watering lasts tuning.farming.moistureDays. Nothing grows or
-- can be planted while the ground is frozen, and the first frost kills whatever is still in the
-- ground (GDD §4.1).
-- Emits "crop.planted" { crop, tile }, "crop.harvested" { crop, tile, amount, seeds } and
-- "crop.frosted" { crop, tile }.

local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")

local Crops = {}

function Crops.isMature(crop)
  return crop.growth >= 1
end

function Crops.needsWater(crop)
  return not Crops.isMature(crop) and crop.moisture <= 0
end

--- Set or clear (cropId = nil) the planned crop for a tile. Returns true if allowed.
function Crops.setPlan(world, i, cropId)
  if cropId then
    world.registry:get("crops", cropId)
    if not Grid.terrain(world, i).tillable then
      return false
    end
  end
  world.state.fields.plan[i] = cropId
  return true
end

--- Is tile i part of the player's field layout (a planned crop)?
function Crops.isPlanned(world, i)
  return world.state.fields.plan[i] ~= nil
end

--- Is tile i tilled, planned or planted? (Such tiles can't take a placed object.)
function Crops.tileInUse(world, i)
  local state = world.state
  return state.fields.tilled[i] == true or state.fields.plan[i] ~= nil or state.crops[i] ~= nil
end

--- Is any tile planned, tilled or growing a crop? (A planned layout of any kind means the player
--- or an earlier run of the routine already decided.)
function Crops.hasAnyPlan(world)
  local fields = world.state.fields
  return next(fields.plan) ~= nil or next(fields.tilled) ~= nil or next(world.state.crops) ~= nil
end

-- Free tillable tiles near the truck, best first: close to water, close to the truck, good soil.
local function starterTiles(world, count)
  local cfg = world.tuning.farming
  local grid, fields = world.state.grid, world.state.fields
  local anchor = Land.truck(world) or Land.spawn(world)
  local water = {}
  for i = 1, #grid.terrain do
    if Grid.terrain(world, i).water then
      water[#water + 1] = i
    end
  end
  local scored = {}
  for i = 1, #grid.terrain do
    if
      Grid.distance(grid, i, anchor) <= cfg.starterRadius
      and Grid.terrain(world, i).tillable
      and not world.occupancy[i]
      and not fields.tilled[i]
      and not fields.plan[i]
      and not world.state.crops[i]
    then
      local nearest = #water > 0 and math.huge or 0
      for _, w in ipairs(water) do
        nearest = math.min(nearest, Grid.distance(grid, i, w))
      end
      local score = cfg.starterWaterWeight * nearest
        + cfg.starterTruckWeight * Grid.distance(grid, i, anchor)
        - cfg.starterSoilWeight * grid.soil[i]
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
  for k = 1, math.min(count, #scored) do
    tiles[k] = scored[k].i
  end
  return tiles
end

--- Plan the default starter field (tuning.farming.starterField) when nothing is planned, tilled or
--- growing. Never overrides a player's layout. Skips frozen ground, crops that could not ripen
--- before the freeze, and crops with no seed in stock (one tile per seed). Deterministic: no RNG.
--- Returns the list of planned tile indices (empty if nothing was planned).
function Crops.planStarter(world)
  local planned = {}
  if Crops.hasAnyPlan(world) or Weather.isFrozen(world) then
    return planned
  end
  local cfg = world.tuning.farming
  local daysLeft = Weather.daysToFreeze(world)
  for _, entry in ipairs(cfg.starterField) do
    local def = world.registry:get("crops", entry.crop)
    local seeds = Ledger.get(world, def.seed)
    local count = math.min(entry.tiles, seeds)
    if count > 0 and daysLeft >= def.growDays + cfg.starterFrostMargin then
      for _, i in ipairs(starterTiles(world, count)) do
        Crops.setPlan(world, i, def.id)
        planned[#planned + 1] = i
      end
    end
  end
  if #planned > 0 then
    world.events:emit("crop.starterPlanned", { tiles = #planned })
  end
  return planned
end

local function cropFor(world, i, order)
  return (order and order.crop) or world.state.fields.plan[i]
end

local function hasSeed(world, cropId)
  return cropId ~= nil and Ledger.get(world, world.registry:get("crops", cropId).seed) > 0
end

--- Is there a crop on tile i that is dry and not yet grown?
function Crops.needsWaterAt(world, i)
  local crop = world.state.crops[i]
  return crop ~= nil and Crops.needsWater(crop)
end

--- Water the crop on tile i (drip lines, sprinklers). Returns true if it was dry.
function Crops.waterTile(world, i)
  local crop = world.state.crops[i]
  if crop and Crops.needsWater(crop) then
    crop.moisture = 1
    return true
  end
  return false
end

local function anyCropNeedsWater(world)
  for _, crop in pairs(world.state.crops) do
    if Crops.needsWater(crop) then
      return true
    end
  end
  return false
end
Crops.anyNeedsWater = anyCropNeedsWater

local function eachPlanned(world, add, filter)
  for i in pairs(world.state.fields.plan) do
    if filter(i) then
      add(i)
    end
  end
end

-- The resource that lacks room for the largest possible harvest of this crop, or nil if it fits.
-- (The rolled amount never exceeds this, so a harvest that starts always fits.)
local function harvestShortage(world, crop)
  local def = world.registry:get("crops", crop.id)
  local farming = world.tuning.farming
  local mostProduce = math.floor(def.yield * farming.soilYieldMax) + 1
  return Ledger.shortfall(world, { [def.produce] = mostProduce, [def.seed] = def.seedReturn[2] })
end

local function harvestFits(world, crop)
  return harvestShortage(world, crop) == nil
end

local function registerTasks(world)
  local fields = world.state.fields

  Tasks.register(world, {
    id = "harvest",
    category = "harvest",
    verb = "Harvest",
    clickOrder = 10,
    candidates = function(w, _, add)
      for i, crop in pairs(w.state.crops) do
        if Crops.isMature(crop) then
          add(i)
        end
      end
    end,
    canDo = function(w, _, i)
      local crop = w.state.crops[i]
      -- A full store holds the harvest back: the crop stays in the ground until there is room.
      return crop ~= nil and Crops.isMature(crop) and harvestFits(w, crop)
    end,
    blocked = function(w, _, i)
      local crop = w.state.crops[i]
      return crop ~= nil and Crops.isMature(crop) and harvestShortage(w, crop) or nil
    end,
    workTime = function(w)
      return w.tuning.farming.harvestTime
    end,
    complete = function(w, _, i)
      local crop = w.state.crops[i]
      local def = w.registry:get("crops", crop.id)
      local rng = w:rng("farming")
      local soil = w.state.grid.soil[i]
      local farming = w.tuning.farming
      local mult = farming.soilYieldMin + (farming.soilYieldMax - farming.soilYieldMin) * soil
      local amount = math.max(1, math.floor(def.yield * mult + rng:float()))
      local seeds = rng:int(def.seedReturn[1], def.seedReturn[2])
      w.state.crops[i] = nil
      -- canDo is re-checked every tick of the job, so a store that fills mid-job drops it and the
      -- crop stays put; the rolled amounts never exceed what harvestShortage checked. Overflow
      -- here is only a same-tick safety net and is announced, never silent.
      Ledger.addOrOverflow(w, def.produce, amount, "harvest")
      Ledger.addOrOverflow(w, def.seed, seeds, "harvest")
      w.events:emit("crop.harvested", { crop = def.id, tile = i, amount = amount, seeds = seeds })
    end,
  })

  Tasks.register(world, {
    id = "water_crop",
    category = "water",
    verb = "Water",
    clickOrder = 30,
    candidates = function(w, _, add)
      if Weather.isRaining(w) then
        return -- the rain does the watering; the routine finds other work
      end
      for i, crop in pairs(w.state.crops) do
        if Crops.needsWater(crop) then
          add(i)
        end
      end
    end,
    canDo = function(w, actor, i, order)
      local crop = w.state.crops[i]
      if not crop or actor.bucket <= 0 or Crops.isMature(crop) then
        return false
      end
      -- The player may top up a crop that's still a little moist; the routine waits until dry.
      return order and crop.moisture < w.tuning.farming.topUpMoisture or Crops.needsWater(crop)
    end,
    workTime = function(w)
      return w.tuning.farming.waterTime
    end,
    complete = function(w, actor, i)
      local crop = w.state.crops[i]
      crop.moisture = 1
      actor.bucket = actor.bucket - 1
    end,
  })

  Tasks.register(world, {
    id = "plant",
    category = "plant",
    verb = "Plant",
    clickOrder = 40,
    candidates = function(w, _, add)
      eachPlanned(w, add, function(i)
        return fields.tilled[i] and not w.state.crops[i]
      end)
    end,
    canDo = function(w, _, i, order)
      if Weather.isFrozen(w) then
        return false
      end
      return fields.tilled[i] == true and not w.state.crops[i] and hasSeed(w, cropFor(w, i, order))
    end,
    workTime = function(w)
      return w.tuning.farming.plantTime
    end,
    complete = function(w, _, i, order)
      local cropId = cropFor(w, i, order)
      local def = w.registry:get("crops", cropId)
      if not Ledger.remove(w, def.seed, 1, "plant") then
        return
      end
      fields.plan[i] = cropId
      w.state.crops[i] = { id = cropId, growth = 0, moisture = 0 }
      w.events:emit("crop.planted", { crop = cropId, tile = i })
    end,
  })

  Tasks.register(world, {
    id = "till",
    category = "plant",
    verb = "Till",
    clickOrder = 50,
    candidates = function(w, _, add)
      eachPlanned(w, add, function(i)
        return not fields.tilled[i] and not w.occupancy[i]
      end)
    end,
    canDo = function(w, _, i, order)
      if fields.tilled[i] or w.occupancy[i] or not Grid.terrain(w, i).tillable then
        return false
      end
      -- Player taps on open grass till it for the selected seed; the routine only tills planned tiles.
      return fields.plan[i] ~= nil or (order ~= nil and order.crop ~= nil)
    end,
    workTime = function(w)
      return w.tuning.farming.tillTime
    end,
    complete = function(w, _, i, order)
      fields.tilled[i] = true
      if not fields.plan[i] and order and order.crop then
        fields.plan[i] = order.crop
      end
    end,
  })
end

-- Threat hooks (D67): threats.lua damages crops only through these. ---------------------------

--- Tiles with a crop in the ground, in tile order (deterministic for seeded rolls).
function Crops.plantedTiles(world)
  local tiles = {}
  for i in pairs(world.state.crops) do
    tiles[#tiles + 1] = i
  end
  table.sort(tiles)
  return tiles
end

--- Is the crop on tile i ripe? (false if there is none)
function Crops.isRipeAt(world, i)
  local crop = world.state.crops[i]
  return crop ~= nil and Crops.isMature(crop)
end

--- Knock the crop on tile i back by `setback` of its growth (a ripe crop has to ripen again).
--- Returns true if there was a crop. Emits "crop.damaged" { crop, tile, cause }.
function Crops.setBack(world, i, setback, cause)
  local crop = world.state.crops[i]
  if not crop then
    return false
  end
  crop.growth = math.max(0, crop.growth - setback)
  world.events:emit("crop.damaged", { crop = crop.id, tile = i, cause = cause })
  return true
end

--- Destroy the crop on tile i (the tile stays tilled and planned, so the routine replants it).
--- Returns true if there was a crop. Emits "crop.lost" { crop, tile, cause }.
function Crops.destroy(world, i, cause)
  local crop = world.state.crops[i]
  if not crop then
    return false
  end
  world.state.crops[i] = nil
  world.events:emit("crop.lost", { crop = crop.id, tile = i, cause = cause })
  return true
end

--- Dry every growing crop by `days` worth of moisture (a drought's extra evaporation).
function Crops.evaporate(world, days)
  local loss = days / world.tuning.farming.moistureDays
  for _, crop in pairs(world.state.crops) do
    if not Crops.isMature(crop) then
      crop.moisture = math.max(0, crop.moisture - loss)
    end
  end
end

--- The first frost: every crop still in the ground dies (mature ones too).
function Crops.frost(world)
  local tiles = {}
  for i in pairs(world.state.crops) do
    tiles[#tiles + 1] = i
  end
  table.sort(tiles)
  for _, i in ipairs(tiles) do
    local crop = world.state.crops[i]
    world.state.crops[i] = nil
    world.events:emit("crop.frosted", { crop = crop.id, tile = i })
  end
end

function Crops.init(world)
  local state = world.state
  state.fields = state.fields or { tilled = {}, plan = {} }
  state.crops = state.crops or {}
  registerTasks(world)
  world.events:on("weather.froze", function()
    Crops.frost(world)
  end)
end

function Crops.tick(world, dt)
  if Weather.isFrozen(world) then
    return
  end
  local farming, dayLength = world.tuning.farming, world.tuning.time.dayLength
  local dryRate = dt / (farming.moistureDays * dayLength)
  local raining = Weather.isRaining(world) -- rain is free water for every crop (D51)
  for _, crop in pairs(world.state.crops) do
    if raining then
      crop.moisture = 1
    end
    if crop.growth < 1 and crop.moisture > 0 then
      local def = world.registry:get("crops", crop.id)
      crop.growth = math.min(1, crop.growth + dt / (def.growDays * dayLength))
      crop.moisture = math.max(0, crop.moisture - dryRate)
    end
  end
end

return Crops
