-- A play session on one save slot: owns the slot data, the running World, the sim clock,
-- playtime, and autosaving. Sits between the app/scenes and the sim; no rendering here.

local Clock = require("src.core.clock")
local Rng = require("src.core.rng")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Sleep = require("src.sim.systems.sleep")
local Routine = require("src.sim.systems.routine")

local Session = {}
Session.__index = Session

--- opts: { store, slot, data, registry, tuning, events? }
--- `data` is the slot data (from Save:read or Save.newSlotData). Starts a new run if it has none.
function Session.new(opts)
  local tuning = opts.tuning
  local data = opts.data
  if not data.run then
    data.run = World.newState(opts.seed or Rng.freshSeed())
  end
  local self = setmetatable({
    store = opts.store,
    slot = opts.slot,
    data = data,
    tuning = tuning,
    world = World.new({ registry = opts.registry, tuning = tuning, events = opts.events, meta = data.meta }, data.run),
    clock = Clock.new({ tickRate = tuning.time.tickRate, maxTicksPerFrame = tuning.time.maxTicksPerFrame }),
    sinceSave = 0,
    routineNow = false, -- routine forced on (runtime); the saved "wanted" flag in sim state restores it
  }, Session)
  self.clock.timeScale = tuning.time.defaultSpeed
  self.tick = function(dt)
    self.world:tick(dt)
  end
  return self
end

--- "active" (the player is directing) or "idle" (the routine takes over). See GDD §5.2.
function Session:setControl(mode)
  self.world.control = mode
end

--- The sim time scale (0 = paused). One mechanism for the player's speed button and the F2 debug key.
function Session:speed()
  return self.clock.timeScale
end

function Session:setSpeed(scale)
  self.clock.timeScale = scale
end

--- Step to the next value in `steps` after the current one (wrapping); a current value that isn't in
--- the list restarts from the first. Returns the new scale.
function Session:cycleSpeed(steps)
  if self:timeHeld() then
    return self.clock.timeScale -- time stands still in town (D78) or under a tip card (D92); the chosen speed waits
  end
  local current = self.clock.timeScale
  local nextScale = steps[1]
  for i, s in ipairs(steps) do
    if s == current then
      nextScale = steps[i % #steps + 1]
      break
    end
  end
  self.clock.timeScale = nextScale
  return nextScale
end

--- Hand the homesteader to the idle routine now instead of waiting out the takeover delay (GDD D43).
--- Refused (returns false, reason) while the homesteader is resting: the routine stops at bedtime
--- (D35). Stays on until `cancelRoutine` (a player order) or bedtime.
function Session:startRoutineNow()
  local ok, reason = self:canStartRoutine()
  if not ok then
    return false, reason
  end
  self.routineNow = true
  Routine.setWanted(self.world, true)
  self:setControl("idle") -- the sim must see it before the scene's next update
  return true
end

--- Can the routine be started by hand right now? Returns true, or false + "resting".
function Session:canStartRoutine()
  local world = self.world
  if Sleep.isBedtime(world) or Sleep.resting(Actors.homesteader(world)) then
    return false, "resting"
  end
  return true
end

--- Give control back to the player (any order does this).
function Session:cancelRoutine()
  self.routineNow = false
  self.resumeOnWake = false
  Routine.setWanted(self.world, false)
end

--- Is the routine running because the player asked for it?
function Session:routineForced()
  return self.routineNow == true
end

--- Is the homesteader asleep right now (in bed, not just walking there)?
function Session:sleeping()
  return Actors.homesteader(self.world).asleep == true
end

--- Skip the rest of the night: the sim runs at tuning.time.skipSpeed until the homesteader wakes.
--- Returns false when nobody is asleep (D56).
function Session:skipNight()
  if not self:sleeping() or self.tipUp then -- no fast-forward under a tip card (D92)
    return false
  end
  self.skipping = true
  return true
end

function Session:skippingNight()
  return self.skipping == true and self:sleeping()
end

--- Is the player on a town trip (the town menu is open)? Game time stands still meanwhile (D78).
function Session:inTown()
  return self.world.state.market.inTown == true
end

--- The scene tells the session whether an FTUE tip card is on screen (D92, #230). Runtime only, never saved.
function Session:setTipUp(up)
  self.tipUp = up == true
end

--- Is game time held for the player to read or decide: a town trip (D78) or a tip card (D92)? The
--- chosen speed is untouched, so it is back the moment the hold ends.
function Session:timeHeld()
  return self:inTown() or self.tipUp == true
end

--- The sim speed actually applied: the player's speed, raised automatically while asleep (D56).
--- A pause stays a pause. Sleep speed never lowers a speed the player chose above it. In town it is
--- 0 whatever was chosen (D78): the chosen speed is untouched, so it is back on the drive home.
function Session:effectiveSpeed()
  local chosen = self.clock.timeScale
  if self:timeHeld() then
    return 0
  end
  if chosen == 0 or not self:sleeping() then
    return chosen
  end
  local time = self.tuning.time
  return math.max(chosen, self.skipping and time.skipSpeed or time.sleepSpeed)
end

--- Run the due ticks at the effective speed. The tick that wakes the homesteader ends a fast
--- stretch there and then, so a skip lands on the morning tick whatever the frame size (D56).
function Session:advanceSim(dt)
  local clock = self.clock
  local chosen = clock.timeScale
  local effective = self:effectiveSpeed()
  if effective == chosen then
    self.skipping = false
    clock:advance(dt, self.tick)
    return
  end
  clock.timeScale = effective
  clock:advance(dt, function(step)
    self.tick(step)
    if clock.timeScale ~= chosen and not self:sleeping() then
      clock.timeScale = chosen
      clock.accumulator = 0 -- drop the fast leftover rather than run it past the morning
    end
  end)
  clock.timeScale = chosen
  if not self:sleeping() then
    self.skipping = false
  end
end

--- Advance real time: runs due sim ticks, accrues playtime, autosaves on the interval.
function Session:update(dt)
  local canStart = self:canStartRoutine()
  if self.routineNow and not canStart then
    self.routineNow = false -- bedtime pauses a started routine; waking resumes it (below)
  end
  if not canStart then
    -- Remember it while resting: the waking tick itself re-mirrors the control mode.
    self.resumeOnWake = Routine.wanted(self.world)
  elseif self.couldStart == false and self.resumeOnWake then
    self.resumeOnWake = false
    self.routineNow = true -- woke up and the routine was running at bedtime: resume (D55)
    Routine.setWanted(self.world, true)
    self:setControl("idle")
  end
  self.couldStart = canStart
  self:advanceSim(dt)
  local header = self.data.header
  header.playtime = (header.playtime or 0) + dt
  self.sinceSave = self.sinceSave + dt
  if self.sinceSave >= self.tuning.save.autosaveInterval then
    self:save()
  end
end

--- Write the slot now. Returns true on success, or false + error.
function Session:save()
  self.sinceSave = 0
  local header = self.data.header
  for k, v in pairs(self.world:summarize()) do
    header[k] = v
  end
  return self.store:write(self.slot, self.data)
end

return Session
