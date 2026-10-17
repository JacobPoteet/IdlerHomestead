-- Statuses (D166, #345, docs/PLAN_DEPTH.md §7): short lists of modifiers on the homesteader. A status is content
-- (data/content/statuses.lua); this system holds which are active and combines their modifiers. Events (the body pack)
-- call Status.apply; items call Status.clearBy in a later slice.
--
-- Rules:
--   * Families escalate, they never stack. Applying a status of a family that is already active raises the active
--     one to its next severity (its `escalatesTo`; at the cap its time is renewed), but only when the applied status
--     itself carries an `escalatesTo` (it is a stage of a chain: a second event of the same illness). One that does
--     not (a one-off such as the chill, an ignore outcome) never escalates the active status, it only renews its time
--     (D175). A worse applied status than the active one is taken as it is.
--   * Different families coexist up to tuning.status.maxActiveStatuses. Past it a new family does not stack: it
--     replaces the active status with the least time left only if it will last longer, and is dropped otherwise.
--   * Modifiers are multipliers (1 = no effect) and multiply across the active statuses; `conditionDrain` is a
--     flat Condition loss a day and adds up. The combined `workSpeed` never goes under tuning.status.minWorkSpeed.
--   * A status with a duration counts it down at each new day, after the night's draw (Needs.daily), so a duration
--     of 1 is gone tomorrow morning; one with none lasts until Status.clear or Status.clearBy ends it.
--
-- Hooks (the systems that read the modifiers): Stats.factor("workSpeed") in the actor's work rate, "carryCapacity" in
-- Water.bucketCapacity, "fallChance" in Actors.fallFactor, "warmthNeed" in Needs.warmthNeeded (tonight's need; the
-- season-long readiness forecast ignores a passing status), "waterNeed" in Needs.waterNeeded, "studySpeed" in the journal's study rate, and "conditionRecovery" and
-- "conditionDrain" in Needs.daily.
--
-- State: world.state.status = { active = { { id, left? } }, history? } in the order applied; `left` is the days
-- remaining (absent = until cleared). `history` (D167) is { { id, count } }: every status that took hold this run, in the
-- order first seen, for the recovery scene's "hurt this run" line; it appears with the first status, so a run that
-- was never hurt saves no more than before.
-- Emits "status.applied" { id, family, severity, kind ("new" | "escalated" | "renewed"), from? (the id it rose from) }
-- and "status.cleared" { id, family, severity, reason ("expired" | "rest" | "item" | "replaced" | <the caller's>) }.

local Status = {}

-- Modifier names, and how a status's value combines across the active ones.
local SUMMED = { conditionDrain = true } -- everything else multiplies
local NAMES = {
  workSpeed = true,
  fallChance = true,
  carryCapacity = true,
  conditionRecovery = true,
  conditionDrain = true,
  studySpeed = true,
  warmthNeed = true,
  waterNeed = true,
}

--- Is `name` a modifier a status can carry?
function Status.isModifier(name)
  return NAMES[name] == true
end

local function state(world)
  return world.state.status
end

local function def(world, id)
  return world.registry:get("statuses", id)
end

local function cfg(world)
  return world.tuning.status
end

local function view(world, entry)
  local d = def(world, entry.id)
  return {
    id = d.id,
    name = d.name,
    line = d.line,
    family = d.family,
    severity = d.severity,
    clearedBy = d.clearedBy,
    left = entry.left, -- days remaining; nil = until cleared
    modifiers = d.modifiers,
  }
end

--- The active statuses in the order applied, as read-only views:
--- { { id, name, line, family, severity, clearedBy, left (days; nil = until cleared), modifiers } }.
function Status.active(world)
  local out = {}
  for i, entry in ipairs(state(world).active) do
    out[i] = view(world, entry)
  end
  return out
end

--- What took hold this run, as { { id, count } } in the order first seen (a plain copy). Empty when nothing did.
--- Reads a world whose run has no status state as empty, so a summary of any run can ask.
function Status.history(world)
  local st = world.state.status
  local out = {}
  for i, h in ipairs(st and st.history or {}) do
    out[i] = { id = h.id, count = h.count }
  end
  return out
end

--- How many statuses are active.
function Status.count(world)
  return #state(world).active
end

--- The most statuses at once.
function Status.maxActive(world)
  return cfg(world).maxActiveStatuses
end

--- The active status with this id, as a view, or nil.
function Status.get(world, id)
  for _, entry in ipairs(state(world).active) do
    if entry.id == id then
      return view(world, entry)
    end
  end
  return nil
end

--- Is the status with this id active?
function Status.has(world, id)
  return Status.get(world, id) ~= nil
end

--- The active status of a family, as a view, or nil.
function Status.inFamily(world, family)
  for _, entry in ipairs(state(world).active) do
    if def(world, entry.id).family == family then
      return view(world, entry)
    end
  end
  return nil
end

local function indexOfFamily(world, family)
  for i, entry in ipairs(state(world).active) do
    if def(world, entry.id).family == family then
      return i
    end
  end
  return nil
end

-- Days an entry has left, with "until cleared" as the longest.
local function remaining(entry)
  return entry.left or math.huge
end

local function emitCleared(world, entry, reason)
  local d = def(world, entry.id)
  world.events:emit("status.cleared", { id = d.id, family = d.family, severity = d.severity, reason = reason })
end

-- Note that the status `id` took hold (new, escalated to or renewed): the run's list of what hurt the homesteader.
local function record(world, id)
  local st = state(world)
  st.history = st.history or {}
  for _, h in ipairs(st.history) do
    if h.id == id then
      h.count = h.count + 1
      return
    end
  end
  st.history[#st.history + 1] = { id = id, count = 1 }
end

local function emitApplied(world, id, kind, from)
  local d = def(world, id)
  record(world, id)
  world.events:emit("status.applied", { id = d.id, family = d.family, severity = d.severity, kind = kind, from = from })
end

--- Which status of a family results when `appliedId` lands on the active `currentId`: the id of the one that holds.
--- Pure (reads definitions only); Events.audit uses it to prove an ignore outcome never escalates or worsens anything.
function Status.resolve(world, currentId, appliedId)
  local current, d = def(world, currentId), def(world, appliedId)
  if d.severity <= current.severity then
    -- A second event of the illness (the applied status is a stage of the chain): one step up, or the cap. A one-off
    -- status without `escalatesTo` leaves the active one as it is.
    if d.escalatesTo and current.escalatesTo then
      return current.escalatesTo
    end
    return current.id
  end
  return d.id
end

--- Apply the status `id`. Returns what happened: "new" (it joined), "escalated" (its family rose a severity or took a
--- worse one), "renewed" (at the cap of its family; the time is renewed) or "dropped" (the list is full of statuses
--- that last longer, so nothing changed), then the view of the status now active (nil when dropped).
function Status.apply(world, id)
  local d = def(world, id)
  local st = state(world)
  local slot = indexOfFamily(world, d.family)
  if slot then
    local entry = st.active[slot]
    local current = def(world, entry.id)
    local target = def(world, Status.resolve(world, entry.id, id))
    local kind = target.id == current.id and "renewed" or "escalated"
    local left = target.duration
    if kind == "renewed" and left and entry.left then
      left = math.max(left, entry.left)
    end
    local from = entry.id
    entry.id, entry.left = target.id, left
    emitApplied(world, target.id, kind, kind == "escalated" and from or nil)
    return kind, view(world, entry)
  end
  if #st.active >= cfg(world).maxActiveStatuses then
    -- Full: the new status replaces the one with the least time left, only if it lasts longer; ties (two
    -- until-cleared statuses too) keep the old.
    local worst
    for i, entry in ipairs(st.active) do
      if worst == nil or remaining(entry) < remaining(st.active[worst]) then
        worst = i
      end
    end
    if (d.duration or math.huge) <= remaining(st.active[worst]) then
      return "dropped", nil
    end
    local gone = table.remove(st.active, worst)
    emitCleared(world, gone, "replaced")
  end
  local entry = { id = id, left = d.duration }
  st.active[#st.active + 1] = entry
  emitApplied(world, id, "new")
  return "new", view(world, entry)
end

--- End the active status with this id (reason defaults to "cleared"). Returns whether there was one.
function Status.clear(world, id, reason)
  local list = state(world).active
  for i, entry in ipairs(list) do
    if entry.id == id then
      table.remove(list, i)
      emitCleared(world, entry, reason or "cleared")
      return true
    end
  end
  return false
end

--- End the active status of a family. Returns whether there was one.
function Status.clearFamily(world, family, reason)
  local slot = indexOfFamily(world, family)
  if not slot then
    return false
  end
  return Status.clear(world, state(world).active[slot].id, reason)
end

--- End every active status that `how` ("rest" or "item") cures, in the order applied. Returns how many ended. Rest and
--- the first-aid items call this (a status with a duration also ends when it runs out).
function Status.clearBy(world, how)
  local ended = 0
  local list = state(world).active
  local i = 1
  while i <= #list do
    local entry = list[i]
    if def(world, entry.id).clearedBy == how then
      table.remove(list, i)
      emitCleared(world, entry, how)
      ended = ended + 1
    else
      i = i + 1
    end
  end
  return ended
end

--- The combined value of a modifier across the active statuses. A multiplier (1 = none, the product), except
--- `conditionDrain` (0 = none, the sum). `workSpeed` is floored at tuning.status.minWorkSpeed.
function Status.modifier(world, name)
  assert(NAMES[name], "unknown status modifier '" .. tostring(name) .. "'")
  local summed = SUMMED[name]
  local total = summed and 0 or 1
  for _, entry in ipairs(state(world).active) do
    local value = def(world, entry.id).modifiers[name]
    if value then
      total = summed and total + value or total * value
    end
  end
  if name == "workSpeed" then
    total = math.max(total, cfg(world).minWorkSpeed)
  end
  return total
end

-- A day passes: the night's draw is done, so count the durations down and end the ones that ran out.
local function newDay(world)
  local list = state(world).active
  local i = 1
  while i <= #list do
    local entry = list[i]
    if entry.left then
      entry.left = entry.left - 1
    end
    if entry.left and entry.left <= 0 then
      table.remove(list, i)
      emitCleared(world, entry, "expired")
    else
      i = i + 1
    end
  end
end

function Status.init(world)
  local st = world.state.status
  if not st then
    st = { active = {} }
    world.state.status = st
  end
  -- A loaded save may name a status the content no longer has: drop it rather than fail.
  for i = #st.active, 1, -1 do
    if not world.registry:has("statuses", st.active[i].id) then
      table.remove(st.active, i)
    end
  end
  world.events:on("calendar.newDay", function()
    newDay(world)
  end)
end

return Status
