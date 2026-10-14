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
-- Pick up and move (D98, #15) live here too: `Placement.pickUp` returns a placed object to the inventory and
-- `Placement.requestMove` relocates one, through the same orders when the new spot needs clearing.
--
-- State: world.state.placement = { orders = { { object = objectId, tile = anchorIndex, from? = anchor of the
--   placed object being moved there, why? } ... } }
--   why: nil, or { kind = "full", resource = id } (a store has no room for the clearing),
--        { kind = "unreachable" } or { kind = "blocked" } (no spot to stand or step aside to).
-- Emits "placement.queued" { object, tile }, "placement.held" { object, tile, kind, resource? },
-- "placement.cancelled" { object, tile, reason }, "placement.done" { object, tile }.

local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Processing = require("src.sim.systems.processing")
local Shelter = require("src.sim.systems.shelter")
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
    if order.object == id and not order.from then -- a move carries its own object, not one from the inventory
      n = n - 1
    end
  end
  return n
end

--- What the order would do: the Inventory.check result plus `available` (an item is free to use) and, when
--- another queued order already covers part of the footprint, ok = false with reason "claimed".
--- `queue` is true when the spot is legal but needs clearing or removing first.
--- `from`: the anchor of a placed object being moved (D98); its own footprint counts as free and it needs no
--- item in the inventory. Moving it onto its own anchor is refused (reason "here").
function Placement.preview(world, id, i, from)
  local result = Inventory.check(world, id, i, nil, from)
  result.available = from ~= nil or Placement.available(world, id) > 0
  if from and result.ok and i == from then
    result.ok, result.immediate, result.reason = false, false, "here"
  end
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

-- Pick up and move (D98, #15) -----------------------------------------------------------------------------

local function placedDef(world, anchor)
  local obj = world.state.grid.objects[anchor]
  return obj and world.registry:get("objects", obj.id), obj
end

-- Does the homesteader sleep in (or walk to) this shelter? Sleep goes to the best shelter (D82).
local function sleepsIn(world, anchor, def)
  local hs = Actors.homesteader(world)
  return def.shelter == true and Sleep.resting(hs) and Shelter.best(world) == anchor
end

--- Rules shared by pick up and move: { ok = true } or { ok = false, reason }, where reason is "none" (nothing
--- there), "fixed" (not a player-placed object: the truck) or "asleep" (the homesteader is in this bed).
function Placement.moveCheck(world, anchor)
  local def = placedDef(world, anchor)
  if not def then
    return { ok = false, reason = "none" }
  end
  if not def.placeable then
    return { ok = false, reason = "fixed" }
  end
  if sleepsIn(world, anchor, def) then
    return { ok = false, reason = "asleep" }
  end
  return { ok = true }
end

--- Can the object at `anchor` go back to the inventory? Returns { ok = true, warn? } or { ok = false, reason,
--- resource?, name? }: the shared reasons of `moveCheck`, "batch" (a station is working: its inputs are
--- already in the pot) or "storage" (what the object stores would no longer fit: `resource`, with `animal` set
--- when the resource is livestock housed here). `warn` is what the pick-up would throw away, for a confirmation:
--- { kind = "charge", kwh } (a battery), { kind = "output", resource, count } (a finished batch waiting for room).
function Placement.pickUpCheck(world, anchor)
  local shared = Placement.moveCheck(world, anchor)
  if not shared.ok then
    return shared
  end
  local def = placedDef(world, anchor)
  local result = { ok = true }
  if def.station then
    local batch = Processing.batch(world, anchor)
    if batch and not batch.blocked then
      return { ok = false, reason = "batch" }
    elseif batch then
      result.warn = { kind = "output", resource = world.registry:get("recipes", batch.recipe).output, count = batch.count }
    end
  end
  local res = {}
  for id in pairs(def.storage or {}) do
    res[#res + 1] = id
  end
  table.sort(res)
  for _, id in ipairs(res) do
    if Ledger.get(world, id) > Ledger.capacity(world, id) - def.storage[id] then
      local kind = world.registry:get("resources", id)
      return { ok = false, reason = "storage", resource = id, animal = kind.category == "animal" }
    end
  end
  if def.battery and not def.vehicle then
    local kwh = Power.charge(world, anchor)
    if kwh >= world.tuning.power.pickupChargeWarn then
      result.warn = { kind = "charge", kwh = kwh }
    end
  end
  return result
end

-- Orders that move the object at `anchor`.
local function dropMoves(world, anchor, reason)
  local list = orders(world)
  for index = #list, 1, -1 do
    if list[index].from == anchor then
      local order = table.remove(list, index)
      Crops.hold(world, footprint(world, order), false)
      if reason then
        world.events:emit("placement.cancelled", { object = order.object, tile = order.tile, reason = reason })
      end
    end
  end
end

-- Let go of any job the homesteader holds or has been ordered to on the object's tiles.
local function dropJobsOn(world, tiles)
  local on = {}
  for _, t in ipairs(tiles) do
    on[t] = true
  end
  for _, actor in ipairs(Actors.list(world)) do
    if actor.job and on[actor.job.target] and actor.job.task ~= "move" then
      Tasks.release(world, actor.job)
      actor.job = nil
    end
    if actor.order and on[actor.order.target] and actor.order.task ~= "move" then
      actor.order = nil
    end
  end
end

-- Tilled soil under an object goes back to farming as it was (Crops.restoreTilled).
local function giveBackSoil(world, obj)
  local tiles = {}
  for t in pairs(obj.tilled or {}) do
    tiles[#tiles + 1] = t
  end
  table.sort(tiles)
  for _, t in ipairs(tiles) do
    Crops.restoreTilled(world, t)
  end
end

-- Take the object off the ground (the caller has checked the rules): soil back, jobs on it dropped.
-- Returns the saved object record.
local function lift(world, anchor)
  local def, obj = placedDef(world, anchor)
  local x, y = Grid.coords(world.state.grid, anchor)
  dropJobsOn(world, Grid.footprintTiles(world.state.grid, def, x, y))
  giveBackSoil(world, obj)
  Grid.removeObject(world, anchor)
  return obj
end

--- Put the object at `anchor` back in the inventory (instant: placing on clear ground is too). Returns true, or
--- nil plus the `pickUpCheck` result when refused. A finished batch waiting in a station is discarded (the UI
--- asks first); a battery's charge is lost; tilled soil it covered is tilled again, everything else is grass.
--- Emits "object.pickedup" { object, tile } (and "processing.discarded" for a waiting batch).
function Placement.pickUp(world, anchor)
  local check = Placement.pickUpCheck(world, anchor)
  if not check.ok then
    return nil, check
  end
  local id = world.state.grid.objects[anchor].id
  dropMoves(world, anchor, "pickedup")
  if check.warn and check.warn.kind == "output" then
    Processing.discard(world, anchor)
  end
  lift(world, anchor)
  Power.forget(world, anchor)
  Inventory.addObject(world, id)
  Inventory.refreshStorage(world)
  Power.refresh(world) -- the network is whatever is left
  world.events:emit("object.pickedup", { object = id, tile = anchor })
  return true
end

--- What destroying the object at `anchor` would throw away (D110, #255): { ok = true, lose } or { ok = false,
--- reason } with the `moveCheck` reasons (the truck, the bed the homesteader sleeps in). `lose` holds only what
--- is lost: `batch` { recipe, count, blocked } (a station's batch, running or waiting), `charge` kWh (a battery),
--- `goods` a list of { resource, count, animal } the ledger could no longer hold once this storage is gone.
--- Nothing is refunded; Pick up (D98) is the way to keep the object.
function Placement.destroyCheck(world, anchor)
  local shared = Placement.moveCheck(world, anchor)
  if not shared.ok then
    return shared
  end
  local def = placedDef(world, anchor)
  local lose = {}
  local batch = def.station and Processing.batch(world, anchor)
  if batch then
    lose.batch = { recipe = batch.recipe, count = batch.count, blocked = batch.blocked == true }
  end
  local ids = {}
  for id in pairs(def.storage or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local over = Ledger.get(world, id) - (Ledger.capacity(world, id) - def.storage[id])
    if over > 0 then
      lose.goods = lose.goods or {}
      lose.goods[#lose.goods + 1] = { resource = id, count = over, animal = world.registry:get("resources", id).category == "animal" }
    end
  end
  if def.battery and not def.vehicle then
    local kwh = Power.charge(world, anchor)
    if kwh >= world.tuning.power.pickupChargeWarn then
      lose.charge = kwh
    end
  end
  return { ok = true, lose = lose }
end

--- Destroy the object at `anchor` for good: no refund, soil back as it was, a station's batch and a battery's
--- charge gone, and whatever the ledger can no longer hold without this storage lost (the amounts `destroyCheck`
--- reported). Returns true, or nil plus the check result when refused. Emits "object.destroyed" { object, tile,
--- lost = { [resource] = count } }.
function Placement.destroy(world, anchor)
  local check = Placement.destroyCheck(world, anchor)
  if not check.ok then
    return nil, check
  end
  local id = world.state.grid.objects[anchor].id
  dropMoves(world, anchor, "pickedup")
  Processing.scrap(world, anchor)
  lift(world, anchor)
  Power.forget(world, anchor)
  Inventory.refreshStorage(world)
  Power.refresh(world)
  local lost = {}
  for _, g in ipairs(check.lose.goods or {}) do
    local over = Ledger.get(world, g.resource) - Ledger.capacity(world, g.resource)
    if over > 0 then
      Ledger.remove(world, g.resource, over, "destroy")
      lost[g.resource] = over
    end
  end
  world.events:emit("object.destroyed", { object = id, tile = anchor, lost = lost })
  return true
end

-- Set the object at `from` down at `to` in one step (the footprint there is clear). Keeps its state: the
-- battery's charge and switch, a station's batch, the record's other fields; a machine starts a fresh unit.
local function relocate(world, from, to)
  local grid = world.state.grid
  local id = grid.objects[from].id
  local def = world.registry:get("objects", id)
  local fx, fy = Grid.coords(grid, from)
  local oldTiles = Grid.footprintTiles(grid, def, fx, fy)
  local obj = lift(world, from)
  if not Inventory.canPlace(world, id, to) then
    -- (A tile the object left is open ground, so this fails only when the new spot is not clear after all.)
    Grid.placeObject(world, id, fx, fy)
    local was
    for _, t in ipairs(oldTiles) do
      if Crops.cover(world, t, "placement") then
        was = was or {}
        was[t] = true
      end
    end
    grid.objects[from] = obj
    obj.tilled = was
    return false
  end
  local tx, ty = Grid.coords(grid, to)
  local newTiles = Grid.footprintTiles(grid, def, tx, ty)
  Grid.placeObject(world, id, tx, ty)
  local was
  for _, t in ipairs(newTiles) do
    if Crops.cover(world, t, "placement") then
      was = was or {}
      was[t] = true
    end
  end
  for key, value in pairs(obj) do
    if key ~= "tilled" then
      grid.objects[to][key] = value
    end
  end
  grid.objects[to].tilled = was
  Power.relocate(world, from, to)
  Processing.relocate(world, from, to)
  Inventory.refreshStorage(world)
  Power.refresh(world)
  world.events:emit("object.moved", { object = id, from = from, tile = to })
  return true
end

--- Start moving the object at `anchor` to tile `i` (its top-left): the spot is checked like any placement
--- (`Placement.preview(world, id, i, anchor)`), the object goes at once when the way is clear and otherwise a
--- move order is queued behind the clearing (crops and plans go last, D86). Until the move happens the object
--- stays where it is and keeps working; cancelling the order leaves it there. Returns "placed", "queued", or
--- nil plus the reason it was refused (the `moveCheck` reasons, or an `Inventory.check` reason and rule).
function Placement.requestMove(world, anchor, i)
  local shared = Placement.moveCheck(world, anchor)
  if not shared.ok then
    return nil, shared.reason
  end
  local id = world.state.grid.objects[anchor].id
  local result = Placement.preview(world, id, i, anchor)
  if not result.ok then
    return nil, result.reason, result.rule
  end
  dropMoves(world, anchor, "replaced") -- one move at a time per object
  if result.immediate then
    if relocate(world, anchor, i) then
      return "placed"
    end
    return nil, "blocked"
  end
  Crops.hold(world, result.tiles, true)
  orders(world)[#orders(world) + 1] = { object = id, tile = i, from = anchor }
  world.events:emit("placement.queued", { object = id, tile = i, from = anchor })
  return "queued"
end

--- The move order for the object at `anchor`, or nil.
function Placement.moveFrom(world, anchor)
  for _, order in ipairs(orders(world)) do
    if order.from == anchor then
      return order
    end
  end
  return nil
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
    local tiles = footprint(world, order)
    local from = order.from
    local check = Inventory.check(world, order.object, order.tile, true, from)
    local gone
    if from then
      local placed = world.state.grid.objects[from]
      gone = not placed or placed.id ~= order.object -- the object being moved is no longer there
    else
      used[order.object] = (used[order.object] or 0) + 1
      gone = used[order.object] > Inventory.objectCount(world, order.object)
    end
    if gone then
      drop(world, index, "item")
    elseif not check.ok then
      drop(world, index, check.reason) -- something that can't be cleared now stands there
    else
      if #check.clear == 0 and not check.actor and (#check.crops > 0 or check.plans > 0) then
        -- Everything else is clear and nobody stands in the way: the crops and plans go now, the last step
        -- before the building, in the tick it goes up (D86). Waiting for the homesteader to step aside
        -- first means a cancel in that window still loses nothing (#227). Tilled soil stays until it is down.
        for _, t in ipairs(tiles) do
          Crops.cover(world, t, "placement", true)
        end
        check = Inventory.check(world, order.object, order.tile, true, from)
      end
      if check.immediate then
        Crops.hold(world, tiles, false) -- Inventory.place reads a held tile as another order's
        local done
        if from then
          done = relocate(world, from, order.tile)
        else
          done = Inventory.place(world, order.object, order.tile)
        end
        if done then
          table.remove(list, index)
          world.events:emit("placement.done", { object = order.object, tile = order.tile, from = from })
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
