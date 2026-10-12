-- Water (GDD §5.3, §7.4): the automation ladder from hauling to drip irrigation.
--
-- Rung 0, the creek: the actor fills the bucket at the water's edge (actor.bucket = waterings left).
-- Rung 1, a dug well and a hand pump: placed on a tile with a high water table (Land.hasWaterTable),
--   they are closer places to fill the bucket (content `waterSource { fillTime }`), and work in winter.
-- Rung 2, the solar pump and the cistern: the pump is a power sink (content `sink` with schedule
--   "fill", tier "pumps"); while powered it adds `pump.rate` units an hour, scaled by how well the
--   pumps tier is served (Power.sinkRatio), to the resource "water". The cistern is what gives
--   "water" a capacity (`storage`), and is also a bucket-filling place that draws on the stock.
-- Rung 3, drip lines: not an actor. Every tick a drip line waters thirsty crops within its radius,
--   spending `tuning.water.dripUnitsPerWatering` from the stock, so the routine never has to haul.
--   With the stock empty the zone is dry: crops thirst as before and the actor hauls by hand.
--
-- Rain (D51) also fills the cistern, for free, while it rains and a cistern exists (see tickRain).
--
-- Systems talk through the ledger (the "water" stock), the task board (fetch_water) and events.
-- State: world.state.water = { acc = { [pump anchor] = fraction of a batch }, dry = { [drip anchor] =
--   true while announced dry }, hand, drip, pumped = totals of waterings by hand / by drip lines /
--   units pumped, pumpedDay = last day "water.pumped" was announced }
-- Emits "water.drawn" { source, tile } when the bucket is filled somewhere other than the creek,
-- "water.pumped" { amount } at most once a day while pumps run, "water.dripped" { tile, drip },
-- "water.dry" { drip } when a drip line has a thirsty crop and no water, and "water.restored" { drip }.

local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")

local Water = {}

local STOCK = "water"

local function state(world)
  return world.state.water
end

--- Waterings a full bucket holds (base + equipment such as the big bucket).
function Water.bucketCapacity(world)
  return world.tuning.actors.bucketCapacity + Stats.modifier(world, "bucketCapacity")
end

-- Objects ---------------------------------------------------------------------------------------

-- Anchors of placed objects whose definition has `key`, ascending so every pass is deterministic.
local function anchorsWith(world, key)
  local list = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if world.registry:get("objects", obj.id)[key] then
      list[#list + 1] = anchor
    end
  end
  table.sort(list)
  return list
end

local function defAt(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id)
end

-- Stock -----------------------------------------------------------------------------------------

--- Cistern units in stock, and the room cisterns give: units, capacity.
function Water.stored(world)
  return Ledger.get(world, STOCK), Ledger.capacity(world, STOCK)
end

--- Is any cistern placed (does the stock have somewhere to live)?
function Water.hasCistern(world)
  return Ledger.capacity(world, STOCK) > 0
end

--- Stock as a fraction of capacity (0 with no cistern).
function Water.fraction(world)
  local units, capacity = Water.stored(world)
  return capacity > 0 and units / capacity or 0
end

--- Waterings made so far this run: { hand = by the actor, drip = by drip lines, pumped = units
--- pumped into cisterns, rained = units the rain put in cisterns }.
function Water.stats(world)
  local s = state(world)
  return { hand = s.hand, drip = s.drip, pumped = s.pumped, rained = s.rained }
end

-- Pumps -----------------------------------------------------------------------------------------

--- What a pump is doing: "off" (switched off), "nocistern" (nowhere to put water), "full",
--- "nopower" (wanted power, got none), "slow" (partly powered) or "pumping".
function Water.pumpState(world, anchor)
  if not Power.isEnabled(world, anchor) then
    return "off"
  end
  if not Water.hasCistern(world) then
    return "nocistern"
  end
  local sink = Power.sinkState(world, anchor)
  if sink == "idle" then
    return "full"
  elseif sink == "short" then
    return Power.sinkRatio(world, anchor) > 0 and "slow" or "nopower"
  end
  return "pumping"
end

local function tickPumps(world, pumps, hours)
  local s, cfg = state(world), world.tuning.water
  for _, anchor in ipairs(pumps) do
    local mode = Water.pumpState(world, anchor)
    if mode == "pumping" or mode == "slow" then
      local acc = (s.acc[anchor] or 0) + defAt(world, anchor).pump.rate * hours * Power.sinkRatio(world, anchor)
      if acc >= cfg.pumpBatch then
        local added = Ledger.add(world, STOCK, acc, "pump")
        acc = added < acc and 0 or acc - added
        s.pumped = s.pumped + added
        local day = Calendar.now(world).day
        if added > 0 and s.pumpedDay ~= day then
          s.pumpedDay = day
          world.events:emit("water.pumped", { amount = added })
        end
      end
      s.acc[anchor] = acc
    end
  end
end

-- Rain ------------------------------------------------------------------------------------------

-- Rain runs into the cistern for free (D51): `rainWaterRate` units an hour times the day's rainfall,
-- up to capacity. Without a cistern there is nowhere to keep it.
local function tickRain(world, hours)
  local rainfall = Weather.rainfall(world)
  if rainfall <= 0 or not Water.hasCistern(world) then
    return
  end
  local s = state(world)
  s.rain = s.rain + world.tuning.weather.rainWaterRate * rainfall * hours
  if s.rain >= world.tuning.water.pumpBatch then
    local added = Ledger.add(world, STOCK, s.rain, "rain")
    s.rain = added < s.rain and 0 or s.rain - added
    s.rained = s.rained + added
  end
end

-- Drip lines ------------------------------------------------------------------------------------

-- Covered tiles per drip line: runtime only (derived from the grid), never saved.
local coverage = setmetatable({}, { __mode = "k" })

--- Tiles a drip line at `anchor` covers (ascending tile indices, inside the map).
function Water.dripTiles(world, anchor)
  local byAnchor = coverage[world]
  if not byAnchor then
    byAnchor = {}
    coverage[world] = byAnchor
  end
  local def = defAt(world, anchor)
  local cached = byAnchor[anchor]
  if cached and cached.id == def.id then
    return cached.tiles
  end
  local grid = world.state.grid
  local ax, ay = Grid.coords(grid, anchor)
  local radius, tiles = def.drip.radius, {}
  for y = ay - radius, ay + radius do
    for x = ax - radius, ax + radius do
      if Grid.inBounds(grid, x, y) then
        tiles[#tiles + 1] = Grid.index(grid, x, y)
      end
    end
  end
  table.sort(tiles)
  byAnchor[anchor] = { id = def.id, tiles = tiles }
  return tiles
end

--- Can a drip line water a crop right now (is there a unit's worth in the stock)?
function Water.dripHasWater(world)
  return Ledger.get(world, STOCK) >= world.tuning.water.dripUnitsPerWatering
end

--- A drip line's state: "ok" (water to give), "dry" (the stock is empty, so crops in its zone
--- go thirsty and the actor hauls by hand) or "frozen" (nothing grows, so nothing is watered).
function Water.dripState(world, anchor)
  if Weather.isFrozen(world) then
    return "frozen"
  end
  return Water.dripHasWater(world) and "ok" or "dry"
end

--- Thirsty crops in a drip line's zone.
function Water.dripThirsty(world, anchor)
  local n = 0
  for _, i in ipairs(Water.dripTiles(world, anchor)) do
    if Crops.needsWaterAt(world, i) then
      n = n + 1
    end
  end
  return n
end

local function tickDrip(world, drips)
  if Weather.isFrozen(world) then
    return
  end
  local s, cost = state(world), world.tuning.water.dripUnitsPerWatering
  for _, anchor in ipairs(drips) do
    local unmet = false
    for _, i in ipairs(Water.dripTiles(world, anchor)) do
      if Crops.needsWaterAt(world, i) then
        if Ledger.remove(world, STOCK, cost, "drip") then
          Crops.waterTile(world, i)
          s.drip = s.drip + 1
          world.events:emit("water.dripped", { tile = i, drip = anchor })
        else
          unmet = true
        end
      end
    end
    if unmet and not s.dry[anchor] then
      s.dry[anchor] = true
      world.events:emit("water.dry", { drip = anchor })
    elseif not unmet and s.dry[anchor] and Water.dripHasWater(world) then
      s.dry[anchor] = nil
      world.events:emit("water.restored", { drip = anchor })
    end
  end
end

-- Filling the bucket ----------------------------------------------------------------------------

-- The definition of a bucket-filling object covering tile i, or nil (the creek is not an object).
local function fillObject(world, i)
  local def = Grid.object(world, i)
  return def and def.waterSource and def or nil
end

function Water.init(world)
  local s = world.state.water or {}
  world.state.water = s
  -- Fields are filled in so saves from before the water ladder keep loading.
  s.acc = s.acc or {}
  s.dry = s.dry or {}
  s.hand = s.hand or 0
  s.drip = s.drip or 0
  s.pumped = s.pumped or 0
  s.pumpedDay = s.pumpedDay or 0
  s.rain = s.rain or 0
  s.rained = s.rained or 0
  world.events:on("task.completed", function(e)
    if e.task == "water_crop" then
      s.hand = s.hand + 1
    end
  end)

  Tasks.register(world, {
    id = "fetch_water",
    category = "water",
    verb = "Fill bucket",
    clickOrder = 60,
    candidates = function(w, actor, add)
      -- Only head for water when the bucket is empty and something is thirsty.
      if actor.bucket > 0 or Weather.isRaining(w) or not Crops.anyNeedsWater(w) then
        return
      end
      for _, terrainId in ipairs({ "water", "ford" }) do
        for _, i in ipairs(Grid.bankTiles(w, terrainId)) do
          if Weather.waterTarget(w, i) then
            add(i)
          end
        end
      end
      for _, anchor in ipairs(anchorsWith(w, "waterSource")) do
        add(anchor)
      end
    end,
    canDo = function(w, actor, i)
      if actor.bucket >= Water.bucketCapacity(w) then
        return false
      end
      local def = fillObject(w, i)
      if def then
        return not def.waterSource.stored or Ledger.get(w, STOCK) >= 1
      end
      return Grid.terrain(w, i).water == true
    end,
    workTime = function(w, _, i)
      local def = fillObject(w, i)
      if def then
        return def.waterSource.fillTime
      end
      return w.tuning.farming.fetchWaterTime + Weather.iceWork(w, i)
    end,
    complete = function(w, actor, i)
      local def = fillObject(w, i)
      local room = Water.bucketCapacity(w) - actor.bucket
      if not def then
        Weather.openHole(w, i)
        actor.bucket = Water.bucketCapacity(w)
        return
      end
      if def.waterSource.stored then
        -- A cistern gives what it has, up to a full bucket.
        local take = math.min(room, math.floor(Ledger.get(w, STOCK)))
        if take < 1 or not Ledger.remove(w, STOCK, take, "bucket") then
          return
        end
        actor.bucket = actor.bucket + take
      else
        actor.bucket = Water.bucketCapacity(w)
      end
      w.events:emit("water.drawn", { source = def.id, tile = i })
    end,
  })
end

function Water.tick(world, dt)
  -- One pass over the placed objects for both lists (ascending anchors, so every run is the same).
  local pumps, drips = {}, {}
  for anchor, obj in pairs(world.state.grid.objects) do
    local def = world.registry:get("objects", obj.id)
    if def.pump then
      pumps[#pumps + 1] = anchor
    end
    if def.drip then
      drips[#drips + 1] = anchor
    end
  end
  table.sort(pumps)
  table.sort(drips)
  tickPumps(world, pumps, dt / Calendar.hourLength(world))
  tickRain(world, dt / Calendar.hourLength(world))
  tickDrip(world, drips)
end

return Water
