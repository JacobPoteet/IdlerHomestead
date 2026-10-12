-- Routine conditions (GDD §7.4, D66): evaluate and edit the optional `cond` on a priority entry.
-- A condition is { kind = <routine_conditions id>, value = number }; no `cond` means "always".
-- Pure reads of the ledger, needs and calendar; the only writes are to the condition table itself.

local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")

local Rules = {}

--- The value a condition's measure reads right now.
local function measure(world, def)
  if def.measure == "foodDays" then
    return Needs.foodDays(world)
  elseif def.measure == "stock" then
    local total = 0
    for _, id in ipairs(def.resources) do
      total = total + Ledger.get(world, id)
    end
    return total
  elseif def.measure == "seasonIndex" then
    return Calendar.now(world).seasonIndex
  elseif def.measure == "hour" then
    return Calendar.now(world).hour
  end
  error("Unknown routine measure " .. tostring(def.measure))
end

--- Is the condition met? nil (no condition) is always met.
function Rules.met(world, cond)
  if cond == nil then
    return true
  end
  local def = world.registry:get("routine_conditions", cond.kind)
  local now = measure(world, def)
  if def.cmp == "below" then
    return now < cond.value
  elseif def.cmp == "atleast" then
    return now >= cond.value
  end
  return now == cond.value
end

--- A fresh condition of a kind, at its default value.
function Rules.make(world, kind)
  return { kind = kind, value = world.registry:get("routine_conditions", kind).default }
end

--- Short text for a condition ("food < 10 d"), or "always" for none.
function Rules.describe(world, cond)
  if cond == nil then
    return "always"
  end
  local def = world.registry:get("routine_conditions", cond.kind)
  local shown = cond.value
  if def.measure == "seasonIndex" then
    local name = world.tuning.time.seasons[cond.value]
    shown = name:sub(1, 1):upper() .. name:sub(2)
  end
  return string.format(def.short, shown)
end

--- Name of the kind a condition uses ("Food below"), or "Always" for none.
function Rules.kindName(world, cond)
  if cond == nil then
    return "Always"
  end
  return world.registry:get("routine_conditions", cond.kind).name
end

--- Next kind in content order after `cond` (nil -> first kind; the last kind -> nil).
--- Returns a new condition at its default value, or nil.
function Rules.nextKind(world, cond)
  local list = world.registry:all("routine_conditions")
  local at = 0
  if cond ~= nil then
    for i, def in ipairs(list) do
      if def.id == cond.kind then
        at = i
      end
    end
  end
  local def = list[at + 1]
  return def and Rules.make(world, def.id) or nil
end

--- Move the value one step (delta = +1 / -1), clamped to the kind's range.
function Rules.step(world, cond, delta)
  if cond == nil then
    return
  end
  local def = world.registry:get("routine_conditions", cond.kind)
  cond.value = math.max(def.min, math.min(def.max, cond.value + delta * def.step))
end

--- Make a loaded condition valid again: unknown kinds drop it, values clamp into the kind's range.
--- Returns the cleaned condition or nil.
function Rules.sanitize(world, cond)
  if type(cond) ~= "table" or not world.registry:has("routine_conditions", cond.kind) then
    return nil
  end
  local def = world.registry:get("routine_conditions", cond.kind)
  local value = tonumber(cond.value) or def.default
  return { kind = cond.kind, value = math.max(def.min, math.min(def.max, value)) }
end

return Rules
