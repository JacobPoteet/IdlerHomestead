-- Inventory: equipment owned this run and placeable objects waiting to be placed.
-- Also sets up the starting gear (tuning.run) once per run, and keeps storage capacities in step
-- with placed objects that have `storage` (e.g. the woodshed raises the wood limit).
--
-- State: world.state.inventory = { equipment = { [catalogId] = true }, objects = { [objectId] = count } }
-- Emits "object.placed" { object, tile }.

local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")

local Inventory = {}

function Inventory.hasEquipment(world, id)
  return world.state.inventory.equipment[id] == true
end

--- Ids of the catalog equipment owned this run (sorted).
function Inventory.equipmentIds(world)
  local ids = {}
  for id in pairs(world.state.inventory.equipment) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

--- The same sorted ids written into the caller's scratch list `into` (entries past the returned count
--- are stale): allocation-free for hot paths such as Stats.modifier. Returns the count.
function Inventory.fillEquipmentIds(world, into)
  local n = 0
  for id in pairs(world.state.inventory.equipment) do
    local j = n
    while j >= 1 and into[j] > id do
      into[j + 1] = into[j]
      j = j - 1
    end
    into[j + 1] = id
    n = n + 1
  end
  return n
end

--- The owned catalog item that supersedes `id` (its `replaces` names it), or nil. A superseded item is not
--- bought again and its modifiers no longer count (D115): the sturdy rod is the basic rod, upgraded.
function Inventory.supersededBy(world, id)
  for _, item in ipairs(world.registry:all("catalog")) do
    if item.replaces == id then
      if Inventory.owns(world, item.id) then
        return item.id
      end
      local deeper = Inventory.supersededBy(world, item.id) -- a tier III also covers tier I (D198)
      if deeper then
        return deeper
      end
    end
  end
  return nil
end

--- Does catalog item `itemId` replace `id`, directly or down the chain of tiers (D198)?
function Inventory.replaces(world, itemId, id)
  local item = world.registry:get("catalog", itemId)
  while item.replaces do
    if item.replaces == id then
      return true
    end
    item = world.registry:get("catalog", item.replaces)
  end
  return false
end

--- Keep a piece of equipment for the run. An upgrade drops the equipment it replaces (so both tiers never add
--- up), and equipment already superseded by an owned upgrade is not added (a perk's starting rod can come
--- second).
function Inventory.addEquipment(world, id)
  local item = world.registry:get("catalog", id)
  local equipment = world.state.inventory.equipment
  if Inventory.supersededBy(world, id) then
    return
  end
  local below = item.replaces
  while below do -- the whole ladder below it goes (a tier III bought straight over a tier I leaves neither, D198)
    equipment[below] = nil
    below = world.registry:get("catalog", below).replaces
  end
  equipment[id] = true
  if world.state.grid then
    Inventory.refreshStorage(world) -- tiers can size a store (cistern, coop, pen)
  end
end

function Inventory.addObject(world, id, count)
  world.registry:get("objects", id)
  local objects = world.state.inventory.objects
  objects[id] = (objects[id] or 0) + (count or 1)
end

function Inventory.objectCount(world, id)
  return world.state.inventory.objects[id] or 0
end

--- Does this run hold a catalog item: its equipment kept, or its object in the inventory or placed?
function Inventory.owns(world, id)
  local item = world.registry:get("catalog", id)
  if item.equipment then
    return Inventory.hasEquipment(world, id)
  end
  if item.object then
    if Inventory.objectCount(world, item.object) > 0 then
      return true
    end
    for _, obj in pairs(world.state.grid.objects) do
      if obj.id == item.object then
        return true
      end
    end
  end
  return false
end

--- Recompute storage limits: each resource's base capacity plus placed objects' `storage`.
function Inventory.refreshStorage(world)
  local extra = {}
  for _, obj in pairs(world.state.grid.objects) do
    local def = world.registry:get("objects", obj.id)
    local scale = Stats.scale(world, def) -- a tier of the cistern, coop or pen sizes its store (D198)
    for res, amount in pairs(def.storage or {}) do
      extra[res] = (extra[res] or 0) + math.floor(amount * scale + 0.5)
    end
  end
  for _, res in ipairs(world.registry:all("resources")) do
    if res.capacity then
      Ledger.setCapacity(world, res.id, extra[res.id] and res.capacity + extra[res.id] or nil)
    end
  end
end

-- Is an object of this type standing on the land?
local function hasPlaced(world, id)
  for _, obj in pairs(world.state.grid.objects) do
    if obj.id == id then
      return true
    end
  end
  return false
end

local function clearable(def)
  return def.clearable ~= false and def.clearTime ~= nil
end

-- Does any tile within one step of t (diagonals included) have terrain satisfying `test`?
local function touches(world, t, test)
  local grid = world.state.grid
  local tx, ty = Grid.coords(grid, t)
  for dy = -1, 1 do
    for dx = -1, 1 do
      if Grid.inBounds(grid, tx + dx, ty + dy) and test(Grid.terrain(world, Grid.index(grid, tx + dx, ty + dy))) then
        return true
      end
    end
  end
  return false
end

--- What would it take to put an object of this type with its top-left at tile i? (D79: any buildable
--- tile, grass or tilled soil, that the object's own rules allow; trees, rocks, logs, brush and junk are
--- cleared first, crops and plans are removed.) Returns a table:
---   ok         the spot is legal once whatever is in the way is cleared or removed
---   reason     when not ok: "bounds", "terrain" (road or water), "object" (something that can't be
---              cleared, such as the truck or another building), "rule" (the object's own rule, see
---              `rule`: "waterTable", "road", "water", "offRoad") or "claimed" (another order has it)
---   immediate  ok and nothing in the way, so it can be placed at once
---   tiles      the footprint
---   clear      { { anchor, id } ... } clearable objects on the footprint, by anchor
---   crops      { { tile, crop, mature } ... } growing crops that would be removed
---   plans      planned tiles with no crop yet that would lose their plan
---   tilled     tilled tiles under the footprint (kept for a pick-up, #15)
---   actor      the homesteader stands where a blocking object would go (a moment's wait)
--- (Objects with `placeNear = "water"`, like micro-hydro, must also touch a water tile;
--- `placeOn = "waterTable"`, like wells and pumps, needs a tile with a high enough water table;
--- `placeNear = "road"`, the roadside stand, must touch the road without covering it.)
---
--- `replaces` (anchors) lists the buildings the object goes up over (an upgrade whose object def has `replaces`, the
--- shack over the camp, D115). They do not block; with one placed the footprint must overlap it (rule "replace"), and
--- not while the homesteader sleeps in it (rule "replaceAsleep").
---
--- `ignoreAnchor`: an object whose footprint counts as free ground (the object being moved, D98).
function Inventory.check(world, id, i, ignoreHeld, ignoreAnchor)
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local x, y = Grid.coords(grid, i)
  local tiles = Grid.footprintTiles(grid, def, x, y)
  local result =
    { ok = false, immediate = false, clear = {}, replaces = {}, crops = {}, plans = 0, tilled = 0, actor = false }
  if not tiles then
    result.reason = "bounds"
    return result
  end
  result.tiles = tiles
  local touchesWater, touchesRoad = false, false
  local seen = {}
  for _, t in ipairs(tiles) do
    local terrain = Grid.terrain(world, t)
    if not terrain.walkable or terrain.water or not terrain.buildable then
      result.reason = "terrain" -- roads and water stay off limits
      return result
    end
    local anchor = world.occupancy[t]
    if anchor and anchor ~= ignoreAnchor and not seen[anchor] then
      seen[anchor] = true
      local other = Grid.object(world, t)
      if def.replaces and other.id == def.replaces then
        result.replaces[#result.replaces + 1] = anchor -- an upgrade goes up over the old building (D115)
      elseif not clearable(other) then
        result.reason = "object"
        return result
      else
        result.clear[#result.clear + 1] = { anchor = anchor, id = other.id }
      end
    end
    if def.placeOn == "waterTable" and not Land.hasWaterTable(world, t) then
      result.reason, result.rule = "rule", "waterTable" -- wells and pumps need groundwater close to the surface
      return result
    end
    if def.placeNear == "water" and not touchesWater then
      touchesWater = touches(world, t, function(terr)
        return terr.water
      end)
    end
    if def.placeNear == "road" and not touchesRoad then
      touchesRoad = touches(world, t, function(terr)
        return terr.id == "road"
      end)
    end
    local status = Crops.tileStatus(world, t)
    if status.held and not ignoreHeld then
      result.reason = "claimed"
      return result
    end
    if status.crop then
      result.crops[#result.crops + 1] = { tile = t, crop = status.crop, mature = status.mature }
    elseif status.plan then
      result.plans = result.plans + 1
    end
    if status.tilled then
      result.tilled = result.tilled + 1
    end
    if def.blocks then
      for _, actor in ipairs(Actors.list(world)) do
        if Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5)) == t then
          result.actor = true
        end
      end
    end
  end
  if def.placeNear == "road" and not touchesRoad then
    result.reason, result.rule = "rule", "road"
    return result
  end
  if def.placeNear == "water" and not touchesWater then
    result.reason, result.rule = "rule", "water"
    return result
  end
  if def.replaces then
    -- An upgrade with the old building standing must go over it; the bed the homesteader sleeps in stays (D115).
    if #result.replaces == 0 and hasPlaced(world, def.replaces) then
      result.reason, result.rule = "rule", "replace"
      return result
    end
    for _, anchor in ipairs(result.replaces) do
      local held = require("src.sim.systems.placement").moveCheck(world, anchor)
      if not held.ok then
        result.reason, result.rule = "rule", "replaceAsleep"
        return result
      end
    end
    table.sort(result.replaces)
  end
  table.sort(result.clear, function(a, b)
    return a.anchor < b.anchor
  end)
  result.ok = true
  result.immediate = #result.clear == 0 and #result.crops == 0 and result.plans == 0 and not result.actor
  return result
end

-- Reachability (D204, #435) ---------------------------------------------------------------------------------

-- Pathfinding's moves: eight ways, no cutting a corner past a blocked tile (src/sim/pathfind.lua).
local STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- Where the walk starts: the road (walkable, never buildable, so nothing can stand on it), or the tiles
-- round the truck on land with no road.
local function roadTiles(world)
  local road = Grid.bankTiles(world, "road")
  if #road > 0 then
    return road
  end
  local truck = Land.truck(world)
  local tiles = {}
  if truck then
    local grid = world.state.grid
    local x, y = Grid.coords(grid, truck)
    for dy = -1, 2 do
      for dx = -1, 2 do
        if Grid.inBounds(grid, x + dx, y + dy) then
          tiles[#tiles + 1] = Grid.index(grid, x + dx, y + dy)
        end
      end
    end
  end
  return tiles
end

-- Which of `goals` (a list of tile lists; a goal is met when any one of its tiles is reached) can be walked to
-- from the road, with walkability given by `open(t)`? A breadth-first flood that stops once every goal is met.
-- Returns a list of booleans, one per goal.
local function reach(world, open, goals)
  local grid = world.state.grid
  local w, h = grid.w, grid.h
  local met, left, goalsAt = {}, 0, {}
  for g, tiles in ipairs(goals) do
    met[g] = false
    left = left + 1
    for _, t in ipairs(tiles) do
      goalsAt[t] = goalsAt[t] or {}
      table.insert(goalsAt[t], g)
    end
  end
  local seen, queue, head = {}, {}, 1
  for _, t in ipairs(roadTiles(world)) do
    if not seen[t] and open(t) then
      seen[t] = true
      queue[#queue + 1] = t
    end
  end
  while head <= #queue and left > 0 do
    local t = queue[head]
    head = head + 1
    for _, g in ipairs(goalsAt[t] or {}) do
      if not met[g] then
        met[g] = true
        left = left - 1
      end
    end
    local x = (t - 1) % w + 1
    local y = (t - x) / w + 1
    for _, d in ipairs(STEPS) do
      local nx, ny = x + d[1], y + d[2]
      if nx >= 1 and ny >= 1 and nx <= w and ny <= h then
        local n = (ny - 1) * w + nx
        if not seen[n] and open(n) then
          local ok = d[1] == 0 or d[2] == 0 or (open((y - 1) * w + nx) and open((ny - 1) * w + x))
          if ok then
            seen[n] = true
            queue[#queue + 1] = n
          end
        end
      end
    end
  end
  return met
end

-- The tiles a bed is slept in from: within one step of the shelter's top-left tile (Tasks' work spot).
local function bedSpots(grid, anchor)
  local x, y = Grid.coords(grid, anchor)
  local tiles = {}
  for dy = -1, 1 do
    for dx = -1, 1 do
      if Grid.inBounds(grid, x + dx, y + dy) then
        tiles[#tiles + 1] = Grid.index(grid, x + dx, y + dy)
      end
    end
  end
  return tiles
end

--- Would putting an object of this type at tile i wall the homesteader in (D204, #435)? `check` is the
--- `Inventory.check` result for that spot (ok), `ignoreAnchor` the object being moved. The spot is refused when,
--- with the object standing there (and what it clears, replaces or moves gone), the homesteader's tile or the
--- spot a bed is slept in from (a new bed's too) could no longer be walked to from the road although it could
--- before. A flood
--- fill over the land: call it when a placement is asked for or carried out, never per tick or per frame.
function Inventory.shutsIn(world, id, check, ignoreAnchor)
  local def = world.registry:get("objects", id)
  if not def.blocks then
    return false
  end
  local grid = world.state.grid
  local covered, gone = {}, {}
  for _, t in ipairs(check.tiles) do
    covered[t] = true
  end
  for _, anchor in ipairs(check.replaces) do
    gone[anchor] = true
  end
  for _, c in ipairs(check.clear) do
    gone[c.anchor] = true
  end
  if ignoreAnchor then
    gone[ignoreAnchor] = true
  end
  local goals = {}
  local hs = Actors.homesteader(world) -- (none yet while the starting kit is set out)
  if hs then
    local here = Grid.index(grid, math.floor(hs.x + 0.5), math.floor(hs.y + 0.5))
    if not covered[here] then -- (one standing where it goes steps aside first; the order checks again then)
      goals[#goals + 1] = { here }
    end
  end
  for _, anchor in ipairs(Grid.anchorsWith(world, "shelter")) do
    if not gone[anchor] then
      goals[#goals + 1] = bedSpots(grid, anchor)
    end
  end
  if def.shelter then
    goals[#goals + 1] = bedSpots(grid, check.tiles[1]) -- the new bed (a corner of the map has no spot to sleep from)
  end
  if #goals == 0 then
    return false
  end
  local after = reach(world, function(t)
    if covered[t] then
      return false
    end
    local anchor = world.occupancy[t]
    if anchor and gone[anchor] then
      return Grid.terrain(world, t).walkable == true
    end
    return Grid.walkable(world, t)
  end, goals)
  local cut = {}
  for g in ipairs(goals) do
    if not after[g] then
      cut[#cut + 1] = goals[g]
    end
  end
  if #cut == 0 then
    return false
  end
  -- Something is out of reach: refuse only if this placement is what cut it off (a pocket that was already shut
  -- before, on an old save, does not stop every placement on the land; a new bed deep in an uncleared wood was
  -- out of reach before too, and the homesteader keeps sleeping in the bed it can reach, D82).
  local before = reach(world, function(t)
    return Grid.walkable(world, t)
  end, cut)
  for g in ipairs(cut) do
    if before[g] then
      return true
    end
  end
  return false
end

--- Can an object of this type be placed with its top-left at tile i right now, with nothing to clear
--- or remove first? (Tilled soil without a crop or plan is fine, D79.)
function Inventory.canPlace(world, id, i)
  return Inventory.check(world, id, i).immediate
end

--- Place an object from inventory at tile i. Returns true on success (false too when it would wall the homesteader
--- in, `Inventory.shutsIn`). Tilled soil under the footprint is
--- covered (the object remembers which tiles were tilled, `tilled = { [tile] = true }`, so picking it up
--- can hand the soil back as it was, #15).
---
--- An upgrade (`replaces`, the shack over the camp, D115) removes the building it stands over in the same step: no
--- refund, the old one's tilled-soil record carries over to the tiles the new one covers (the rest goes back to
--- tilled soil), and an unplaced copy of the old one waiting in the inventory is dropped too. Emits
--- "object.replaced" { object, old, tile } for each building removed, before "object.placed".
function Inventory.place(world, id, i)
  if Inventory.objectCount(world, id) <= 0 then
    return false
  end
  local check = Inventory.check(world, id, i)
  if not check.immediate or Inventory.shutsIn(world, id, check) then
    return false
  end
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local x, y = Grid.coords(grid, i)
  local tiles = Grid.footprintTiles(grid, def, x, y)
  local was
  local removed = {}
  for _, old in ipairs(check.replaces) do
    local record = require("src.sim.systems.placement").replaceLift(world, old)
    removed[#removed + 1] = record.id
    for t in pairs(record.tilled or {}) do
      was = was or {}
      was[t] = true
    end
  end
  local anchor = Grid.placeObject(world, id, x, y)
  if not anchor then
    return false
  end
  local covered = {}
  for _, t in ipairs(tiles) do
    covered[t] = true
    if Crops.cover(world, t, "placement") then
      was = was or {}
      was[t] = true
    end
  end
  local own
  for t in pairs(was or {}) do
    if covered[t] then
      own = own or {}
      own[t] = true
    else
      Crops.restoreTilled(world, t) -- soil the old building covered and the new one does not
    end
  end
  grid.objects[anchor].tilled = own
  local objects = world.state.inventory.objects
  objects[id] = objects[id] - 1
  if objects[id] <= 0 then
    objects[id] = nil
  end
  if def.replaces and objects[def.replaces] then
    objects[def.replaces] = objects[def.replaces] - 1 -- an unplaced old one is not needed any more
    if objects[def.replaces] <= 0 then
      objects[def.replaces] = nil
    end
  end
  Inventory.refreshStorage(world)
  for _, old in ipairs(removed) do
    world.events:emit("object.replaced", { object = id, old = old, tile = anchor })
  end
  world.events:emit("object.placed", { object = id, tile = anchor })
  return true
end

--- Put a starting object on the nearest free tiles around the spawn (or leave it in the inventory when there is no room).
function Inventory.placeNearSpawn(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  for r = 1, 6 do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r and Grid.inBounds(grid, sx + dx, sy + dy) then
          local i = Grid.index(grid, sx + dx, sy + dy)
          if Inventory.canPlace(world, id, i) and Grid.terrain(world, i).id ~= "road" then
            Inventory.addObject(world, id)
            Inventory.place(world, id, i)
            return
          end
        end
      end
    end
  end
  Inventory.addObject(world, id) -- nowhere free: leave it in the inventory to place by hand
end

function Inventory.init(world)
  local state = world.state
  if state.inventory then
    Inventory.refreshStorage(world)
    return
  end
  state.inventory = { equipment = {}, objects = {} }
  for _, id in ipairs(world.tuning.run.startingEquipment) do
    Inventory.addEquipment(world, id)
  end
  for _, id in ipairs(world.tuning.run.startingObjects) do
    Inventory.placeNearSpawn(world, id)
  end
end

return Inventory
