-- Fields & crops (GDD §5.3, §7.3).
--
-- State:
--   world.state.fields = { tilled = { [i] = true }, plan = { [i] = cropId } }
--     plan: the player's field layout. The idle routine tills, plants and replants planned tiles.
--   world.state.crops = { [i] = { id, growth = 0..1, moisture = 0..1 } }
-- A harvest draws the tile's fertility and yield scales with it; the same family twice in a row builds pest
-- pressure that cuts yield, and weeds cut it until the `weed` task pulls them (soil.lua, D178, D179, D180).
-- Crops grow only while moist; one watering lasts tuning.farming.moistureDays. Nothing grows or
-- can be planted while the ground is frozen, and the first frost kills whatever is still in the
-- ground (GDD §4.1), except a `hardy` crop, which sits the winter out dormant (D177). A crop is sown only in
-- the seasons of its `plantSeasons`.
-- Perennials (PLAN_DEPTH 8.5, D183): a crop whose definition has `perennial` is planted once and stays. Its state adds
--   stage ("sapling" planted this season, "first" bearing its small first crop, "mature" after one winter), seasons and
--   winters passed since planting, rest (nothing to ripen: it takes no water and does not grow) and fruited (this
--   year's crop is picked). It ripens only inside its fruitSeason and only once a year; a harvest resets it instead of
--   removing it. A young plant is data for the deer and bears of phase C (`Crops.vulnerableTo`).
-- Emits "crop.planted" { crop, tile }, "crop.harvested" { crop, tile, amount, seeds } and
-- "crop.frosted" { crop, tile }. "crop.harvested" also carries the tile's `pressure`, whether the harvest `repeated` its family, and its `weeds`.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Quality = require("src.sim.systems.quality")
local Soil = require("src.sim.systems.soil")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")

local Crops = {}

--- Is the crop's plant window open in `season` (default: now)? Radish and potato are open all three unfrozen
--- seasons, garlic only in autumn (D177). Takes a crop id or a crop definition.
function Crops.inWindow(world, crop, season)
  local def = type(crop) == "table" and crop or world.registry:get("crops", crop)
  season = season or Calendar.now(world).season
  for _, s in ipairs(def.plantSeasons) do
    if s == season then
      return true
    end
  end
  return false
end

--- Can the plant task sow this crop right now: the ground is not frozen and the season is in its window?
function Crops.canPlantNow(world, crop)
  return not Weather.isFrozen(world) and Crops.inWindow(world, crop)
end

--- Does the crop live through the freeze (D177)? Tender crops die at it; hardy ones sit dormant.
function Crops.survivesFrost(world, crop)
  local def = type(crop) == "table" and crop or world.registry:get("crops", crop)
  return def.frost == "hardy"
end

function Crops.isMature(crop)
  return crop.growth >= 1
end

function Crops.needsWater(crop)
  return not Crops.isMature(crop) and not crop.rest and crop.moisture <= 0
end

-- Perennials (D183) -----------------------------------------------------------------------------------------

--- A fresh crop record for `def` (a crop definition) as the plant task makes it.
function Crops.newCrop(world, def)
  local crop = { id = def.id, growth = 0, moisture = 0, thirst = 0, tends = 0 }
  if def.perennial then
    crop.stage, crop.seasons, crop.winters, crop.rest = "sapling", 0, 0, true
  end
  return crop
end

--- Is the crop record a perennial (it has a stage)?
function Crops.isPerennial(crop)
  return crop.stage ~= nil
end

--- Is the plant young, not yet through a winter? The animals concern only these.
function Crops.isYoung(crop)
  return crop.stage == "sapling" or crop.stage == "first"
end

--- Is the young plant on tile i drawn to `animal` ("deer", "bear"), by its definition? Data for the night threats of
--- phase C (PLAN_DEPTH 6.1); nothing in the sim acts on it yet.
function Crops.vulnerableTo(world, i, animal)
  local crop = world.state.crops[i]
  if not crop or not Crops.isYoung(crop) then
    return false
  end
  for _, a in ipairs(world.registry:get("crops", crop.id).perennial.vulnerable) do
    if a == animal then
      return true
    end
  end
  return false
end

--- Share of its full crop a perennial gives now: the first-year share while it is young, Annuals give 1.
function Crops.yieldShare(world, crop)
  if not crop.stage then
    return 1
  end
  local cfg = world.tuning.perennials
  return crop.stage == "mature" and 1 or cfg.firstYieldShare
end

--- Should the plant be ripening now: past the sapling stage, in its fruiting season and not yet picked this year?
local function ripening(world, crop, def, season)
  return crop.stage ~= "sapling" and season == def.perennial.fruitSeason and not crop.fruited
end

-- A new season begins: every perennial counts it, a winter that has ended makes it older, it starts
-- ripening in its fruiting season and an unripe crop at the end of it is lost.
local function seasonBegins(world, season)
  local seasons = world.tuning.time.seasons
  local at = 1
  for k, s in ipairs(seasons) do
    if s == season then
      at = k
    end
  end
  local leftWinter = Weather.isFrozenSeason(world, seasons[(at - 2) % #seasons + 1])
  for _, i in ipairs(Crops.plantedTiles(world)) do
    local crop = world.state.crops[i]
    local def = world.registry:get("crops", crop.id)
    if def.perennial then
      crop.seasons = crop.seasons + 1
      if leftWinter then
        crop.winters = crop.winters + 1
      end
      crop.stage = crop.winters >= 1 and "mature" or crop.seasons >= 1 and "first" or "sapling"
      if season == def.perennial.fruitSeason then
        crop.fruited = nil -- a new year's crop
      elseif crop.growth < 1 then
        crop.growth = 0 -- the season ended before the fruit ripened
      end
      crop.rest = not ripening(world, crop, def, season)
    end
  end
end

--- Set or clear (cropId = nil) the planned crop for a tile. Returns true if allowed.
function Crops.setPlan(world, i, cropId)
  if cropId then
    world.registry:get("crops", cropId)
    if not Grid.terrain(world, i).tillable or world.state.fields.held[i] then
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

--- What the farm holds on tile i: { tilled, plan = cropId|nil, crop = cropId|nil, mature, held }.
--- The placement preview (D79) reads it to say what a building would remove.
function Crops.tileStatus(world, i)
  local fields, crop = world.state.fields, world.state.crops[i]
  return {
    tilled = fields.tilled[i] == true,
    plan = fields.plan[i],
    crop = crop and crop.id or nil,
    mature = crop ~= nil and Crops.isMature(crop),
    held = fields.held[i] == true,
  }
end

--- Is tile i held for a queued placement (D79)?
function Crops.isHeld(world, i)
  return world.state.fields.held[i] == true
end

--- Hold (or release) tiles for a queued placement (D79): a held tile takes no new plan, tilling or
--- planting, so the routine cannot grow something where a building is about to go.
function Crops.hold(world, tiles, held)
  for _, i in ipairs(tiles) do
    world.state.fields.held[i] = held and true or nil
  end
end

--- Take tile i out of farming for a building (D79): the crop, the plan and the tilled flag go (no
--- refund; the seed is not returned). Returns whether the tile was tilled, so a later pick-up (#15) can
--- give the soil back as it was. Emits "crop.removed" { crop, tile, mature, cause } for a crop lost.
function Crops.cover(world, i, cause, keepTilled)
  local fields, crop = world.state.fields, world.state.crops[i]
  local wasTilled = fields.tilled[i] == true
  if crop then
    world.state.crops[i] = nil
    world.events:emit("crop.removed", { crop = crop.id, tile = i, mature = Crops.isMature(crop), cause = cause })
  end
  fields.plan[i] = nil
  if not keepTilled then
    fields.tilled[i] = nil
  end
  return wasTilled
end

--- Give tile i back to farming as tilled soil (the reverse of cover, for picking a building up, #15).
function Crops.restoreTilled(world, i)
  world.state.fields.tilled[i] = true
end

--- The player destroys the crop on tile i from its panel (D110, #255): the same removal as covering it or
--- pulling it with the Untill tool (no refund, plan dropped), leaving bare tilled soil. Returns true if there
--- was a crop. Emits "crop.removed" with cause "destroy".
function Crops.remove(world, i)
  if not world.state.crops[i] then
    return false
  end
  Crops.cover(world, i, "destroy", true)
  return true
end

--- What planting `cropId` over `tiles` would replace (D110, #257): every tile with a growing crop, the same
--- kind too (planning is an override). Returns { tiles = { i ... } in the given order, ripe = how many are ripe, byCrop = { [id] = n } }.
--- A tile that cannot take a plan (held for a building, not tillable) is not counted.
function Crops.replacePreview(world, tiles, cropId)
  local out = { tiles = {}, ripe = 0, byCrop = {} }
  for _, i in ipairs(tiles) do
    local crop = world.state.crops[i]
    if crop and cropId and not world.state.fields.held[i] and Grid.terrain(world, i).tillable then
      out.tiles[#out.tiles + 1] = i
      out.byCrop[crop.id] = (out.byCrop[crop.id] or 0) + 1
      if Crops.isMature(crop) then
        out.ripe = out.ripe + 1
      end
    end
  end
  return out
end

--- Plan `cropId` over `tiles` and replace any crop already growing there, in one action (D110, #257):
--- the old crop is pulled with no refund (`Crops.cover`, `crop.removed` cause "replace"; the soil stays tilled)
--- and the tile is planned for the new one. The same crop is replaced too (the user decided planning is an intentional override). Only the player's plan action
--- calls this; the routine never replaces a crop on its own. cropId nil clears plans and never pulls a crop.
--- Returns { planned = tiles that took the plan, replaced = crops pulled }.
function Crops.planReplacing(world, tiles, cropId)
  local planned, replaced = 0, 0
  for _, i in ipairs(tiles) do
    local crop = world.state.crops[i]
    if crop and cropId and not world.state.fields.held[i] and Grid.terrain(world, i).tillable then
      Crops.cover(world, i, "replace", true)
      replaced = replaced + 1
    end
    if Crops.setPlan(world, i, cropId) and cropId then
      planned = planned + 1
    end
  end
  return { planned = planned, replaced = replaced }
end

--- Is any tile planned, tilled or growing a crop? (A planned layout of any kind means the player
--- or an earlier run of the routine already decided.)
function Crops.hasAnyPlan(world)
  local fields = world.state.fields
  return next(fields.plan) ~= nil or next(fields.tilled) ~= nil or next(world.state.crops) ~= nil
end

-- Tiles the homesteader can walk to from the truck within `radius` (4-neighbour flood fill over walkable
-- tiles, so anything it reaches here the pathfinder reaches too). Returns a set { [i] = true }.
local ORTHO = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function reachableFromTruck(world, anchor, radius)
  local grid = world.state.grid
  local reached, queue, head = {}, {}, 1
  local function visit(i)
    if not reached[i] and Grid.walkable(world, i) and Grid.distance(grid, i, anchor) <= radius then
      reached[i] = true
      queue[#queue + 1] = i
    end
  end
  local ax, ay = Grid.coords(grid, anchor)
  for dy = -1, 1 do
    for dx = -1, 1 do
      if Grid.inBounds(grid, ax + dx, ay + dy) then
        visit(Grid.index(grid, ax + dx, ay + dy))
      end
    end
  end
  local spawn = Land.spawn(world)
  if spawn then
    visit(spawn)
  end
  while head <= #queue do
    local x, y = Grid.coords(grid, queue[head])
    head = head + 1
    for _, d in ipairs(ORTHO) do
      if Grid.inBounds(grid, x + d[1], y + d[2]) then
        visit(Grid.index(grid, x + d[1], y + d[2]))
      end
    end
  end
  return reached
end

-- A compact block of `count` free tillable tiles near the truck (D88, #137). Each candidate has a
-- base score (water distance, truck distance, soil: lower is better) and must be workable from a tile
-- the homesteader can walk to from the truck. The block grows from the best-scoring tile: every next
-- tile touches the block, and each neighbouring tile (8 around it) already in it lowers the tile's score by
-- starterAdjacencyWeight, so the field fills out as a lump instead of a strip along the creek.
-- Deterministic (ties go to the lower index); uses no randomness. Returns tiles in growth order.
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
  local reached = reachableFromTruck(world, anchor, cfg.starterRadius + 1)
  local base = {}
  for i = 1, #grid.terrain do
    if
      Grid.distance(grid, i, anchor) <= cfg.starterRadius
      and Grid.terrain(world, i).tillable
      and not world.occupancy[i]
      and not fields.tilled[i]
      and not fields.plan[i]
      and not fields.held[i]
      and not world.state.crops[i]
    then
      -- workable: a reached walkable tile is within one step of it (or it is one itself)
      local x, y = Grid.coords(grid, i)
      local ok = false
      for dy = -1, 1 do
        for dx = -1, 1 do
          if Grid.inBounds(grid, x + dx, y + dy) and reached[Grid.index(grid, x + dx, y + dy)] then
            ok = true
          end
        end
      end
      if ok then
        local nearest = #water > 0 and math.huge or 0
        for _, w in ipairs(water) do
          nearest = math.min(nearest, Grid.distance(grid, i, w))
        end
        base[i] = cfg.starterWaterWeight * nearest
          + cfg.starterTruckWeight * Grid.distance(grid, i, anchor)
          - cfg.starterSoilWeight * grid.soil[i]
      end
    end
  end
  local tiles, chosen = {}, {}
  while #tiles < count do
    local best, bestScore, bestTouch
    for i, b in pairs(base) do
      if not chosen[i] then
        local x, y = Grid.coords(grid, i)
        local near, room, touch = 0, 0, false
        for dy = -1, 1 do
          for dx = -1, 1 do
            if (dx ~= 0 or dy ~= 0) and Grid.inBounds(grid, x + dx, y + dy) then
              if chosen[Grid.index(grid, x + dx, y + dy)] then
                touch = true
                near = near + 1
              end
              if base[Grid.index(grid, x + dx, y + dy)] then
                room = room + 1
              end
            end
          end
        end
        -- the seed tile has no block to touch yet: prefer one with open ground around it, so the block can grow
        local score = b - cfg.starterAdjacencyWeight * (#tiles == 0 and room or near)
        -- touching the block beats not touching (the seed tile has nothing to touch); then the lower
        -- score, then the lower index
        local better = best == nil
          or (touch and not bestTouch)
          or (touch == bestTouch and (score < bestScore or (score == bestScore and i < best)))
        if better then
          best, bestScore, bestTouch = i, score, touch
        end
      end
    end
    if not best then
      break
    end
    chosen[best] = true
    tiles[#tiles + 1] = best
  end
  return tiles
end

--- Plan the default starter field (tuning.farming.starterField) when nothing is planned, tilled or
--- growing. Never overrides a player's layout. Skips frozen ground, crops that could not ripen
--- before the freeze, and crops with no seed in stock (one tile per seed). The field is one compact
--- block reachable from the truck (D88). Deterministic: no RNG.
--- Returns the list of planned tile indices (empty if nothing was planned).
function Crops.planStarter(world)
  local planned = {}
  if Crops.hasAnyPlan(world) or Weather.isFrozen(world) then
    return planned
  end
  local cfg = world.tuning.farming
  local daysLeft = Weather.daysToFreeze(world)
  local wanted, total = {}, 0
  for _, entry in ipairs(cfg.starterField) do
    local def = world.registry:get("crops", entry.crop)
    local count = math.min(entry.tiles, Ledger.get(world, def.seed))
    if
      count > 0
      and Crops.inWindow(world, def)
      and (Crops.survivesFrost(world, def) or daysLeft >= def.growDays + cfg.starterFrostMargin)
    then
      wanted[#wanted + 1] = { def = def, count = count }
      total = total + count
    end
  end
  local tiles = starterTiles(world, total)
  local n = 0
  for _, w in ipairs(wanted) do
    for _ = 1, w.count do
      n = n + 1
      if tiles[n] then
        Crops.setPlan(world, tiles[n], w.def.id)
        planned[#planned + 1] = tiles[n]
      end
    end
  end
  if #planned > 0 then
    world.events:emit("crop.starterPlanned", { tiles = #planned })
  end
  return planned
end

--- Could a crop planted today be caught by the first frost (D37, D70, #165)? Returns nil when it
--- ripens in time (or the ground is already frozen, when nothing can be planted), else
--- { level = "late" (cannot ripen: it needs more watered days than are left) | "tight" (within the
--- starter-field margin of that), daysLeft (days to the freeze, counting today), growDays }.
function Crops.frostRisk(world, cropId)
  if Weather.isFrozen(world) then
    return nil
  end
  local def = world.registry:get("crops", cropId)
  if Crops.survivesFrost(world, def) then
    return nil
  end
  local left = Weather.daysToFreeze(world)
  if left == math.huge then
    return nil
  end
  local level
  if left < def.growDays then
    level = "late"
  elseif left < def.growDays + world.tuning.farming.starterFrostMargin then
    level = "tight"
  end
  return level and { level = level, daysLeft = left, growDays = def.growDays } or nil
end

--- Watered days a growing crop still needs to ripen (0 when ripe).
function Crops.daysToRipe(world, crop)
  return (1 - math.min(1, crop.growth)) * world.registry:get("crops", crop.id).growDays
end

local function cropFor(world, i, order)
  return (order and order.crop) or world.state.fields.plan[i]
end

local function hasSeed(world, cropId)
  return cropId ~= nil and Ledger.get(world, world.registry:get("crops", cropId).seed) > 0
end

--- Tiles that are part of the farm: tilled, planned or planted, ascending (the Soil lens's field).
function Crops.fieldTiles(world)
  local seen, list = {}, {}
  local function add(i)
    if not seen[i] then
      seen[i] = true
      list[#list + 1] = i
    end
  end
  for i in pairs(world.state.fields.tilled) do
    add(i)
  end
  for i in pairs(world.state.fields.plan) do
    add(i)
  end
  for i in pairs(world.state.crops) do
    add(i)
  end
  table.sort(list)
  return list
end

--- Is any crop in the ground on tile i?
function Crops.hasCropAt(world, i)
  return world.state.crops[i] ~= nil
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

--- A hand order tended the crop on tile i (it was watered, or its tile weeded, by the player's own tap or a policy's
--- order, never by the routine): one more tend towards the tended mark (D182). Returns true if there was a crop.
function Crops.tend(world, i, order)
  local crop = world.state.crops[i]
  if not crop or not order then
    return false
  end
  crop.tends = (crop.tends or 0) + 1
  return true
end

--- Does the crop on tile i carry the tended mark?
function Crops.isTendedAt(world, i)
  local crop = world.state.crops[i]
  return crop ~= nil and Quality.isTended(world, crop)
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
      local mult = Soil.yieldMultiplier(w, i) -- soil quality, fertility and pest pressure (D178, D179), read before the harvest changes them
      local pressure, repeated, weeds = Soil.pressure(w, i), Soil.repeats(w, i, def), Soil.weeds(w, i)
      local tier, penalty, tended = Quality.grade(w, i, crop, def) -- fertility, weeds, thirst and the tended mark (D182), read before the harvest changes them
      local share = Crops.yieldShare(w, crop) -- a young perennial gives less (D183)
      local amount = math.max(1, math.floor(def.yield * mult * share + rng:float()))
      local seeds = rng:int(def.seedReturn[1], def.seedReturn[2])
      if def.perennial then
        -- the plant stays: it rests until its next fruiting season
        crop.growth, crop.thirst, crop.tends = 0, 0, 0
        crop.rest, crop.fruited = true, true
      else
        w.state.crops[i] = nil
      end
      Soil.harvested(w, i, def)
      -- canDo is re-checked every tick of the job, so a store that fills mid-job drops it and the
      -- crop stays put; the rolled amounts never exceed what harvestShortage checked. Overflow
      -- here is only a same-tick safety net and is announced, never silent.
      local stored = Ledger.addOrOverflow(w, def.produce, amount, "harvest")
      Quality.add(w, def.produce, tier, stored)
      Ledger.addOrOverflow(w, def.seed, seeds, "harvest")
      local harvest = {
        crop = def.id,
        tile = i,
        amount = amount,
        seeds = seeds,
        pressure = pressure,
        repeated = repeated,
        weeds = weeds,
        quality = tier,
        penalty = penalty,
        tended = tended,
        stage = crop.stage,
      }
      w.events:emit("crop.harvested", harvest)
    end,
  })

  -- Weeding (D180): the idle routine pulls a tile from `weedPullAt`, the player's tap pulls any weedy tile.
  -- A tap on a ripe or dry crop still harvests or waters first (clickOrder 35 sits after both).
  Tasks.register(world, {
    id = "weed",
    category = "maintenance",
    verb = "Weed",
    clickOrder = 35,
    candidates = function(w, _, add)
      local pullAt = w.tuning.soil.weedPullAt
      for _, i in ipairs(Soil.weedTiles(w)) do
        if Soil.weeds(w, i) >= pullAt then
          add(i)
        end
      end
    end,
    canDo = function(w, _, i, order)
      local level = Soil.weeds(w, i)
      if level <= 0 or fields.held[i] then
        return false
      end
      return order ~= nil or level >= w.tuning.soil.weedPullAt
    end,
    workTime = function(w)
      return w.tuning.soil.weedPullTime
    end,
    complete = function(w, _, i, order)
      Soil.pull(w, i)
      Crops.tend(w, i, order)
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
    complete = function(w, actor, i, order)
      local crop = w.state.crops[i]
      crop.moisture = 1
      actor.bucket = actor.bucket - 1
      Crops.tend(w, i, order)
    end,
  })

  Tasks.register(world, {
    id = "plant",
    category = "plant",
    verb = "Plant",
    clickOrder = 40,
    standing = true, -- a planned tile is a standing order (D92)
    candidates = function(w, _, add)
      eachPlanned(w, add, function(i)
        return fields.tilled[i] and not w.state.crops[i]
      end)
    end,
    canDo = function(w, _, i, order)
      local cropId = cropFor(w, i, order)
      if cropId == nil or not Crops.canPlantNow(w, cropId) then
        return false -- frozen ground, or the crop's plant window is shut (a planned tile waits for its season)
      end
      return fields.tilled[i] == true and not w.state.crops[i] and not fields.held[i] and hasSeed(w, cropId)
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
      w.state.crops[i] = Crops.newCrop(w, def)
      w.events:emit("crop.planted", { crop = cropId, tile = i })
    end,
  })

  Tasks.register(world, {
    id = "till",
    category = "plant",
    verb = "Till",
    clickOrder = 50,
    standing = true, -- a planned tile is tilled whatever the seed stock (D92)
    candidates = function(w, _, add)
      eachPlanned(w, add, function(i)
        return not fields.tilled[i] and not w.occupancy[i] and not fields.held[i]
      end)
    end,
    canDo = function(w, _, i, order)
      if fields.tilled[i] or w.occupancy[i] or fields.held[i] or not Grid.terrain(w, i).tillable then
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

  -- Untill (D79): tilled soil goes back to grass. The player's Untill tool orders it on any tilled tile
  -- without a crop and the tile drops its plan; the idle routine only untills tilled tiles that nobody
  -- planned (leftovers of a cleared plan), and only when tuning.farming.routineUntill is on.
  Tasks.register(world, {
    id = "untill",
    category = "plant",
    verb = "Untill",
    clickOrder = 5, -- ahead of plant and till, so the tool in hand wins on a tilled tile
    candidates = function(w, _, add)
      if not w.tuning.farming.routineUntill then
        return
      end
      for i in pairs(fields.tilled) do
        if not fields.plan[i] and not w.state.crops[i] and not fields.held[i] and not w.occupancy[i] then
          add(i)
        end
      end
    end,
    canDo = function(w, _, i, order)
      if not fields.tilled[i] or w.occupancy[i] then
        return false
      end
      if order then
        return order.tool == "untill" -- the player's tool also pulls a planted crop (#254)
      end
      return w.tuning.farming.routineUntill and not w.state.crops[i] and not fields.plan[i] and not fields.held[i]
    end,
    workTime = function(w)
      return w.tuning.farming.untillTime
    end,
    complete = function(w, _, i)
      if w.state.crops[i] then
        -- A planted crop (#254): pull it and drop the plan, leaving bare tilled soil (the prepared state);
        -- no refund, same as covering it with a building. Untill again turns the soil back to grass.
        Crops.cover(w, i, "untill", true)
        return
      end
      fields.tilled[i] = nil
      fields.plan[i] = nil
      w.events:emit("field.untilled", { tile = i })
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

--- Id of the crop on tile i, or nil.
function Crops.cropIdAt(world, i)
  local crop = world.state.crops[i]
  return crop and crop.id or nil
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
  if crop.stage == "mature" then
    -- an established perennial loses this year's fruit, not the plant (D183)
    crop.growth, crop.rest, crop.fruited = 0, true, true
  else
    world.state.crops[i] = nil
  end
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
    if not Crops.survivesFrost(world, crop.id) then -- hardy crops sit the winter out dormant (D177)
      world.state.crops[i] = nil
      world.events:emit("crop.frosted", { crop = crop.id, tile = i })
    end
  end
end

function Crops.init(world)
  local state = world.state
  state.fields = state.fields or { tilled = {}, plan = {}, held = {} }
  state.fields.held = state.fields.held or {} -- tiles a queued placement keeps free of farming (D79)
  state.crops = state.crops or {}
  registerTasks(world)
  world.events:on("weather.froze", function()
    Crops.frost(world)
  end)
  world.events:on("calendar.newSeason", function(e)
    seasonBegins(world, e.season)
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
    if crop.growth < 1 and not crop.rest then
      if crop.moisture > 0 then
        local def = world.registry:get("crops", crop.id)
        crop.growth = math.min(1, crop.growth + dt / (def.growDays * dayLength))
        crop.moisture = math.max(0, crop.moisture - dryRate * def.waterAppetite)
      else
        crop.thirst = (crop.thirst or 0) + dt / dayLength -- game days stood dry, graded at harvest (D182)
      end
    end
  end
end

return Crops
