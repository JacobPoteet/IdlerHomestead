-- Statuses (D166, #345, docs/PLAN_DEPTH.md §7, src/sim/systems/status.lua): families escalate and never stack, the
-- cap holds, work speed has a floor, durations run out, and each modifier reaches the system that reads it.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Shelter = require("src.sim.systems.shelter")
local Sleep = require("src.sim.systems.sleep")
local Status = require("src.sim.systems.status")
local Stats = require("src.sim.stats")
local Wardrobe = require("src.sim.systems.wardrobe")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24
local cfg = tun.status

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function summerDay()
  for n, season in ipairs(tun.time.seasons) do
    if season == "summer" then
      return (n - 1) * tun.time.daysPerSeason + 2
    end
  end
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
  end
end

-- Tick across the next midnight (the new day: the night's draw, then the statuses count down).
local function acrossMidnight(world)
  local now = require("src.sim.systems.calendar").now(world)
  setTime(world, now.day, 23.99)
  for _ = 1, 20 do
    world:tick(STEP)
  end
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

local function ids(world)
  local out = {}
  for i, s in ipairs(Status.active(world)) do
    out[i] = s.id
  end
  return table.concat(out, ",")
end

-- Content ---------------------------------------------------------------------------------------------

T.test("status: the content is consistent and every modifier hook is covered", function()
  local covered = {}
  local byFamily = {}
  for _, d in ipairs(reg:all("statuses")) do
    T.truthy(d.severity >= 1)
    T.truthy(d.duration == nil or d.duration >= 1, d.id .. " lasts at least a day")
    T.truthy(d.clearedBy == "time" or d.clearedBy == "rest" or d.clearedBy == "item", d.id .. " clearedBy")
    if d.clearedBy == "time" then
      T.truthy(d.duration, d.id .. ": cleared by time, so it has a duration")
    end
    for name, value in pairs(d.modifiers) do
      T.truthy(Status.isModifier(name), d.id .. " names the unknown modifier " .. name)
      T.truthy(type(value) == "number" and value > 0, d.id .. "." .. name)
      covered[name] = true
    end
    if d.escalatesTo then
      local nextDef = reg:get("statuses", d.escalatesTo)
      T.eq(nextDef.family, d.family, d.id .. " escalates within its family")
      T.eq(nextDef.severity, d.severity + 1, d.id .. " escalates one step")
    end
    byFamily[d.family] = byFamily[d.family] or {}
    byFamily[d.family][d.severity] = d
  end
  for _, name in ipairs({
    "workSpeed",
    "fallChance",
    "carryCapacity",
    "conditionRecovery",
    "conditionDrain",
    "studySpeed",
    "warmthNeed",
    "waterNeed",
  }) do
    T.truthy(covered[name], "some status carries " .. name)
  end
  T.eq(#byFamily.ankle, 3, "the ankle family has three severities")
end)

T.test("status: a new run has none, and nothing changes while none is active", function()
  local world = newWorld()
  T.eq(Status.count(world), 0)
  T.eq(#Status.active(world), 0)
  for _, name in ipairs({ "workSpeed", "fallChance", "carryCapacity", "conditionRecovery", "studySpeed" }) do
    T.eq(Status.modifier(world, name), 1, name .. " is exactly 1")
  end
  T.eq(Status.modifier(world, "conditionDrain"), 0)
  T.eq(Needs.waterNeeded(world), tun.needs.dailyWater)
  T.eq(Water.bucketCapacity(world), tun.actors.bucketCapacity)
  T.eq(Actors.fallFactor(world), 1)
  T.eq(world.state.status.active[1], nil)
end)

-- Escalation ------------------------------------------------------------------------------------------

T.test("status: a family escalates to its cap and never stacks", function()
  local world = newWorld()
  local applied = collect(world, "status.applied")
  local cleared = collect(world, "status.cleared")
  local kind, now = Status.apply(world, "ankle_1")
  T.eq(kind, "new")
  T.eq(now.id, "ankle_1")
  T.eq(ids(world), "ankle_1")
  T.eq(Status.apply(world, "ankle_1"), "escalated", "a second event of the family raises it")
  T.eq(ids(world), "ankle_2")
  T.eq(applied[2].from, "ankle_1")
  T.eq(applied[2].id, "ankle_2")
  T.eq(applied[2].severity, 2)
  T.eq(applied[2].family, "ankle")
  T.eq(Status.apply(world, "ankle_1"), "escalated")
  T.eq(ids(world), "ankle_3")
  local kind3 = Status.apply(world, "ankle_1")
  T.eq(kind3, "renewed", "at the cap only the time is renewed")
  T.eq(ids(world), "ankle_3")
  T.eq(Status.count(world), 1, "one ankle, never three")
  T.eq(#cleared, 0, "escalation is not a clearing")
  T.eq(applied[1].kind, "new")
  T.eq(applied[4].kind, "renewed")
end)

T.test("status: a one-off status of a family never escalates the active one, it only renews", function()
  -- The ignore outcome of the fever (chill) shares the fever family: ignoring must not turn an infection into the flu.
  local world = newWorld()
  Status.apply(world, "infection")
  T.eq(Status.apply(world, "chill"), "renewed")
  T.eq(ids(world), "infection", "the chill leaves the infection as it is")
  T.eq(Status.get(world, "infection").left, reg:get("statuses", "infection").duration)
  Status.clear(world, "infection")
  Status.apply(world, "fever")
  T.eq(Status.apply(world, "chill"), "renewed")
  T.eq(ids(world), "fever")
  Status.apply(world, "fever") -- a second fever is a stage of the chain: it still escalates
  T.eq(ids(world), "flu")
  T.eq(Status.apply(world, "chill"), "renewed")
  T.eq(ids(world), "flu", "and the flu stays the flu")
  -- Whatever the severity, no status without an `escalatesTo` changes another of its family.
  for _, active in ipairs(reg:all("statuses")) do
    for _, applied in ipairs(reg:all("statuses")) do
      if applied.family == active.family and not applied.escalatesTo and applied.severity <= active.severity then
        T.eq(Status.resolve(world, active.id, applied.id), active.id, applied.id .. " on " .. active.id)
      end
    end
  end
end)

T.test("status: applying a worse severity of an active family takes the worse one", function()
  local world = newWorld()
  Status.apply(world, "ankle_1")
  T.eq(Status.apply(world, "ankle_3"), "escalated")
  T.eq(ids(world), "ankle_3")
  T.eq(Status.get(world, "ankle_3").left, reg:get("statuses", "ankle_3").duration)
end)

T.test("status: renewing keeps the longer time", function()
  local world = newWorld()
  Status.apply(world, "back")
  acrossMidnight(world)
  local before = Status.get(world, "back").left
  T.eq(before, reg:get("statuses", "back").duration - 1)
  T.eq(Status.apply(world, "back"), "renewed")
  T.eq(Status.get(world, "back").left, reg:get("statuses", "back").duration)
end)

-- The cap ---------------------------------------------------------------------------------------------

T.test("status: different families coexist up to the cap, and a full list only replaces the shortest-lived", function()
  T.eq(cfg.maxActiveStatuses, 3)
  local world = newWorld()
  local cleared = collect(world, "status.cleared")
  Status.apply(world, "ankle_1") -- 1 day
  Status.apply(world, "fever") -- 3 days
  Status.apply(world, "back") -- 4 days
  T.eq(ids(world), "ankle_1,fever,back")
  T.eq(Status.count(world), Status.maxActive(world))
  -- Shorter than everything: dropped.
  local kind, now = Status.apply(world, "burn") -- 3 days, longer than ankle_1's 1
  T.eq(kind, "new", "lasts longer than the 1 day ankle: it replaces it")
  T.eq(now.id, "burn")
  T.eq(ids(world), "fever,back,burn")
  T.eq(cleared[1].id, "ankle_1")
  T.eq(cleared[1].reason, "replaced")
  -- Nothing left that a 1-day status outlasts.
  local dropped = Status.apply(world, "ankle_1")
  T.eq(dropped, "dropped")
  T.eq(ids(world), "fever,back,burn")
  T.eq(Status.count(world), 3, "never a fourth")
  -- An open-ended status outlasts any timed one.
  T.eq(Status.apply(world, "tired"), "new")
  T.eq(Status.count(world), 3)
  T.truthy(Status.has(world, "tired"))
  -- A second event of a family already active still escalates when the list is full.
  T.eq(Status.apply(world, "burn"), "renewed")
  T.eq(Status.count(world), 3)
end)

-- Floors ----------------------------------------------------------------------------------------------

T.test("status: work speed never goes under the floor", function()
  local world = newWorld()
  Status.apply(world, "ankle_1") -- 0.5
  Status.apply(world, "tired") -- 0.9
  T.truthy(0.5 * 0.9 > cfg.minWorkSpeed)
  T.near(Status.modifier(world, "workSpeed"), 0.5 * 0.9, 1e-9)
  -- Squeeze it under the floor with a content table of heavy modifiers.
  local floorWorld = newWorld()
  local mods = reg:get("statuses", "ankle_3").modifiers
  local old = mods.workSpeed
  mods.workSpeed = 0.2
  Status.apply(floorWorld, "ankle_3")
  Status.apply(floorWorld, "fever")
  T.eq(Status.modifier(floorWorld, "workSpeed"), cfg.minWorkSpeed)
  mods.workSpeed = old
end)

T.test("status: a heavy injury still leaves the homesteader working, never stuck", function()
  local world = newWorld()
  local hs = Actors.homesteader(world)
  hs.job = { task = "till", target = world.state.land.spawn, path = {}, progress = 0, ordered = true }
  local base = Actors.progress(world, hs).remaining
  Status.apply(world, "ankle_3")
  Status.apply(world, "fever")
  Status.apply(world, "tired")
  local slow = Actors.progress(world, hs).remaining
  hs.job = nil
  T.truthy(slow > base)
  T.truthy(slow <= base / cfg.minWorkSpeed + 1e-9, "no slower than the floor allows")
end)

T.test("status: the drain never takes Condition under its floor", function()
  local world = newWorld()
  world.state.needs.condition = 3
  local mods = reg:get("statuses", "burn").modifiers
  mods.conditionDrain = 1 -- a drain of 1 a day, whatever the content says
  Status.apply(world, "burn")
  Needs.daily(world)
  T.truthy(Needs.condition(world) >= cfg.drainFloor, "the drain stopped at the floor")
  world.state.needs.condition = cfg.drainFloor
  Needs.daily(world)
  T.truthy(Needs.condition(world) >= cfg.drainFloor)
  mods.conditionDrain = nil
end)

-- Expiry and clearing ---------------------------------------------------------------------------------

T.test("status: a duration counts down after each night's draw and the status ends", function()
  local world = newWorld()
  local cleared = collect(world, "status.cleared")
  Status.apply(world, "ankle_2") -- 3 days
  local days = reg:get("statuses", "ankle_2").duration
  T.eq(Status.get(world, "ankle_2").left, days)
  for n = 1, days - 1 do
    acrossMidnight(world)
    T.eq(Status.get(world, "ankle_2").left, days - n)
  end
  T.eq(#cleared, 0)
  acrossMidnight(world)
  T.falsy(Status.has(world, "ankle_2"), "gone")
  T.eq(#cleared, 1)
  T.eq(cleared[1].id, "ankle_2")
  T.eq(cleared[1].reason, "expired")
  T.eq(Status.modifier(world, "workSpeed"), 1, "its effect goes with it")
end)

T.test("status: a one day status still shapes the night it was applied on", function()
  local world = newWorld()
  setTime(world, 1, 12)
  Status.apply(world, "ankle_1")
  local seen
  world.events:on("needs.ate", function()
    seen = Status.has(world, "ankle_1") -- the draw runs before the count-down
  end)
  acrossMidnight(world)
  T.truthy(seen, "active during the draw")
  T.falsy(Status.has(world, "ankle_1"), "gone the next morning")
end)

T.test("status: an open-ended status lasts until something clears it", function()
  local world = newWorld()
  Status.apply(world, "tired")
  T.eq(Status.get(world, "tired").left, nil)
  for _ = 1, 3 do
    acrossMidnight(world)
  end
  T.truthy(Status.has(world, "tired"), "days do not end it")
end)

T.test("status: rest and items clear what they cure; clear and clearFamily end one", function()
  local world = newWorld()
  local cleared = collect(world, "status.cleared")
  Status.apply(world, "tired") -- rest
  Status.apply(world, "burn") -- item
  Status.apply(world, "back") -- time
  T.eq(Status.clearBy(world, "rest"), 1)
  T.eq(ids(world), "burn,back")
  T.eq(cleared[1].reason, "rest")
  T.eq(Status.clearBy(world, "item"), 1)
  T.eq(cleared[2].reason, "item")
  T.eq(Status.clearBy(world, "rest"), 0)
  T.eq(ids(world), "back", "time is not cured by either")
  T.truthy(Status.clearFamily(world, "back", "test"))
  T.eq(cleared[3].reason, "test")
  T.falsy(Status.clear(world, "back"))
  T.eq(Status.count(world), 0)
end)

-- The modifier hooks ------------------------------------------------------------------------------------

T.test("status: modifiers multiply across families, conditionDrain adds", function()
  local world = newWorld()
  Status.apply(world, "fever") -- 0.6
  Status.apply(world, "back") -- carry only
  T.near(Status.modifier(world, "workSpeed"), 0.6, 1e-9)
  T.near(Stats.factor(world, "workSpeed"), 0.6, 1e-9)
  T.eq(Status.modifier(world, "fallChance"), 1, "a modifier no status names is 1")
  Status.apply(world, "burn") -- 0.8
  T.near(Status.modifier(world, "workSpeed"), 0.6 * 0.8, 1e-9)
  T.eq(Status.modifier(world, "conditionDrain"), 0)
  Status.apply(world, "fever") -- a second one of the family: the flu, 0.5 and a point of Condition a day
  T.near(Status.modifier(world, "workSpeed"), 0.5 * 0.8, 1e-9)
  T.eq(Status.modifier(world, "conditionDrain"), 1)
  T.truthy(pcall(Status.modifier, world, "nonsense") == false)
end)

T.test("status hook: work speed slows the homesteader and composes with the wardrobe", function()
  local function remaining(withStatus, outfit)
    local world = newWorld()
    for _, def in ipairs(reg:all("garments")) do
      Wardrobe.grant(world, def.id)
    end
    if outfit then
      T.truthy(Wardrobe.wear(world, outfit))
    end
    if withStatus then
      Status.apply(world, "fever") -- workSpeed 0.6
    end
    local hs = Actors.homesteader(world)
    hs.job = { task = "till", target = world.state.land.spawn, path = {}, progress = 0, ordered = true }
    local p = Actors.progress(world, hs)
    hs.job = nil
    return p.remaining, Wardrobe.workBonus(world)
  end
  local light = {}
  for _, slot in ipairs(tun.wardrobe.slots) do
    for _, def in ipairs(reg:all("garments")) do
      if def.slot == slot and def.class == "light" and not light[slot] then
        light[slot] = def.id
      end
    end
  end
  local plain = remaining(false)
  local slow = remaining(true)
  T.near(slow, plain / 0.6, 1e-9, "the status alone")
  local lightOnly, bonus = remaining(false, light)
  T.truthy(bonus > 1)
  T.near(lightOnly, plain / bonus, 1e-9, "the wardrobe alone")
  local both = remaining(true, light)
  T.near(both, plain / (bonus * 0.6), 1e-9, "both multiply")
end)

T.test("status hook: carry capacity scales the bucket and keeps at least one watering", function()
  local world = newWorld()
  local base = Water.bucketCapacity(world)
  Status.apply(world, "back") -- 0.5
  T.eq(Water.bucketCapacity(world), math.max(1, math.floor(base * 0.5 + 0.5)))
  T.truthy(Water.bucketCapacity(world) < base)
  local tiny = newWorld()
  tiny.tuning = setmetatable(
    { actors = setmetatable({ bucketCapacity = 1 }, { __index = tun.actors }) },
    { __index = tun }
  )
  Status.apply(tiny, "back")
  T.eq(Water.bucketCapacity(tiny), 1, "never under one")
end)

T.test("status hook: fall chance is the actors' accessor", function()
  local world = newWorld()
  Status.apply(world, "ankle_2")
  T.eq(Actors.fallFactor(world), 2)
  Status.apply(world, "ankle_2") -- torn: 3
  T.eq(Actors.fallFactor(world), 3)
end)

T.test("status hook: the warmth need follows a fever (tonight, not the season-long forecast)", function()
  local function needs(withFever)
    local world = newWorld()
    setTime(world, tun.time.daysPerSeason * 3 + 2, 12) -- deep winter
    if withFever then
      Status.apply(world, "fever") -- 1.15
    end
    return Needs.warmthNeeded(world), Readiness.warmthAhead(world), world
  end
  local plain, plainAhead, w = needs(false)
  local fever, feverAhead = needs(true)
  T.truthy(plain > 0)
  T.near(fever / plain, 1.15, 1e-9)
  T.eq(feverAhead, plainAhead, "the season-long forecast ignores a passing status")
  T.near(plain, Weather.warmthNeed(w) * Shelter.nightInsulation(w), 1e-9, "no status: unchanged")
end)

T.test("status hook: the water need and the outlook follow a fever", function()
  local world = newWorld()
  Status.apply(world, "fever") -- 1.5
  T.near(Needs.waterNeeded(world), tun.needs.dailyWater * 1.5, 1e-9)
  T.near(Needs.waterOutlook(world).perDay, tun.needs.dailyWater * 1.5, 1e-9)
end)

T.test("status hook: condition recovery scales a fed, warm day; drain costs Condition", function()
  local function after(id)
    local world = newWorld()
    setTime(world, summerDay(), 12) -- no cold nights in summer
    if id then
      Status.apply(world, id)
    end
    -- A fed, watered day.
    Ledger.add(world, "brook_trout", 10)
    world.state.needs.condition = 10
    Needs.daily(world)
    return Needs.condition(world)
  end
  local base = after(nil)
  local fever = after("fever") -- recovery x0.5
  local gain = base - 10
  T.truthy(gain > 0, "a good day restores some")
  T.near(fever - 10, gain * 0.5, 1e-6)
  T.near(after("flu"), 10 + gain * 0.5 - 1, 1e-6, "the flu halves the recovery and drains a point a day")
end)

T.test("status hook: study speed scales the night's progress", function()
  local function oneNight(id)
    local world = newWorld(1)
    world.meta.journal.notes.first_catch = { day = 1 }
    world.meta.journal.notes.fish_spoil = { day = 1 }
    Journal.study(world, "smoker")
    if id then
      Status.apply(world, id)
    end
    local bed, wake = Sleep.bedtimeHours(world)
    setTime(world, 1, bed)
    run(world, HOUR * (24 - bed + wake))
    return Journal.progress(world, "smoker")
  end
  local plain = oneNight(nil)
  T.truthy(plain > 0)
  T.near(oneNight("tired") / plain, 0.8, 1e-6, "run down studies at 80%")
end)

-- State -----------------------------------------------------------------------------------------------

T.test("status: the state is plain and survives a save round trip", function()
  local world = newWorld()
  Status.apply(world, "ankle_3")
  Status.apply(world, "tired")
  acrossMidnight(world)
  local copy = serialize.decode(serialize.encode(world.state))
  local again = World.new({ registry = reg, tuning = tun }, copy)
  T.eq(ids(again), ids(world))
  T.eq(Status.get(again, "ankle_3").left, Status.get(world, "ankle_3").left)
  T.near(Status.modifier(again, "workSpeed"), Status.modifier(world, "workSpeed"), 1e-12)
end)

T.test("status: a loaded status the content no longer has is dropped", function()
  local world = newWorld()
  Status.apply(world, "back")
  local copy = serialize.decode(serialize.encode(world.state))
  copy.status.active[#copy.status.active + 1] = { id = "no_such_status", left = 2 }
  local again = World.new({ registry = reg, tuning = tun }, copy)
  T.eq(ids(again), "back")
end)
