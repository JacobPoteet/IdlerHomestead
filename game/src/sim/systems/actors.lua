-- Actors (GDD §7.4): things that walk around and do tasks. For now, the homesteader. Machines are
-- stationary actors on the same task board, run by machines.lua (D65).
--
-- State: world.state.actors = array of
--   { id, kind, x, y, bucket, job, order, wait }
-- x, y are tile coordinates (floats; integer = tile centre). `job` is the current task
-- (see tasks.lua); `order` is a pending player order picked up on the next tick.
--
-- world.control ("active" | "idle") is set each frame by the session from player input
-- (not saved). In idle control the homesteader follows the priority routine; in active
-- control it only does what the player orders (an idle job already underway is finished).
-- At bedtime the homesteader drops routine work and goes to sleep (see sleep.lua); a player
-- order wakes them.

local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Sleep = require("src.sim.systems.sleep")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")

local Actors = {}

function Actors.init(world)
  local state = world.state
  world.control = world.control or "active"
  -- Player-only: tap open ground to walk there.
  Tasks.register(world, {
    id = "move",
    verb = "Walk",
    clickOrder = 1000,
    standOn = true,
    canDo = function(w, _, i)
      return Grid.walkable(w, i)
    end,
    workTime = function()
      return 0
    end,
    complete = function() end,
  })
  if not state.actors then
    local x, y = Grid.coords(state.grid, Land.spawn(world))
    state.actors = {
      { id = 1, kind = "homesteader", x = x, y = y, bucket = 0, wait = 0 },
    }
  end
  for _, actor in ipairs(state.actors) do
    actor.prevX, actor.prevY = actor.x, actor.y
    if actor.job then
      Tasks.reserve(world, actor, actor.job)
    end
  end
end

--- The homesteader: the first actor of kind "homesteader" (it is created first, so this is actors[1]
--- on every save; the lookup keeps that an implementation detail).
function Actors.homesteader(world)
  local list = world.state.actors
  for _, actor in ipairs(list) do
    if actor.kind == "homesteader" then
      return actor
    end
  end
  return list[1]
end

--- All walking actors (array; empty before the actors system has initialised). Machines are actors
--- on the task board too, but stand still and live in machines.lua (Machines.list), so this list is
--- what walks, sleeps and carries a bucket (D65).
function Actors.list(world)
  return world.state.actors or {}
end

--- Queue a player order on tile i. opts: { crop = cropId } for planting/tilling.
--- Returns the task type the order will run, or nil if nothing can be done there.
function Actors.order(world, actor, i, opts)
  local job, full = Tasks.jobForOrder(world, actor, i, opts)
  if job then
    actor.order = job
    return (Tasks.get(world, job.task)) -- parentheses: Tasks.get returns assert's extra message too
  end
  return nil, full -- full: the resource whose store has no room, when that is why it was refused
end

local function dropJob(world, actor)
  if actor.job then
    Tasks.release(world, actor.job)
    actor.job = nil
  end
end

local function walk(world, actor, dt)
  local grid = world.state.grid
  local path = actor.job.path
  local remaining = world.tuning.actors.walkSpeed * dt
  while remaining > 0 and #path > 0 do
    local nextTile = path[1]
    if not Grid.walkable(world, nextTile) then
      return false -- something now blocks the way
    end
    local tx, ty = Grid.coords(grid, nextTile)
    local dx, dy = tx - actor.x, ty - actor.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local speedScale = 1 / Grid.walkCost(world, nextTile)
    local step = remaining * speedScale
    if step >= dist then
      actor.x, actor.y = tx, ty
      table.remove(path, 1)
      remaining = remaining - dist / speedScale
    else
      actor.x, actor.y = actor.x + dx / dist * step, actor.y + dy / dist * step
      remaining = 0
    end
  end
  return true
end

-- Work seconds done per second of game time: ordered jobs run at the active multiplier, routine
-- jobs at the idle one (GDD §5.2).
local function workRate(world, job)
  local idle = world.tuning.idle
  return job.ordered and idle.activeWorkMultiplier or idle.idleWorkMultiplier + Stats.modifier(world, "idleEfficiency")
end

--- Progress of the actor's current timed action, for the UI (GDD D44), or nil when there is none:
--- walking, resting, or an instant action (work time 0). Read-only.
--- Returns { task, target, fraction (0..1), duration (work seconds), remaining (game seconds) }.
function Actors.progress(world, actor)
  local job = actor.job
  if not job or #job.path > 0 then
    return nil
  end
  local duration = Tasks.get(world, job.task).workTime(world, actor, job.target)
  if duration <= 0 then
    return nil
  end
  local done = math.min(job.progress, duration)
  return {
    task = job.task,
    target = job.target,
    fraction = done / duration,
    duration = duration,
    remaining = (duration - done) / workRate(world, job),
  }
end

local function work(world, actor, dt)
  local job = actor.job
  local taskType = Tasks.get(world, job.task)
  if not taskType.canDo(world, actor, job.target, job.order) then
    dropJob(world, actor)
    return
  end
  job.progress = job.progress + dt * workRate(world, job)
  if job.progress >= taskType.workTime(world, actor, job.target) then
    local target, order = job.target, job.order
    dropJob(world, actor)
    taskType.complete(world, actor, target, order)
    world.events:emit("task.completed", { task = taskType.id, target = target, actor = actor.id, ordered = order ~= nil })
  end
end

-- At bedtime, anything but a player order gives way to walking to bed.
local function goToBed(world, actor)
  local job = actor.job
  if job and (job.ordered or job.task == "sleep") then
    return
  end
  dropJob(world, actor)
  actor.job = Sleep.bedJob(world, actor)
  if actor.job then
    Tasks.reserve(world, actor, actor.job)
  else
    -- No shelter in reach: sleep where you stand.
    actor.asleep = true
    world.events:emit("sleep.started", { actor = actor.id })
  end
end

function Actors.tick(world, dt)
  local bedtime = Sleep.isBedtime(world)
  for _, actor in ipairs(world.state.actors) do
    actor.prevX, actor.prevY = actor.x, actor.y
    if actor.order then
      Sleep.wake(world, actor)
      dropJob(world, actor)
      actor.job = actor.order
      actor.order = nil
      Tasks.reserve(world, actor, actor.job)
    end
    if bedtime and not actor.asleep then
      goToBed(world, actor)
    end
    if not actor.job and not bedtime then
      actor.wait = (actor.wait or 0) - dt
      if actor.wait <= 0 then
        -- Standing orders (planned tiles to till and plant, D92) come first in either control mode;
        -- the routine's own priorities only apply while it is in charge.
        local job = Tasks.chooseStandingJob(world, actor)
        if not job and world.control == "idle" then
          job = Tasks.chooseIdleJob(world, actor)
        end
        if job then
          actor.job = job
          Tasks.reserve(world, actor, job)
        else
          actor.wait = world.tuning.idle.recheckInterval
        end
      end
    end
    if actor.job then
      if #actor.job.path > 0 then
        if not walk(world, actor, dt) then
          dropJob(world, actor)
        end
      else
        work(world, actor, dt)
      end
    end
  end
end

return Actors
