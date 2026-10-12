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
--
-- State: world.state.priorities = ordered { { category, enabled } } for the idle routine.
-- Runtime: world.taskTypes (registered each load), world.reservations.

local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")

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
      list[#list + 1] = entry
      seen[entry.category] = true
    end
  end
  for _, cat in ipairs(world.registry:all("task_categories")) do
    if not seen[cat.id] then
      list[#list + 1] = { category = cat.id, enabled = true }
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

local function reservationKey(taskId, i)
  return taskId .. ":" .. i
end

local function reservedByOther(world, actor, taskId, i)
  local holder = world.reservations[reservationKey(taskId, i)]
  return holder ~= nil and holder ~= actor.id
end

function Tasks.reserve(world, actor, job)
  world.reservations[reservationKey(job.task, job.target)] = actor.id
end

function Tasks.release(world, job)
  world.reservations[reservationKey(job.task, job.target)] = nil
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

--- The idle routine: the highest-priority category with a reachable task; within it, the
--- target nearest by walking distance (one Dijkstra search over all candidates).
function Tasks.chooseIdleJob(world, actor)
  local grid = world.state.grid
  local here = Grid.index(grid, math.floor(actor.x + 0.5), math.floor(actor.y + 0.5))
  for _, entry in ipairs(world.state.priorities) do
    if entry.enabled then
      local targets, taskAt, any = {}, {}, false
      for _, t in ipairs(world.taskTypes.list) do
        if t.category == entry.category and t.candidates then
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
    end
  end
  return nil
end

return Tasks
