-- Player-facing controls: game speed (D42), start-routine-now (D43), action progress (D44).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local Session = require("src.session")
local Grid = require("src.sim.grid")
local Actors = require("src.sim.systems.actors")
local Sleep = require("src.sim.systems.sleep")

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

T.test("routine now: bedtime ends it, and the morning does not restart it", function()
  local session = newSession()
  local world = session.world
  local bed = Sleep.bedtimeHours(world)
  setTime(world, bed - 0.1)
  T.truthy(session:startRoutineNow())
  setTime(world, bed + 0.1)
  session:update(STEP)
  T.falsy(session:routineForced(), "stopped at bedtime")
  local _, wake = Sleep.bedtimeHours(world)
  setTime(world, wake + 1)
  session:update(STEP)
  T.falsy(session:routineForced(), "stays off in the morning")
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
