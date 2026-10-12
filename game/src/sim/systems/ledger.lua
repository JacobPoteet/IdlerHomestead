-- Resource ledger (GDD §7.2): the single store of every typed resource in a run.
-- A shared interface: any system may read or change amounts through these functions.
--
-- Emits "ledger.changed" { id, delta, total, reason } whenever an amount changes.
-- Capacity defaults to the resource definition's `capacity` (unlimited if absent);
-- storage systems can override it per resource with setCapacity.
--
-- Ledger.add silently caps at capacity and reports how much fit. Callers that already took
-- something from the player (money, inputs) must not lose the rest: check Ledger.room /
-- Ledger.canHold first and hold the goods back, or use Ledger.addOrOverflow, which announces
-- "ledger.overflow" { id, lost, reason } when goods had to be discarded.

local Ledger = {}

function Ledger.init(world)
  local state = world.state
  state.ledger = state.ledger or { amounts = {}, capacity = {} }
end

local function def(world, id)
  return world.registry:get("resources", id)
end

function Ledger.get(world, id)
  def(world, id)
  return world.state.ledger.amounts[id] or 0
end

function Ledger.capacity(world, id)
  local override = world.state.ledger.capacity[id]
  if override then
    return override
  end
  return def(world, id).capacity or math.huge
end

--- Set (or clear with nil) a capacity override, e.g. from storage buildings.
function Ledger.setCapacity(world, id, amount)
  def(world, id)
  world.state.ledger.capacity[id] = amount
end

local function change(world, id, delta, reason)
  local amounts = world.state.ledger.amounts
  local total = (amounts[id] or 0) + delta
  amounts[id] = total ~= 0 and total or nil
  world.events:emit("ledger.changed", { id = id, delta = delta, total = total, reason = reason })
end

--- Add up to `amount`, limited by capacity. Returns the amount actually added.
function Ledger.add(world, id, amount, reason)
  assert(amount >= 0, "Ledger.add amount must be non-negative")
  local room = Ledger.capacity(world, id) - Ledger.get(world, id)
  local added = math.max(0, math.min(amount, room))
  if added > 0 then
    change(world, id, added, reason)
  end
  return added
end

--- Units of a resource that still fit before hitting capacity.
function Ledger.room(world, id)
  return math.max(0, Ledger.capacity(world, id) - Ledger.get(world, id))
end

--- items: { [resourceId] = amount }. True if every amount fits at once.
function Ledger.canHold(world, items)
  for id, amount in pairs(items) do
    if Ledger.room(world, id) < amount then
      return false
    end
  end
  return true
end

--- Add as much as fits and report the rest as discarded: emits "ledger.overflow" { id, lost, reason }.
--- Returns the amount added and the amount lost.
function Ledger.addOrOverflow(world, id, amount, reason)
  local added = Ledger.add(world, id, amount, reason)
  local lost = amount - added
  if lost > 0 then
    world.events:emit("ledger.overflow", { id = id, lost = lost, reason = reason })
  end
  return added, lost
end

--- Remove exactly `amount` if available. Returns true on success, false (and no change) otherwise.
function Ledger.remove(world, id, amount, reason)
  assert(amount >= 0, "Ledger.remove amount must be non-negative")
  if Ledger.get(world, id) < amount then
    return false
  end
  if amount > 0 then
    change(world, id, -amount, reason)
  end
  return true
end

--- costs: { [resourceId] = amount }. True if every cost can be paid.
function Ledger.canAfford(world, costs)
  for id, amount in pairs(costs) do
    if Ledger.get(world, id) < amount then
      return false
    end
  end
  return true
end

--- Pay all costs atomically. Returns false (and changes nothing) if any can't be paid.
function Ledger.spend(world, costs, reason)
  if not Ledger.canAfford(world, costs) then
    return false
  end
  for id, amount in pairs(costs) do
    Ledger.remove(world, id, amount, reason)
  end
  return true
end

return Ledger
