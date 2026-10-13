-- Placement orders (GDD D79, issue #197): put a building on ground that is not clear yet.
--
-- The player can place an object on any buildable tile (grass or tilled soil) its own rules allow. When
-- trees, rocks, logs, brush or junk stand on the footprint, the request becomes an *order*: the
-- homesteader clears them (the ordinary "clear" task: yields go to the ledger, a full store holds the
-- job, D59) and the object is placed the moment the footprint is clear. The tiles are held at once so
-- nothing new is planted there. Crops and planned tiles under the footprint stay (a crop keeps growing
-- and can be harvested) until everything else is clear; they are removed then, just before the object
-- goes up (no refund; D86), so cancelling an order never destroys anything. Orders run in the order
-- they were made.
--
-- State: world.state.placement = { orders = { { object = objectId, tile = anchorIndex, why? } ... } }
--   why: nil, or { kind = "full", resource = id } (a store has no room for the clearing),
--        { kind = "unreachable" } or { kind = "blocked" } (no spot to stand or step aside to).
-- Emits "placement.queued" { object, tile }, "placement.held" { object, tile, kind, resource? },
-- "placement.cancelled" { object, tile, reason }, "placement.done" { object, tile }.

local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Sleep = require("src.sim.systems.sleep")
local Tasks = require("src.sim.systems.tasks")

local Placement = {}

local function orders(world)
  return world.state.placement.orders
end

local function footprint(world, order)
  local grid = world.state.grid
  local x, y = Grid.coords(grid, order.tile)
  return Grid.footprintTiles(grid, world.registry:get("objects", order.object), x, y)
end

--- Queued orders, oldest first. Callers must not modify them.
function Placement.orders(world)
  return orders(world)
end

--- The tile indices an order's object covers.
function Placement.footprintOf(world, order)
  return footprint(world, order)
end

--- The queued order whose footprint covers tile i, or nil.
function Placement.orderAt(world, i)
  for _, order in ipairs(orders(world)) do
    for _, t in ipairs(footprint(world, order)) do
      if t == i then
        return order
      end
    end
  end
  return nil
end

--- How many of this object are in the inventory and not spoken for by a queued order.
function Placement.available(world, id)
  local n = Inventory.objectCount(world, id)
  for _, order in ipairs(orders(world)) do
    if order.object == id then
      n = n - 1
    end
  end
  return n
end

--- What the order would do: the Inventory.check result plus `available` (an item is free to use) and, when
--- another queued order already covers part of the footprint, ok = false with reason "claimed".
--- `queue` is true when the spot is legal but needs clearing or removing first.
function Placement.preview(world, id, i)
  local result = Inventory.check(world, id, i)
  result.available = Placement.available(world, id) > 0
  result.queue = result.ok and not result.immediate
  return result
end

--- The resource whose full store would hold back clearing the objects a preview lists (D59), or nil.
function Placement.shortage(world, preview)
  local clear = Tasks.get(world, "clear")
  local hs = Actors.homesteader(world)
  for _, target in ipairs(preview.clear) do
    local full = clear.blocked(world, hs, target.anchor)
    if full then
      return full
    end
  end
  return nil
end

--- Take the item to tile i: place it at once when the footprint is clear, else queue an order (crops and
--- plans under it go later, when the rest is clear). Returns "placed", "queued", or nil plus the reason it was refused
--- ("none" when no such item is free, else the Inventory.check reason).
function Placement.request(world, id, i)
  if Placement.available(world, id) <= 0 then
    return nil, "none"
  end
  local result = Inventory.check(world, id, i)
  if not result.ok then
    return nil, result.reason, result.rule
  end
  if result.immediate then
    if Inventory.place(world, id, i) then
      return "placed"
    end
    return nil, "blocked"
  end
  -- Crops and plans stay for now (D86): they are removed by `tick` only once everything else is clear, just
  -- before the building goes up, so cancelling an order never destroys anything.
  Crops.hold(world, result.tiles, true)
  orders(world)[#orders(world) + 1] = { object = id, tile = i }
  world.events:emit("placement.queued", { object = id, tile = i })
  return "queued"
end

local function drop(world, index, reason)
  local order = table.remove(orders(world), index)
  Crops.hold(world, footprint(world, order), false)
  if reason then
    world.events:emit("placement.cancelled", { object = order.object, tile = order.tile, reason = reason })
  end
  return order
end

--- Cancel the queued order covering tile i. Returns true if there was one. (Whatever was already cleared
--- stays cleared; crops and plans are never touched before the last step, so nothing is lost.)
function Placement.cancel(world, i)
  for index, order in ipairs(orders(world)) do
    for _, t in ipairs(footprint(world, order)) do
      if t == i then
        drop(world, index, "player")
        return true
      end
    end
  end
  return false
end

local function setWhy(world, order, why)
  local was = order.why
  if (was and was.kind) == (why and why.kind) and (was and was.resource) == (why and why.resource) then
    return
  end
  order.why = why
  if why then
    world.events:emit("placement.held", { object = order.object, tile = order.tile, kind = why.kind, resource = why.resource })
  end
end

-- A walkable tile just outside the footprint to step to when the homesteader stands where it goes.
local function sideStep(world, order)
  local grid = world.state.grid
  local x, y = Grid.coords(grid, order.tile)
  local def = world.registry:get("objects", order.object)
  local fw, fh = def.footprintW or 1, def.footprintH or 1
  for dy = -1, fh do
    for dx = -1, fw do
      local tx, ty = x + dx, y + dy
      if Grid.inBounds(grid, tx, ty) and (dx < 0 or dy < 0 or dx >= fw or dy >= fh) then
        local t = Grid.index(grid, tx, ty)
        if Grid.walkable(world, t) then
          return t
        end
      end
    end
  end
  return nil
end

-- Hand the idle homesteader the next job an order needs: clearing its first object, or stepping aside.
local function assign(world, hs, order, check)
  if #check.clear == 0 then
    local t = sideStep(world, order)
    local job = t and Tasks.jobFor(world, hs, "move", t)
    if not job then
      setWhy(world, order, { kind = "blocked" })
      return false
    end
    setWhy(world, order, nil)
    hs.job = job
    Tasks.reserve(world, hs, job)
    return true
  end
  local clear = Tasks.get(world, "clear")
  local full
  for _, target in ipairs(check.clear) do
    if clear.canDo(world, hs, target.anchor) then
      local job = Tasks.jobFor(world, hs, "clear", target.anchor)
      if job then
        setWhy(world, order, nil)
        hs.job = job
        Tasks.reserve(world, hs, job)
        return true
      end
    elseif not full then
      full = clear.blocked(world, hs, target.anchor)
    end
  end
  setWhy(world, order, full and { kind = "full", resource = full } or { kind = "unreachable" })
  return false
end

function Placement.tick(world)
  local list = orders(world)
  if #list == 0 then
    return
  end
  local hs = Actors.homesteader(world)
  local free = not hs.job and not hs.order and not hs.asleep and not Sleep.isBedtime(world) and not Sleep.resting(hs)
  local used = {}
  local index = 1
  while index <= #list do
    local order = list[index]
    used[order.object] = (used[order.object] or 0) + 1
    local tiles = footprint(world, order)
    local check = Inventory.check(world, order.object, order.tile, true)
    if used[order.object] > Inventory.objectCount(world, order.object) then
      drop(world, index, "item")
    elseif not check.ok then
      drop(world, index, check.reason) -- something that can't be cleared now stands there
    else
      if #check.clear == 0 and (#check.crops > 0 or check.plans > 0) then
        -- Everything else is clear: the crops and plans go now, the last step before the building (D86).
        -- Tilled soil stays until it is down.
        for _, t in ipairs(tiles) do
          Crops.cover(world, t, "placement", true)
        end
        check = Inventory.check(world, order.object, order.tile, true)
      end
      if check.immediate then
        Crops.hold(world, tiles, false) -- Inventory.place reads a held tile as another order's
        if Inventory.place(world, order.object, order.tile) then
          table.remove(list, index)
          world.events:emit("placement.done", { object = order.object, tile = order.tile })
        else
          Crops.hold(world, tiles, true)
          index = index + 1
        end
      else
        if free and assign(world, hs, order, check) then
          free = false
        end
        index = index + 1
      end
    end
  end
end

function Placement.init(world)
  local state = world.state
  state.placement = state.placement or { orders = {} }
end

return Placement
