-- Power (GDD §7.5), M2 slice: solar sources charge batteries (at first, only the truck).
-- Sources: objects with `powerOutput` (peak kW in full sun). Batteries: objects with `battery` (kWh).
-- Energy fills batteries in placement order. The full network (sinks, priorities, battery banks,
-- wind) arrives in M5.
--
-- State: world.state.power = { charge = { [anchor] = kWh } }

local Calendar = require("src.sim.systems.calendar")

local Power = {}

function Power.init(world)
  world.state.power = world.state.power or { charge = {} }
end

--- Solar intensity 0..1 for the current hour (sine arc between the season's sunrise and sunset).
function Power.sun(world)
  local sunrise, sunset = Calendar.daylight(world)
  local hour = Calendar.now(world).hour
  if hour <= sunrise or hour >= sunset then
    return 0
  end
  return math.sin(math.pi * (hour - sunrise) / (sunset - sunrise))
end

local function sortedAnchors(world, field)
  local list = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if world.registry:get("objects", obj.id)[field] then
      list[#list + 1] = anchor
    end
  end
  table.sort(list)
  return list
end

--- Peak solar capacity in kW (all panels in full sun).
function Power.peak(world)
  local total = 0
  for _, anchor in ipairs(sortedAnchors(world, "powerOutput")) do
    total = total + world.registry:get("objects", world.state.grid.objects[anchor].id).powerOutput
  end
  return total
end

--- Current solar output in kW.
function Power.output(world)
  return Power.peak(world) * Power.sun(world)
end

function Power.charge(world, anchor)
  return world.state.power.charge[anchor] or 0
end

function Power.capacity(world, anchor)
  local obj = world.state.grid.objects[anchor]
  return obj and world.registry:get("objects", obj.id).battery or 0
end

--- Remove `amount` kWh from a battery. Returns true if it had enough.
function Power.drain(world, anchor, amount)
  local charge = Power.charge(world, anchor)
  if charge < amount then
    return false
  end
  world.state.power.charge[anchor] = charge - amount
  return true
end

function Power.tick(world, dt)
  local energy = Power.output(world) * dt / Calendar.hourLength(world)
  if energy <= 0 then
    return
  end
  for _, anchor in ipairs(sortedAnchors(world, "battery")) do
    local room = Power.capacity(world, anchor) - Power.charge(world, anchor)
    local add = math.min(room, energy)
    if add > 0 then
      world.state.power.charge[anchor] = Power.charge(world, anchor) + add
      energy = energy - add
    end
    if energy <= 0 then
      break
    end
  end
end

return Power
