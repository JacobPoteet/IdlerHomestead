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
--   workTime(world, actor, i)            seconds of work at 1x efficiency
--   complete(world, actor, i, order)     apply the result
--   standOn                              true: actor must stand on the tile (default: within 1)
--
-- State: world.state.priorities = ordered { { category, enabled } } for the idle routine.
-- Runtime: world.taskTypes (registered each load), world.reservations.

local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")

local Tasks = {}

-- How many of the nearest candidates to try pathing to before giving up on a category.
local PATH_ATTEMPTS = 6

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
function Tasks.taskForTile(world, actor, i, order)
  for _, t in ipairs(world.taskTypes.list) do
    if t.clickOrder and t.canDo(world, actor, i, order) then
      return t
    end
  end
  return nil
end

--- Build a job for a player order on tile i. Returns the job, or nil if nothing applies or
--- the tile can't be reached.
function Tasks.jobForOrder(world, actor, i, order)
  order = order or {}
  local taskType = Tasks.taskForTile(world, actor, i, order)
  if not taskType then
    return nil
  end
  local path = pathFor(world, actor, taskType, i)
  if not path then
    return nil
  end
  return newJob(taskType, i, path, order)
end

--- The idle routine: highest-priority category with a reachable task, nearest first.
function Tasks.chooseIdleJob(world, actor)
  local grid = world.state.grid
  local ax, ay = actor.x, actor.y
  for _, entry in ipairs(world.state.priorities) do
    if entry.enabled then
      local candidates = {}
      for _, t in ipairs(world.taskTypes.list) do
        if t.category == entry.category and t.candidates then
          t.candidates(world, actor, function(i)
            if not reservedByOther(world, actor, t.id, i) and t.canDo(world, actor, i, nil) then
              local x, y = Grid.coords(grid, i)
              candidates[#candidates + 1] = { task = t, target = i, d = (x - ax) ^ 2 + (y - ay) ^ 2 }
            end
          end)
        end
      end
      table.sort(candidates, function(a, b)
        if a.d ~= b.d then
          return a.d < b.d
        end
        return a.target < b.target -- deterministic tie-break
      end)
      for n = 1, math.min(PATH_ATTEMPTS, #candidates) do
        local c = candidates[n]
        local path = pathFor(world, actor, c.task, c.target)
        if path then
          return newJob(c.task, c.target, path, nil)
        end
      end
    end
  end
  return nil
end

return Tasks
