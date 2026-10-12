-- Player-facing controls: game speed (D42), start-routine-now (D43), action progress (D44).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local Session = require("src.session")
local Grid = require("src.sim.grid")
local Actors = require("src.sim.systems.actors")
local Sleep = require("src.sim.systems.sleep")
local Routine = require("src.sim.systems.routine")
local World = require("src.sim.world")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newSession(seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = Save.newSlotData("Controls"), registry = reg, tuning = tun, seed = seed or 5 })
end

local function setTime(world, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((hour / 24) - t.startHour / 24) * t.dayLength
end

--- Jump to just after sunrise and let the homesteader get out of bed.
local function morning(session, wake)
  setTime(session.world, wake + 1)
  for _ = 1, 400 do
    session:update(STEP)
    if session:canStartRoutine() then
      session:update(STEP) -- the next frame notices the wake-up
      return
    end
  end
  error("homesteader never woke")
end

local function ticksIn(session, seconds)
  local before = session.world.state.tick
  session:update(seconds)
  return session.world.state.tick - before
end

-- Speed ------------------------------------------------------------------------------------

T.test("speed: a session starts at the default and the button steps through the tuning list", function()
  local session = newSession()
  local steps = tun.time.speedSteps
  T.eq(session:speed(), tun.time.defaultSpeed)
  T.eq(steps[1], 0, "the list starts at paused")
  local seen = {}
  for _ = 1, #steps do
    seen[#seen + 1] = session:cycleSpeed(steps)
  end
  T.eq(session:speed(), tun.time.defaultSpeed, "a full lap returns to where it began")
  T.eq(table.concat(seen, ","), "2,4,0,1")
end)

T.test("speed: an unlisted scale (debug F2) restarts the button list from its first step", function()
  local session = newSession()
  session:setSpeed(30)
  T.eq(session:cycleSpeed(tun.time.speedSteps), tun.time.speedSteps[1])
  -- and the debug list uses the same mechanism
  session:cycleSpeed(tun.time.debugTimeScales)
  T.eq(session:speed(), tun.time.debugTimeScales[1])
end)

T.test("speed: paused runs no ticks, 2x runs twice as many", function()
  local session = newSession()
  session:setSpeed(0)
  T.eq(ticksIn(session, 1), 0, "paused")
  session:setSpeed(1)
  local one = ticksIn(session, 1)
  session:setSpeed(2)
  local two = ticksIn(session, 1)
  T.near(two / one, 2, 0.1)
  session:setSpeed(4)
  T.near(ticksIn(session, 1) / one, 4, 0.2)
end)

-- Start routine now ------------------------------------------------------------------------

T.test("routine now: starts at once in daytime and an order hands control back", function()
  local session = newSession()
  setTime(session.world, 10)
  T.falsy(session:routineForced())
  T.truthy(session:startRoutineNow())
  T.truthy(session:routineForced())
  session:update(STEP)
  T.truthy(session:routineForced(), "stays on while the day goes on")
  session:cancelRoutine()
  T.falsy(session:routineForced())
end)

T.test("routine now: refused at bedtime and while asleep (D35)", function()
  local session = newSession()
  local world = session.world
  local bed = Sleep.bedtimeHours(world)
  setTime(world, bed + 0.5)
  local ok, why = session:startRoutineNow()
  T.falsy(ok)
  T.eq(why, "resting")
  T.falsy(session:routineForced())
  setTime(world, 10)
  Actors.homesteader(world).asleep = true
  T.falsy(session:canStartRoutine(), "asleep")
  T.falsy(session:startRoutineNow())
end)

T.test("routine now: bedtime pauses it, and the morning resumes it (D55)", function()
  local session = newSession()
  local world = session.world
  local bed = Sleep.bedtimeHours(world)
  setTime(world, bed - 0.1)
  T.truthy(session:startRoutineNow())
  session:update(STEP)
  setTime(world, bed + 0.1)
  session:update(STEP)
  T.falsy(session:routineForced(), "stopped at bedtime")
  T.truthy(Routine.wanted(world), "but still wanted")
  local _, wake = Sleep.bedtimeHours(world)
  morning(session, wake)
  T.truthy(session:routineForced(), "resumes in the morning")
end)

T.test("routine resume: normal takeover by day also resumes after sleep", function()
  local session = newSession()
  local world = session.world
  local bed = Sleep.bedtimeHours(world)
  setTime(world, bed - 0.5)
  session:setControl("idle") -- what the scene does once the takeover delay has passed
  session:update(STEP)
  T.falsy(session:routineForced(), "not forced: any input still hands control back")
  setTime(world, bed + 0.1)
  session:update(STEP)
  local _, wake = Sleep.bedtimeHours(world)
  morning(session, wake)
  T.truthy(session:routineForced())
end)

T.test("routine resume: not if the player took control or never had it on", function()
  local session = newSession()
  local world = session.world
  local bed = Sleep.bedtimeHours(world)
  local _, wake = Sleep.bedtimeHours(world)
  -- Never on.
  setTime(world, bed - 0.5)
  session:update(STEP)
  setTime(world, bed + 0.1)
  session:update(STEP)
  morning(session, wake)
  T.falsy(session:routineForced(), "never on")
  -- On, then a player order (cancelRoutine) before bedtime.
  setTime(world, bed - 0.5)
  session:update(STEP)
  T.truthy(session:startRoutineNow())
  session:cancelRoutine()
  session:setControl("active")
  session:update(STEP)
  setTime(world, bed + 0.1)
  session:update(STEP)
  morning(session, wake)
  T.falsy(session:routineForced(), "took control")
  -- On at bedtime, then a "stay up" order during the night clears it.
  setTime(world, bed - 0.5)
  session:update(STEP)
  T.truthy(session:startRoutineNow())
  session:update(STEP)
  setTime(world, bed + 0.1)
  session:update(STEP)
  session:cancelRoutine()
  morning(session, wake)
  T.falsy(session:routineForced(), "stay-up order")
end)

T.test("routine resume: wanted survives a save round-trip, and an older save loads", function()
  local session = newSession()
  local world = session.world
  setTime(world, 10)
  T.truthy(session:startRoutineNow())
  session:update(STEP)
  local state = serialize.decode(serialize.encode(world.state))
  T.truthy(state.routine.wanted)
  local loaded = World.new({ registry = reg, tuning = tun }, state)
  T.truthy(Routine.wanted(loaded))
  -- A save from before D55 has no routine table.
  local old = serialize.decode(serialize.encode(world.state))
  old.routine = nil
  local older = World.new({ registry = reg, tuning = tun }, old)
  T.falsy(Routine.wanted(older))
  older:tick(STEP)
end)

T.test("routine resume: deterministic for a seed", function()
  local function run()
    local session = newSession(9)
    local bed = Sleep.bedtimeHours(session.world)
    setTime(session.world, bed - 0.2)
    session:startRoutineNow()
    local flags = {}
    for i = 1, 400 do
      session:update(STEP * 5)
      flags[#flags + 1] = (session:routineForced() and "1" or "0") .. session.world.state.tick
    end
    return table.concat(flags, ","), serialize.encode(session.world.state)
  end
  local a, sa = run()
  local b, sb = run()
  T.eq(a, b)
  T.eq(sa, sb)
end)

-- Idle hint --------------------------------------------------------------------------------

T.test("idle hint: fires after hintAfter idle seconds, then is rate limited", function()
  local session = newSession()
  local world = session.world
  setTime(world, 10)
  session:setControl("active")
  local hints = 0
  world.events:on("routine.idleHint", function()
    hints = hints + 1
  end)
  local function run(seconds)
    for _ = 1, math.floor(seconds / STEP) do
      session:setControl("active")
      world:tick(STEP)
      setTime(world, 10) -- keep it daytime
    end
  end
  run(tun.idle.hintAfter - 2)
  T.eq(hints, 0, "not yet")
  run(4)
  T.eq(hints, 1, "fired")
  run(tun.idle.hintInterval - 6)
  T.eq(hints, 1, "rate limited")
  run(10)
  T.eq(hints, 2, "fires again after the interval")
end)

T.test("idle hint: silent while the routine runs, working, or resting", function()
  local session = newSession()
  local world = session.world
  local hints = 0
  world.events:on("routine.idleHint", function()
    hints = hints + 1
  end)
  setTime(world, 10)
  for _ = 1, math.floor(tun.idle.hintAfter * 3 / STEP) do
    world.control = "idle" -- routine on
    world:tick(STEP)
    setTime(world, 10)
  end
  T.eq(hints, 0, "routine on")
  for _ = 1, math.floor(tun.idle.hintAfter * 3 / STEP) do
    world.control = "active"
    setTime(world, Sleep.bedtimeHours(world) + 0.5)
    world:tick(STEP)
  end
  T.eq(hints, 0, "bedtime")
end)

T.test("takeover: browse panels do not reset the timer, the homestead does (D55)", function()
  local Input = require("src.core.input")
  local top = { name = "homestead" }
  local app = { top = function() return top end }
  local input = Input.new(app, tun)
  input.lastActivity = 100
  top.name = "catalog"
  input:activity()
  T.eq(input.lastActivity, 100, "catalog input ignored")
  top.name = "homestead"
  input:activity()
  T.truthy(input.lastActivity ~= 100, "homestead input counts")
end)

-- Action progress --------------------------------------------------------------------------

local function nearbyTillable(world)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        if Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if Grid.terrain(world, i).tillable and not world.occupancy[i] and i ~= world.state.land.spawn then
            return i
          end
        end
      end
    end
  end
end

T.test("progress: nil with no job and for instant actions", function()
  local world = newSession().world
  local hs = Actors.homesteader(world)
  T.eq(Actors.progress(world, hs), nil, "no job")
  local tile = nearbyTillable(world)
  Actors.order(world, hs, tile) -- no seed in hand: a plain walk
  for _ = 1, 400 do
    world:tick(STEP)
    T.eq(Actors.progress(world, hs), nil, "walking is instant work")
  end
end)

T.test("progress: a timed action reports a rising fraction and a shrinking remainder, then ends", function()
  local world = newSession().world
  local hs = Actors.homesteader(world)
  local tile = nearbyTillable(world)
  Actors.order(world, hs, tile, { crop = "radish" })
  local first, last
  for _ = 1, 400 do
    world:tick(STEP)
    local p = Actors.progress(world, hs)
    if p then
      T.eq(p.task, "till")
      T.eq(p.target, tile)
      T.eq(p.duration, tun.farming.tillTime)
      T.truthy(p.fraction >= 0 and p.fraction <= 1)
      first = first or p
      last = { fraction = p.fraction, remaining = p.remaining }
    elseif last then
      break
    end
  end
  T.truthy(first and last, "saw the action in progress")
  T.truthy(last.fraction > first.fraction, "fraction rises")
  T.truthy(last.remaining < first.remaining, "remaining shrinks")
  T.eq(Actors.progress(world, hs), nil, "gone once finished")
  T.truthy(world.state.fields.tilled[tile])
end)

T.test("progress: routine-chosen work reports it too", function()
  local world = newSession().world
  world.control = "idle"
  local hs = Actors.homesteader(world)
  local plan = nearbyTillable(world)
  world.state.fields.plan[plan] = "radish"
  local routine
  for _ = 1, 600 do
    world:tick(STEP)
    local p = Actors.progress(world, hs)
    if p and not hs.job.ordered then
      routine = p
      break
    end
  end
  T.truthy(routine, "the routine started a timed action")
  T.truthy(routine.remaining >= routine.duration * (1 - routine.fraction) / tun.idle.activeWorkMultiplier,
    "idle work is not faster than active work")
end)
