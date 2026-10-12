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

--- Can an object of this type be placed with its top-left at tile i? (Objects with
--- `placeNear = "water"`, like micro-hydro, must also touch a water tile; `placeOn = "waterTable"`,
--- like wells and pumps, needs a tile with a high enough water table; `placeNear = "road"`, the
--- roadside stand, must touch the road without covering it.)
function Inventory.canPlace(world, id, i)
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local x, y = Grid.coords(grid, i)
  local tiles = Grid.footprintTiles(grid, def, x, y)
  if not tiles then
    return false
  end
  local touchesWater = false
  local touchesRoad = false
  for _, t in ipairs(tiles) do
    local terrain = Grid.terrain(world, t)
    if not terrain.walkable or terrain.water or world.occupancy[t] then
      return false
    end
    if def.offRoad and terrain.id == "road" then
      return false -- a henhouse does not go in the road
    end
    if def.placeOn == "waterTable" and not Land.hasWaterTable(world, t) then
      return false -- wells and pumps need groundwater close to the surface
    end
    if def.placeNear == "water" and not touchesWater then
      local tx, ty = Grid.coords(grid, t)
      for dy = -1, 1 do
        for dx = -1, 1 do
          if Grid.inBounds(grid, tx + dx, ty + dy) and Grid.terrain(world, Grid.index(grid, tx + dx, ty + dy)).water then
            touchesWater = true
          end
        end
      end
    end
    if def.placeNear == "road" then
      if Grid.terrain(world, t).id == "road" then
        return false -- the stand sits beside the road, not on it
      end
      if not touchesRoad then
        local tx, ty = Grid.coords(grid, t)
        for dy = -1, 1 do
          for dx = -1, 1 do
            if Grid.inBounds(grid, tx + dx, ty + dy) and Grid.terrain(world, Grid.index(grid, tx + dx, ty + dy)).id == "road" then
              touchesRoad = true
            end
          end
        end
      end
    end
    if Crops.tileInUse(world, t) then
      return false
    end
    for _, actor in ipairs(Actors.list(world)) do
      if def.blocks and Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5)) == t then
        return false
      end
    end
  end
  if def.placeNear == "road" and not touchesRoad then
    return false
  end
  return def.placeNear ~= "water" or touchesWater
end

--- Place an object from inventory at tile i. Returns true on success.
function Inventory.place(world, id, i)
  if Inventory.objectCount(world, id) <= 0 or not Inventory.canPlace(world, id, i) then
    return false
  end
  local x, y = Grid.coords(world.state.grid, i)
  local anchor = Grid.placeObject(world, id, x, y)
  if not anchor then
    return false
  end
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
