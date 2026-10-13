-- Inventory: equipment owned this run and placeable objects waiting to be placed.
-- Also sets up the starting gear (tuning.run) once per run, and keeps storage capacities in step
-- with placed objects that have `storage` (e.g. the woodshed raises the firewood limits).
--
-- State: world.state.inventory = { equipment = { [catalogId] = true }, objects = { [objectId] = count } }
-- Emits "object.placed" { object, tile }.

local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

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

function Inventory.addEquipment(world, id)
  world.registry:get("catalog", id)
  world.state.inventory.equipment[id] = true
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
    for res, amount in pairs(world.registry:get("objects", obj.id).storage or {}) do
      extra[res] = (extra[res] or 0) + amount
    end
  end
  for _, res in ipairs(world.registry:all("resources")) do
    if res.capacity then
      Ledger.setCapacity(world, res.id, extra[res.id] and res.capacity + extra[res.id] or nil)
    end
  end
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
--- `ignoreAnchor`: an object whose footprint counts as free ground (the object being moved, D98).
function Inventory.check(world, id, i, ignoreHeld, ignoreAnchor)
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local x, y = Grid.coords(grid, i)
  local tiles = Grid.footprintTiles(grid, def, x, y)
  local result = { ok = false, immediate = false, clear = {}, crops = {}, plans = 0, tilled = 0, actor = false }
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
      if not clearable(other) then
        result.reason = "object"
        return result
      end
      result.clear[#result.clear + 1] = { anchor = anchor, id = other.id }
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
      for _, actor in ipairs(Actors.list(world)) do        if Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5)) == t then
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
  table.sort(result.clear, function(a, b)
    return a.anchor < b.anchor
  end)
  result.ok = true
  result.immediate = #result.clear == 0 and #result.crops == 0 and result.plans == 0 and not result.actor
  return result
end

--- Can an object of this type be placed with its top-left at tile i right now, with nothing to clear
--- or remove first? (Tilled soil without a crop or plan is fine, D79.)
function Inventory.canPlace(world, id, i)
  return Inventory.check(world, id, i).immediate
end

--- Place an object from inventory at tile i. Returns true on success. Tilled soil under the footprint is
--- covered (the object remembers which tiles were tilled, `tilled = { [tile] = true }`, so picking it up
--- can hand the soil back as it was, #15).
function Inventory.place(world, id, i)
  if Inventory.objectCount(world, id) <= 0 or not Inventory.canPlace(world, id, i) then
    return false
  end
  local grid = world.state.grid
  local x, y = Grid.coords(grid, i)
  local tiles = Grid.footprintTiles(grid, world.registry:get("objects", id), x, y)
  local anchor = Grid.placeObject(world, id, x, y)
  if not anchor then
    return false
  end
  local was
  for _, t in ipairs(tiles) do
    if Crops.cover(world, t, "placement") then
      was = was or {}
      was[t] = true
    end
  end
  grid.objects[anchor].tilled = was
  local objects = world.state.inventory.objects
  objects[id] = objects[id] - 1
  if objects[id] <= 0 then
    objects[id] = nil
  end
  Inventory.refreshStorage(world)
  world.events:emit("object.placed", { object = id, tile = anchor })
  return true
end

-- Place starting objects on the nearest free tiles around the spawn.
local function placeNearSpawn(world, id)
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
    placeNearSpawn(world, id)
  end
end

return Inventory
