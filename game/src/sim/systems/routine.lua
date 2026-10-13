-- Routine memory and the idle hint (GDD D55, issue #113).
--
-- `wanted` is the persisted "the routine was running" flag. By day it mirrors the control mode
-- (routine in charge = true; the player directing = false); it is set at once by the R key and
-- cleared by any player order. At bedtime it freezes, so it still reads true in the morning and
-- on a loaded save, and Session resumes the routine when the homesteader wakes (D55).
-- While the routine is off and the homesteader stands with nothing to do (awake, daytime), game
-- seconds are counted; past `tuning.idle.hintAfter` it emits "routine.idleHint" (rate limited by
-- `tuning.idle.hintInterval`) so the UI can nudge the player.
--
-- Starter field (D61, #66): when the routine is in charge and nothing is planned, tilled or growing,
-- it plans a small default field (Crops.planStarter) so an unattended start does not starve.
--
-- With the routine ON and no job found for `tuning.idle.nothingAfter` seconds it emits
-- "routine.nothingToDo" instead (D93, #119), on the same cooldown.
--
-- State: world.state.routine = { wanted, idleFor, cooldown, planDay, noJobFor (only while counting) }.

local Actors = require("src.sim.systems.actors")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Sleep = require("src.sim.systems.sleep")

local Routine = {}

local function state(world)
  return world.state.routine
end

function Routine.init(world)
  local s = world.state.routine
  if not s then
    s = {}
    world.state.routine = s
  end
  s.wanted = s.wanted == true
  s.idleFor = s.idleFor or 0 -- game seconds the homesteader has idled with the routine off
  s.cooldown = s.cooldown or 0 -- game seconds before another hint may fire
  s.planDay = s.planDay or 0 -- calendar day the starter field was last considered
end

--- Does the player want the routine running (survives bedtime and saves)?
function Routine.wanted(world)
  return state(world).wanted
end

function Routine.setWanted(world, wanted)
  local s = state(world)
  s.wanted = wanted == true
  if wanted then
    s.idleFor, s.noJobFor = 0, nil
  end
end

--- Can the homesteader work right now (awake and not in bedtime hours)?
local function working(world)
  return not (Sleep.isBedtime(world) or Sleep.resting(Actors.homesteader(world)))
end

--- Which nudge the UI should show right now (D54, D93): "idle" (routine off, homesteader standing about),
--- "nothing" (routine on, no job found), or nil. A pure read of the counters, so the HUD can mark the
--- Routine button for as long as it holds, even while a panel covers the world (#120).
function Routine.hintKind(world)
  local s, idle = state(world), world.tuning.idle
  if s.wanted then
    return (s.noJobFor or 0) >= idle.nothingAfter and "nothing" or nil
  end
  return s.idleFor >= idle.hintAfter and "idle" or nil
end

function Routine.tick(world, dt)
  local s = state(world)
  local idle = world.tuning.idle
  s.cooldown = math.max(0, s.cooldown - dt)
  if not working(world) then
    s.idleFor, s.noJobFor = 0, nil
    return
  end
  local was = s.wanted
  s.wanted = world.control == "idle"
  local hs = Actors.homesteader(world)
  if s.wanted then
    s.idleFor = 0
    -- Routine on but no job found (every priority empty or off, nothing planned that can be worked):
    -- count it and nudge once past nothingAfter (D93, #119). Planned tiles are standing orders (D92),
    -- so they count as jobs through `hs.job` like any other.
    s.noJobFor = not (hs.job or hs.order) and (s.noJobFor or 0) + dt or nil
    if (s.noJobFor or 0) >= idle.nothingAfter and s.cooldown <= 0 then
      s.cooldown = idle.hintInterval
      world.events:emit("routine.nothingToDo", { noJobFor = s.noJobFor })
    end
    -- The routine only works planned tiles, so with nothing planned it plans the starter field
    -- (D61): on takeover, and again each new day in case a frozen season or missing seed stopped it.
    local day = Calendar.now(world).day
    if not was or s.planDay ~= day then
      s.planDay = day
      Crops.planStarter(world)
    end
    return
  end
  s.noJobFor = nil
  if hs.job or hs.order then
    s.idleFor = 0
    return
  end
  s.idleFor = s.idleFor + dt
  if s.idleFor >= idle.hintAfter and s.cooldown <= 0 then
    s.cooldown = idle.hintInterval
    world.events:emit("routine.idleHint", { idleFor = s.idleFor })
  end
end

return Routine
