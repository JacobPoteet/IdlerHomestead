-- Sleep (GDD §5.3 shelter, §8.1 study): the homesteader goes to bed a little after sunset and
-- wakes at sunrise, so long winter nights mean long sleeps (and long study).
--
-- At bedtime an actor with no job, or only a routine job, walks to the nearest shelter (the truck
-- at first) and sleeps there. A player order wakes them up ("stay up"); once nothing is left to do
-- they head back to bed. The routine never runs during bedtime.
--
-- State: actor.asleep (bool) on world.state.actors entries.
-- Emits "sleep.started" { actor } and "sleep.woke" { actor }.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Tasks = require("src.sim.systems.tasks")

local Sleep = {}

--- Hours of the day the homesteader should be in bed: sunset + evening until sunrise.
function Sleep.bedtimeHours(world)
  local sunrise, sunset = Calendar.daylight(world)
  return sunset + world.tuning.actors.eveningHours, sunrise
end

function Sleep.isBedtime(world)
  local from, to = Sleep.bedtimeHours(world)
  local hour = Calendar.now(world).hour
  if from >= 24 then
    return hour >= from - 24 and hour < to
  end
  return hour >= from or hour < to
end

--- In bed or on the way there (both count as resting for study).
function Sleep.resting(actor)
  return actor.asleep == true or (actor.job ~= nil and actor.job.task == "sleep")
end

--- Is the homesteader resting? (GDD §8.1: study happens while the homesteader sleeps.)
function Sleep.homesteaderResting(world)
  return Sleep.resting(world.state.actors[1])
end

local function shelters(world)
  local list = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if world.registry:get("objects", obj.id).shelter then
      list[#list + 1] = anchor
    end
  end
  table.sort(list)
  return list
end

--- A job that walks the actor to bed, or nil if no shelter can be reached.
function Sleep.bedJob(world, actor)
  local best
  for _, anchor in ipairs(shelters(world)) do
    local job = Tasks.jobFor(world, actor, "sleep", anchor)
    if job and (not best or #job.path < #best.path) then
      best = job
    end
  end
  return best
end

--- Wake an actor (a player order, or morning).
function Sleep.wake(world, actor)
  if actor.asleep then
    actor.asleep = false
    world.events:emit("sleep.woke", { actor = actor.id })
  end
end

function Sleep.init(world)
  Tasks.register(world, {
    id = "sleep",
    verb = "Sleep",
    canDo = function(w, _, i)
      local obj = Grid.object(w, i)
      return obj ~= nil and obj.shelter == true
    end,
    workTime = function()
      return 0
    end,
    complete = function(w, actor)
      if Sleep.isBedtime(w) then
        actor.asleep = true
        w.events:emit("sleep.started", { actor = actor.id })
      end
    end,
  })
end

function Sleep.tick(world)
  if Sleep.isBedtime(world) then
    return
  end
  for _, actor in ipairs(world.state.actors) do
    Sleep.wake(world, actor)
  end
end

return Sleep
