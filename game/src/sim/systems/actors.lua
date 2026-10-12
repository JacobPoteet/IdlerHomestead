-- Actors (GDD §7.4): things that walk around and do tasks. For now, the homesteader.
--
-- State: world.state.actors = array of
--   { id, kind, x, y, bucket, job, order, wait }
-- x, y are tile coordinates (floats; integer = tile centre). `job` is the current task
-- (see tasks.lua); `order` is a pending player order picked up on the next tick.
--
-- world.control ("active" | "idle") is set each frame by the session from player input
-- (not saved). In idle control the homesteader follows the priority routine; in active
-- control it only does what the player orders (an idle job already underway is finished).

local Grid = require("src.sim.grid")
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
    local x, y = Grid.coords(state.grid, state.land.spawn)
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

function Actors.homesteader(world)
  return world.state.actors[1]
end

--- Queue a player order on tile i. opts: { crop = cropId } for planting/tilling.
--- Returns the task type the order will run, or nil if nothing can be done there.
function Actors.order(world, actor, i, opts)
  local job = Tasks.jobForOrder(world, actor, i, opts)
  if job then
    actor.order = job
    return Tasks.get(world, job.task)
  end
  return nil
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

local function work(world, actor, dt)
  local job = actor.job
  local taskType = Tasks.get(world, job.task)
  if not taskType.canDo(world, actor, job.target, job.order) then
    dropJob(world, actor)
    return
  end
  local idle = world.tuning.idle
  local multiplier = job.ordered and idle.activeWorkMultiplier or idle.idleWorkMultiplier
  job.progress = job.progress + dt * multiplier
  if job.progress >= taskType.workTime(world, actor, job.target) then
    local target, order = job.target, job.order
    dropJob(world, actor)
    taskType.complete(world, actor, target, order)
    world.events:emit("task.completed", { task = taskType.id, target = target, actor = actor.id, ordered = order ~= nil })
  end
end

function Actors.tick(world, dt)
  for _, actor in ipairs(world.state.actors) do
    actor.prevX, actor.prevY = actor.x, actor.y
    if actor.order then
      dropJob(world, actor)
      actor.job = actor.order
      actor.order = nil
      Tasks.reserve(world, actor, actor.job)
    end
    if not actor.job and world.control == "idle" then
      actor.wait = (actor.wait or 0) - dt
      if actor.wait <= 0 then
        local job = Tasks.chooseIdleJob(world, actor)
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
