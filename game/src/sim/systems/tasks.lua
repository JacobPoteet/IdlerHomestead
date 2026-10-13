-- Task board (GDD §7.4): the shared interface between "things that need doing" and
-- "things that do work". Systems register task types; actors pick from them.
--
-- A task type is a table:
--   id, category        category is a task_categories id (or nil for player-only tasks like "move")
--   verb                short label for UI ("Harvest", "Water")
--   clickOrder          when the player taps a tile, the lowest clickOrder task that canDo wins
--   candidates(world, actor, add)        idle routine: call add(tileIndex) for each possible target
--   canDo(world, actor, i, order)        is the task valid on tile i right now? `order` is set for
--                                        player orders ({ crop = ... }), nil for the idle routine
--   blocked(world, actor, i, order)      optional: the id of a full resource when the task would apply
--                                        to tile i but for lack of storage room, else nil. Only the
--                                        player's taps use it, to say why they were refused (#74).
--   canDoCandidate(world, actor, i)      optional: canDo(world, actor, i, nil) for a tile that
--                                        `candidates` just offered, minus the checks `candidates`
--                                        already made once for every tile (e.g. owning a rod);
--                                        the idle search uses it instead of canDo (#77)
--   workTime(world, actor, i)            seconds of work at 1x efficiency
--   complete(world, actor, i, order)     apply the result
--   standOn                              true: actor must stand on the tile (default: within 1)
--   standing                             true: the task is a standing order (D92): an actor with no job
--                                        picks it up in any control mode, before the idle priorities
--
-- Actors (GDD §7.4, D65) are anything that claims tasks: the homesteader (actors.lua) walks to a
-- target found by `chooseIdleJob` or a player order; a machine (machines.lua) stands still and
-- claims through `chooseAreaJob`, limited by its capability set { categories, tasks? } and an area
-- { center, radius }. Every claim goes through the same reservations, keyed by task and tile, so two
-- actors never work the same target: a reservation names its holder (actor.id) and only that holder
-- can release it.
--
-- State: world.state.priorities = ordered { { category, enabled, cond? } } for the idle routine.
-- `cond` ({ kind, value }, see routine_rules.lua / D66) makes the idle routine skip the category
-- while it is not met; it never affects player orders or machines.
-- Runtime: world.taskTypes (registered each load), world.reservations ("task:tile" -> actor id),
-- rebuilt on load from the jobs actors and machines hold.

local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")
local Rules = require("src.sim.routine_rules")

local Tasks = {}


function Tasks.init(world)
  world.taskTypes = { list = {}, byId = {} }
  world.reservations = {}
  Tasks.syncPriorities(world)
end

--- Keep the saved priority list in step with content: new categories are appended,
--- removed ones dropped. The player's order and toggles are preserved.
function Tasks.syncPriorities(world)
  local known = {}
  for _, cat in ipairs(world.registry:all("task_categories")) do
    known[cat.id] = true
  end
  local list, seen = {}, {}
  for _, entry in ipairs(world.state.priorities or {}) do
    if known[entry.category] and not seen[entry.category] then
      entry.cond = Rules.sanitize(world, entry.cond) -- older saves have none and keep none (D66)
      list[#list + 1] = entry
      seen[entry.category] = true
    end
  end
  for _, cat in ipairs(world.registry:all("task_categories")) do
    if not seen[cat.id] then
      list[#list + 1] = { category = cat.id, enabled = true } -- no condition by default (D66)
    end
  end
  world.state.priorities = list
end

function Tasks.register(world, taskType)
  assert(taskType.id and not world.taskTypes.byId[taskType.id], "Task type needs a unique id")
  world.taskTypes.byId[taskType.id] = taskType
  local list = world.taskTypes.list
  list[#list + 1] = taskType
  table.sort(list, function(a, b)
    return (a.clickOrder or math.huge) < (b.clickOrder or math.huge)
  end)
end

function Tasks.get(world, id)
  return assert(world.taskTypes.byId[id], "Unknown task type " .. tostring(id))
end

--- Move a category one step up (-1) or down (+1) in the idle priority list.
function Tasks.movePriority(world, category, delta)
  local list = world.state.priorities
  for i, entry in ipairs(list) do
    if entry.category == category then
      local j = i + delta
      if j >= 1 and j <= #list then
        list[i], list[j] = list[j], list[i]
      end
      return
    end
  end
end

function Tasks.setPriorityEnabled(world, category, enabled)
  for _, entry in ipairs(world.state.priorities) do
    if entry.category == category then
      entry.enabled = enabled
    end
  end
end

local function entryFor(world, category)
  for _, entry in ipairs(world.state.priorities) do
    if entry.category == category then
      return entry
    end
  end
  error("Unknown routine category " .. tostring(category))
end

--- The category's routine condition, { kind, value }, or nil for "always" (D66).
function Tasks.condition(world, category)
  return entryFor(world, category).cond
end

--- Set a category's condition to a kind at its default value; nil clears it.
function Tasks.setCondition(world, category, kind)
  entryFor(world, category).cond = kind and Rules.make(world, kind) or nil
end

--- Cycle a category's condition kind (always -> each kind in content order -> always).
function Tasks.cycleCondition(world, category)
  local entry = entryFor(world, category)
  entry.cond = Rules.nextKind(world, entry.cond)
end

--- Nudge a category's condition value one step (delta +1 / -1), clamped to the kind's range.
function Tasks.stepCondition(world, category, delta)
  Rules.step(world, entryFor(world, category).cond, delta)
end

--- Is the category's condition met right now? (Categories with none always are.)
function Tasks.conditionMet(world, category)
  return Rules.met(world, entryFor(world, category).cond)
end

local function reservationKey(taskId, i)
  return taskId .. ":" .. i
end

local function reservedByOther(world, actor, taskId, i)
  local holder = world.reservations[reservationKey(taskId, i)]
  return holder ~= nil and holder ~= actor.id
end

--- Claim a job's target for an actor. The job remembers its holder, so a later release by an actor
--- that lost the claim (a player order took the tile over) cannot free someone else's reservation.
function Tasks.reserve(world, actor, job)
  job.holder = actor.id
  world.reservations[reservationKey(job.task, job.target)] = actor.id
end

--- Give up a job's claim, if this job still holds it (jobs saved before holders existed always do).
function Tasks.release(world, job)
  local key = reservationKey(job.task, job.target)
  if job.holder == nil or world.reservations[key] == job.holder then
    world.reservations[key] = nil
  end
end

--- Id of the actor holding task `taskId` on tile i, or nil.
function Tasks.holder(world, taskId, i)
  return world.reservations[reservationKey(taskId, i)]
end

--- Does a capability set allow this task type? caps = { categories = { id... }, tasks = { id... }? }:
--- the task's category must be listed, and when `tasks` is given its id must be listed too. A nil
--- capability set (the homesteader) allows everything.
function Tasks.allows(caps, taskType)
  if caps == nil then
    return true
  end
  if not taskType.category then
    return false
  end
  local ok = false
  for _, c in ipairs(caps.categories) do
    if c == taskType.category then
      ok = true
    end
  end
  if ok and caps.tasks then
    ok = false
    for _, id in ipairs(caps.tasks) do
      if id == taskType.id then
        ok = true
      end
    end
  end
  return ok
end

local function pathFor(world, actor, taskType, target)
  local grid = world.state.grid
  local here = Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5))
  if taskType.standOn then
    return Pathfind.find(world, here, function(i)
      return i == target
    end, target)
  end
  return Pathfind.toWorkSpot(world, here, target)
end

local function newJob(taskType, target, path, order)
  return { task = taskType.id, target = target, path = path, progress = 0, ordered = order ~= nil, order = order }
end

--- The task the player means by tapping tile i, or nil.
--- A task type that would apply to the tile but for a full store stops the search: the tap is
--- refused (nil) and the second return is the id of the resource that is full (#74), rather than
--- quietly falling through to some lesser task.
function Tasks.taskForTile(world, actor, i, order)
  for _, t in ipairs(world.taskTypes.list) do
    if t.clickOrder then
      local full = t.blocked and t.blocked(world, actor, i, order)
      if full then
        return nil, full
      end
      if t.canDo(world, actor, i, order) then
        return t
      end
    end
  end
  return nil
end

--- Build a job for a player order on tile i. Returns the job, or nil if nothing applies or
--- the tile can't be reached; when a full store refused the order, also the full resource's id.
function Tasks.jobForOrder(world, actor, i, order)
  order = order or {}
  local taskType, full = Tasks.taskForTile(world, actor, i, order)
  if not taskType then
    return nil, full
  end
  local path = pathFor(world, actor, taskType, i)
  if not path then
    return nil
  end
  return newJob(taskType, i, path, order)
end

--- A job for a specific task type and target (no player order), or nil if unreachable.
function Tasks.jobFor(world, actor, taskId, target)
  local taskType = Tasks.get(world, taskId)
  local path = pathFor(world, actor, taskType, target)
  if not path then
    return nil
  end
  return newJob(taskType, target, path, nil)
end

-- One search over every task type `wanted` accepts: the doable, unreserved candidate nearest by walking
-- distance becomes a job (one Dijkstra search over all candidates), or nil.
local function nearestJob(world, actor, wanted)
  local grid = world.state.grid
  local here = Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5))
  local targets, taskAt, any = {}, {}, false
  for _, t in ipairs(world.taskTypes.list) do
    if wanted(t) and t.candidates and Tasks.allows(actor.caps, t) then
      local canDoCandidate = t.canDoCandidate
      local canDo = t.canDo
      t.candidates(world, actor, function(i)
        if taskAt[i] or reservedByOther(world, actor, t.id, i) then
          return
        end
        local ok
        if canDoCandidate then
          ok = canDoCandidate(world, actor, i)
        else
          ok = canDo(world, actor, i, nil)
        end
        if ok then
          targets[i] = t.standOn == true
          taskAt[i] = t
          any = true
        end
      end)
    end
  end
  if any then
    local path, target = Pathfind.nearest(world, here, targets)
    if path then
      return newJob(taskAt[target], target, path, nil)
    end
  end
  return nil
end

--- The idle routine: the highest-priority category with a reachable task; within it, the
--- target nearest by walking distance (one Dijkstra search over all candidates).
function Tasks.chooseIdleJob(world, actor)
  for _, entry in ipairs(world.state.priorities) do
    if entry.enabled and Rules.met(world, entry.cond) then
      local job = nearestJob(world, actor, function(t)
        return t.category == entry.category
      end)
      if job then
        return job
      end
    end
  end
  return nil
end

--- Standing orders (D92): task types flagged `standing` (tilling and planting of planned tiles) are
--- the player's own instruction, so they run whatever the control mode, ahead of the routine's
--- priority list and ignoring its conditions (D66). A category the player switched off in the Routine
--- panel stays off, so a standing order never works against that toggle. Nearest target first.
function Tasks.chooseStandingJob(world, actor)
  return nearestJob(world, actor, function(t)
    return t.standing == true and entryFor(world, t.category).enabled
  end)
end

--- A stationary actor's search (machines, D65): within its capability set and area, the first
--- category in `caps.categories` order with a doable, unclaimed target; within it the target nearest
--- the area's centre (Chebyshev), ties by tile index, so the choice never depends on table order.
--- No path: a machine reaches its area without walking.
--- area = { center = tile index, radius = tiles }.
--- Returns job, nil when one is found; otherwise nil, full where `full` is the id of a resource whose
--- full store is holding back a target in the area (D59), or nil when there is simply nothing to do.
function Tasks.chooseAreaJob(world, actor, caps, area)
  local grid = world.state.grid
  local full, fullKey -- the nearest held-back target decides which full store is reported
  local function closer(dist, i, otherDist, other)
    return otherDist == nil or dist < otherDist or (dist == otherDist and i < other)
  end
  for _, category in ipairs(caps.categories) do
    local best, bestDist, bestType
    for _, t in ipairs(world.taskTypes.list) do
      if t.category == category and t.candidates and Tasks.allows(caps, t) then
        t.candidates(world, actor, function(i)
          local dist = Grid.distance(grid, area.center, i)
          if dist > area.radius or reservedByOther(world, actor, t.id, i) or not closer(dist, i, bestDist, best) then
            return
          end
          if t.canDo(world, actor, i, nil) then
            best, bestDist, bestType = i, dist, t
          elseif t.blocked and closer(dist, i, fullKey and fullKey[1], fullKey and fullKey[2]) then
            local res = t.blocked(world, actor, i, nil)
            if res then
              full, fullKey = res, { dist, i }
            end
          end
        end)
      end
    end
    if best then
      return newJob(bestType, best, {}, nil), nil
    end
  end
  return nil, full
end

return Tasks
