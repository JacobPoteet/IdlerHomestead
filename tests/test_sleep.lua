-- Fast sleep and skip-the-night (GDD D56, issue #112): sleep runs at an automatic sim speed, the
-- skip control goes faster still, and nothing about the sim changes except how many ticks a frame runs.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local Session = require("src.session")
local Calendar = require("src.sim.systems.calendar")
local Actors = require("src.sim.systems.actors")
local Journal = require("src.sim.systems.journal")
local Sleep = require("src.sim.systems.sleep")
local World = require("src.sim.world")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local FRAME = 1 / 60

local function newSession(seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = Save.newSlotData("Sleep"), registry = reg, tuning = tun, seed = seed or 3 })
end

local function setTime(world, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((hour / 24) - t.startHour / 24) * t.dayLength
end

--- A session with the homesteader already in bed, `after` hours past bedtime.
local function inBed(seed, after)
  local session = newSession(seed)
  local world = session.world
  local bed = Sleep.bedtimeHours(world)
  setTime(world, bed + (after or 0.5))
  Actors.homesteader(world).asleep = true
  return session
end

local function ticksIn(session, seconds)
  local before = session.world.state.tick
  session:update(seconds)
  return session.world.state.tick - before
end

T.test("sleep speed: applies only while the homesteader is asleep", function()
  local session = newSession()
  local world = session.world
  setTime(world, 10)
  T.eq(session:effectiveSpeed(), tun.time.defaultSpeed, "awake by day")
  local bed = Sleep.bedtimeHours(world)
  setTime(world, bed + 0.5)
  T.eq(session:effectiveSpeed(), tun.time.defaultSpeed, "bedtime but still up (walking to bed)")
  Actors.homesteader(world).asleep = true
  T.eq(session:effectiveSpeed(), tun.time.sleepSpeed, "asleep")
  T.eq(session:speed(), tun.time.defaultSpeed, "the player's own speed is untouched")
  Actors.homesteader(world).asleep = false
  T.eq(session:effectiveSpeed(), tun.time.defaultSpeed, "awake again")
end)

T.test("sleep speed: a pause stays paused and ticks scale with the speed", function()
  local session = inBed()
  session:setSpeed(0)
  T.eq(session:effectiveSpeed(), 0)
  T.eq(ticksIn(session, 1), 0, "paused while asleep")
  session:setSpeed(1)
  local fast = ticksIn(session, 1)
  T.eq(fast, tun.time.sleepSpeed * tun.time.tickRate, "one real second asleep is sleepSpeed seconds of sim")
  Actors.homesteader(session.world).asleep = false
  setTime(session.world, 10)
  T.eq(ticksIn(session, 1), tun.time.tickRate, "and 1x again once awake")
end)

--- Run until the homesteader wakes; returns the encoded world state.
local function wakeFast(session, frame, skip)
  local world = session.world
  if skip then
    T.truthy(session:skipNight())
  end
  for _ = 1, 100000 do
    session:update(frame)
    if not Actors.homesteader(world).asleep then
      return serialize.encode(world.state)
    end
  end
  error("never woke")
end

T.test("sleep speed: fast sleep, skip and plain 1x ticking give the identical morning", function()
  local slow = inBed(7)
  local world = slow.world
  for _ = 1, 100000 do
    world:tick(STEP)
    if not Actors.homesteader(world).asleep then
      break
    end
  end
  local reference = serialize.encode(world.state)
  T.eq(wakeFast(inBed(7), FRAME), reference, "automatic sleep speed")
  T.eq(wakeFast(inBed(7), 1 / 30, true), reference, "skip")
  T.eq(wakeFast(inBed(7), 0.2), reference, "a big frame")
end)

T.test("skip night: lands on the morning tick and returns to normal speed", function()
  local session = inBed(2)
  local world = session.world
  T.falsy(session:skippingNight())
  T.truthy(session:skipNight())
  T.truthy(session:skippingNight())
  T.eq(session:effectiveSpeed(), tun.time.skipSpeed)
  local _, wake = Sleep.bedtimeHours(world)
  local frames = 0
  while Actors.homesteader(world).asleep and frames < 100000 do
    session:update(1 / 30)
    frames = frames + 1
  end
  local hour = Calendar.now(world).hour
  T.truthy(hour >= wake and hour < wake + 2 * STEP * 24 / tun.time.dayLength, "woke on the morning tick, hour " .. hour)
  T.falsy(session:skippingNight())
  T.eq(session:effectiveSpeed(), tun.time.defaultSpeed)
  T.truthy(frames * (1 / 30) < 10, "a night takes a few real seconds to skip")
  T.falsy(session:skipNight(), "nothing to skip when awake")
end)

T.test("study: a night in bed yields the same whether fast, skipped or at 1x (per in-bed hour)", function()
  local function night(skip)
    local session = inBed(1, 0)
    local world = session.world
    world.meta.journal.notes.first_catch = { day = 1 }
    world.meta.journal.notes.fish_spoil = { day = 1 }
    Journal.study(world, "smoker")
    wakeFast(session, FRAME, skip)
    return Journal.progress(world, "smoker")
  end
  local nights = reg:get("catalog", "smoker").studyNights
  local expected = 1 / nights -- a spring night is tuning.study.nightHours in bed
  T.near(night(false), expected, 0.01)
  T.near(night(true), expected, 0.01)
end)

T.test("sleep speed: saving and loading mid-sleep keeps sleeping fast and wakes on time", function()
  local session = inBed(4, 2)
  session:update(0.5)
  T.truthy(session:sleeping())
  local data = Save.newSlotData("Loaded")
  data.meta = serialize.decode(serialize.encode(session.data.meta))
  data.run = serialize.decode(serialize.encode(session.world.state))
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local loaded = Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun })
  T.truthy(loaded:sleeping(), "still asleep after the load")
  T.eq(loaded:effectiveSpeed(), tun.time.sleepSpeed)
  T.falsy(loaded:skippingNight(), "a skip is not saved; the player asks again")
  T.eq(wakeFast(loaded, FRAME), wakeFast(session, FRAME), "both wake into the same morning")
end)

T.test("calendar: a save written with the old day length keeps its date and time of day", function()
  local world = World.new({ registry = reg, tuning = tun }, World.newState(5))
  world.state.calendar.elapsed = (3.4 - tun.time.startHour / 24) * tun.time.dayLength
  local before = Calendar.now(world)
  local old = serialize.decode(serialize.encode(world.state))
  old.calendar.dayLength = nil -- saves before D56 did not record it
  old.calendar.elapsed = old.calendar.elapsed * tun.time.legacyDayLength / tun.time.dayLength
  local loaded = World.new({ registry = reg, tuning = tun }, old)
  local after = Calendar.now(loaded)
  T.eq(after.day, before.day)
  T.near(after.hour, before.hour, 0.001)
  T.eq(loaded.state.calendar.dayLength, tun.time.dayLength)
  loaded:tick(STEP)
end)
