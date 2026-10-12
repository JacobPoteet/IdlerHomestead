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

-- Would the largest possible harvest of this crop fit in storage right now?
local function harvestFits(world, crop)
  local def = world.registry:get("crops", crop.id)
  local farming = world.tuning.farming
  local mostProduce = math.floor(def.yield * farming.soilYieldMax) + 1
  return Ledger.room(world, def.produce) >= mostProduce and Ledger.room(world, def.seed) >= def.seedReturn[2]
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
      -- harvestFits guards the start of the job; storage can still fill while the work runs.
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
  for _, crop in pairs(world.state.crops) do
    if crop.growth < 1 and crop.moisture > 0 then
      local def = world.registry:get("crops", crop.id)
      crop.growth = math.min(1, crop.growth + dt / (def.growDays * dayLength))
      crop.moisture = math.max(0, crop.moisture - dryRate)
    end
  end
end

return Crops
