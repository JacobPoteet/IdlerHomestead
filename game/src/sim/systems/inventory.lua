-- Inventory: equipment owned this run and placeable objects waiting to be placed.
-- Also sets up the starting gear (tuning.run) once per run.
--
-- State: world.state.inventory = { equipment = { [catalogId] = true }, objects = { [objectId] = count } }
-- Emits "object.placed" { object, tile }.

local Grid = require("src.sim.grid")

local Inventory = {}

function Inventory.hasEquipment(world, id)
  return world.state.inventory.equipment[id] == true
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

--- Can an object of this type be placed with its top-left at tile i?
function Inventory.canPlace(world, id, i)
  local grid = world.state.grid
  local def = world.registry:get("objects", id)
  local x, y = Grid.coords(grid, i)
  local tiles = Grid.footprintTiles(grid, def, x, y)
  if not tiles then
    return false
  end
  for _, t in ipairs(tiles) do
    local terrain = Grid.terrain(world, t)
    if not terrain.walkable or terrain.water or world.occupancy[t] then
      return false
    end
    if world.state.fields.tilled[t] or world.state.fields.plan[t] or world.state.crops[t] then
      return false
    end
    for _, actor in ipairs(world.state.actors or {}) do
      if def.blocks and Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5)) == t then
        return false
      end
    end
  end
  return true
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
  world.events:emit("object.placed", { object = id, tile = anchor })
  return true
end

-- Place starting objects on the nearest free tiles around the spawn.
local function placeNearSpawn(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
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
