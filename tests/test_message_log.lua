-- The message log (D90, #167), news held through the night (#177) and the falling-condition warning
-- (#176). The log is UI state (src/ui/message_log.lua); the held-toast routing is checked on a
-- stand-in scene wearing the homestead's own methods; the warning is sim state in systems/alerts.lua.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Alerts = require("src.sim.systems.alerts")
local MessageLog = require("src.ui.message_log")
local Homestead = require("src.scenes.homestead")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local RATE = tun.time.tickRate

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - tun.time.startHour / 24) * tun.time.dayLength
  world.state.calendar.day = day
end

local function run(world, seconds)
  for _ = 1, math.ceil(seconds * RATE) do
    world:tick(1 / RATE)
  end
end

local function stamp(at)
  return { day = 1, hour = 8, at = at or 0 }
end

-- The log ----------------------------------------------------------------------------------------

T.test("log: keeps the last N lines, newest first", function()
  local log = MessageLog.new(3, 60)
  for i = 1, 5 do
    log:add("line " .. i, stamp(i))
  end
  local lines = log:lines()
  T.eq(#lines, 3, "older lines drop off")
  T.eq(lines[1].text, "line 5")
  T.eq(lines[2].text, "line 4")
  T.eq(lines[3].text, "line 3")
end)

T.test("log: the same line twice in a row counts instead of repeating", function()
  local log = MessageLog.new(10, 60)
  log:add("Caught a perch", stamp(1))
  log:add("Caught a perch", stamp(2))
  log:add("Caught a perch", stamp(3))
  log:add("Delivered: bed", stamp(4))
  log:add("Caught a perch", stamp(5))
  local lines = log:lines()
  T.eq(#lines, 3)
  T.eq(MessageLog.label(lines[3]), "Caught a perch (x3)")
  T.eq(MessageLog.label(lines[1]), "Caught a perch", "not in a row: a new line")
end)

T.test("log: pieces of one event within the window are one line", function()
  local log = MessageLog.new(10, 60)
  log:addPart("overflow", "3 wood", "Storage full: lost %s", stamp(100))
  log:addPart("overflow", "2 stone", "Storage full: lost %s", stamp(100))
  log:addPart("overflow", "1 fish", "Storage full: lost %s", stamp(130))
  T.eq(log:size(), 1)
  T.eq(log:lines()[1].text, "Storage full: lost 3 wood, 2 stone, 1 fish")
  log:addPart("overflow", "4 wood", "Storage full: lost %s", stamp(130 + 61))
  T.eq(log:size(), 2, "after the window it is a new line")
  log:add("Something else", stamp(200))
  log:addPart("overflow", "1 wood", "Storage full: lost %s", stamp(201))
  T.eq(log:size(), 4, "another line in between breaks the group")
end)

T.test("log: lives in the table it is given, survives a save round trip and shows the same lines", function()
  local world = newWorld(3)
  local log = MessageLog.new(5, 60, world.state.log)
  log:add("Caught a perch", stamp(1))
  log:add("Caught a perch", stamp(2))
  log:addPart("overflow", "3 wood", "Storage full: lost %s", stamp(10))
  log:add("Delivered: bed", { day = 2, hour = 6.5, at = 20 })
  local loaded = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  local again = MessageLog.new(5, 60, loaded.state.log)
  T.eq(serialize.encode(again:lines()), serialize.encode(log:lines()), "the same recent log after a load")
  T.eq(MessageLog.when(again:lines()[1]), "Day 2 06:30")
  T.eq(MessageLog.label(again:lines()[3]), "Caught a perch (x2)")
  again:addPart("overflow", "x", "Storage full: lost %s", stamp(30)) -- a load can carry on
  T.eq(again:size(), 4)
end)

T.test("log: the cap holds in the saved table, and a lowered cap trims a loaded log", function()
  local store = {}
  local log = MessageLog.new(4, 60, store)
  for i = 1, 9 do
    log:add("line " .. i, stamp(i))
  end
  T.eq(#store, 4, "the saved table never grows past the cap")
  T.eq(MessageLog.new(2, 60, store):lines()[2].text, "line 8")
  T.eq(#store, 2)
end)

T.test("log: when() reads as a date and a clock", function()
  T.eq(MessageLog.when({ day = 3, hour = 6.5 }), "Day 3 06:30")
end)

-- Held toasts and the log on a stand-in scene -------------------------------------------------------

local function scene(sleeping)
  local world = newWorld(1)
  local s
  s = setmetatable({
    world = world,
    app = {
      ctx = { tuning = tun },
      top = function()
        return nil
      end,
    },
    session = {
      sleeping = function()
        return s and s.asleep
      end,
      setSpeed = function() end,
    },
    toast = nil,
    toastQueue = {},
    held = {},
    log = MessageLog.new(tun.ui.log.maxLines, tun.ui.log.coalesceSeconds),
    asleep = sleeping,
  }, Homestead)
  s.session.sleeping = function()
    return s.asleep
  end
  Homestead.subscribe(s)
  return s, world
end

T.test("log: a new run state has an empty log; a stand-in scene keeps the log in the run state", function()
  T.eq(#newWorld(1).state.log, 0)
  local s, world = scene(false)
  s.log = MessageLog.new(tun.ui.log.maxLines, tun.ui.log.coalesceSeconds, world.state.log)
  s:showToast("saved line")
  T.eq(world.state.log[#world.state.log].text, "saved line")
end)

T.test("toasts: every toast is logged once, queued or shown", function()
  local s = scene(false)
  s:showToast("one")
  s:queueToast("two")
  s:queueToast("three")
  s:urgentToast("four")
  local lines = s.log:lines()
  T.eq(#lines, 4)
  T.eq(lines[1].text, "four")
  T.eq(lines[4].text, "one")
  T.eq(s.toast.text, "four")
  T.eq(s.toastQueue[1], "one", "urgent news puts what was showing back at the head")
end)

T.test("held news: raised in the night, nothing shows until the homesteader is up, then in order", function()
  local s, world = scene(true)
  world.events:emit("weather.froze", {})
  world.events:emit("weather.coldSnap", { active = true })
  T.eq(s.toast, nil, "nothing is shown while asleep")
  T.truthy(#s.held >= 2, "the news is held (the world may add its own)")
  T.eq(s.log:size(), 0, "held news is logged when it is handed over")
  local held = #s.held
  s:releaseHeld()
  T.eq(#s.held, held, "still asleep: still held")
  s.asleep = false
  s:releaseHeld()
  T.eq(#s.held, 0)
  T.truthy(s.toast, "the first raised shows first")
  -- Everything handed over is in the log, the later news above the earlier.
  local function at(pattern)
    for i, line in ipairs(s.log:lines()) do
      if line.text:find(pattern, 1, true) then
        return i
      end
    end
  end
  T.truthy(at("creek froze") and at("Cold snap"))
  T.truthy(at("Cold snap") < at("creek froze"), "the log is newest first")
  T.eq(s.log:size(), held, "one log line per held toast")
end)

T.test("held news: unkeyed toasts are all kept, keyed ones keep the latest", function()
  local s = scene(true)
  s:newsToast("a")
  s:newsToast("a")
  s:heldToast("k", "first")
  s:heldToast("k", "second")
  T.eq(#s.held, 3)
  T.eq(s.held[3].text, "second")
  s.asleep = false
  s:releaseHeld()
  T.eq(s.log:lines()[1].text, "second")
  T.eq(MessageLog.label(s.log:lines()[2]), "a (x2)", "two identical news lines in a row log as one line with a count")
end)

T.test("held news: awake, news queues straight away behind what is showing", function()
  local s, world = scene(false)
  world.events:emit("weather.froze", {})
  T.truthy(s.toast, "shown at once")
  T.eq(#s.held, 0, "nothing is held while awake")
  local before = #s.toastQueue
  world.events:emit("weather.coldSnap", { active = false })
  T.eq(#s.toastQueue, before + 1, "queued behind what is showing")
end)

-- Falling condition (#176) ----------------------------------------------------------------------------

local function condition(world, value)
  world.state.needs.condition = value
end

T.test("falling condition: amber from the tuned drop, even while condition is high", function()
  local world = newWorld(1)
  setTime(world, 1, 12)
  condition(world, 100)
  run(world, 2) -- the first look remembers the dawn
  T.eq((Alerts.level(world, "condition")), 0)
  condition(world, 100 - tun.alerts.conditionFallDrop + 1)
  T.eq((Alerts.level(world, "condition")), 0, "a small drop is not a warning")
  condition(world, 100 - tun.alerts.conditionFallDrop)
  T.eq((Alerts.level(world, "condition")), 1, "the tuned drop is amber")
  T.truthy(100 - tun.alerts.conditionFallDrop > tun.alerts.conditionAmber, "(still well above the low threshold)")
  condition(world, 100)
  T.eq((Alerts.level(world, "condition")), 0, "recovering clears it")
  condition(world, tun.alerts.conditionRed - 1)
  T.eq((Alerts.level(world, "condition")), 2, "low is still red")
end)

T.test("falling condition: the night's loss shows through the next day and clears the day after", function()
  local world = newWorld(1)
  setTime(world, 1, 12)
  condition(world, 100)
  run(world, 2)
  local drop = tun.alerts.conditionFallDrop + 5
  -- Midnight leaves the heart lower; before dawn the reference is the last dawn.
  setTime(world, 2, 2)
  condition(world, 100 - drop)
  T.eq((Alerts.level(world, "condition")), 1)
  -- Dawn: the new dawn is remembered, the reference moves to the dawn before, so it stays amber all day.
  setTime(world, 2, 8)
  run(world, 2)
  T.eq((Alerts.level(world, "condition")), 1, "still amber after the dawn that follows the loss")
  -- A quiet night: the next dawn has the same heart, so a day later the warning is gone.
  setTime(world, 3, 2)
  T.eq((Alerts.level(world, "condition")), 0, "after midnight it is judged on the last dawn: no further loss")
  setTime(world, 3, 8)
  run(world, 2)
  T.eq((Alerts.level(world, "condition")), 0)
end)

T.test("falling condition: raises one warning per day, reusing the once-per-day-per-level rule", function()
  local world = newWorld(1)
  setTime(world, 1, 12)
  condition(world, 100)
  run(world, 2)
  local raised = {}
  world.events:on("alert.raised", function(e)
    raised[#raised + 1] = e
  end)
  condition(world, 100 - tun.alerts.conditionFallDrop - 3)
  run(world, tun.alerts.checkInterval + 0.5)
  T.eq(#raised, 1)
  T.eq(raised[1].kind, "condition")
  T.eq(raised[1].level, 1)
  condition(world, 100 - tun.alerts.conditionFallDrop - 6)
  run(world, tun.alerts.checkInterval + 0.5)
  T.eq(#raised, 1, "falling further inside the same level does not repeat it")
  condition(world, 100)
  run(world, tun.alerts.checkInterval + 0.5)
  condition(world, 100 - tun.alerts.conditionFallDrop - 3)
  run(world, tun.alerts.checkInterval + 0.5)
  T.eq(#raised, 1, "dipping again the same day is held back")
end)

T.test("falling condition: deterministic and the remembered dawn round-trips", function()
  local function play()
    local world = newWorld(7)
    setTime(world, 1, 12)
    condition(world, 90)
    run(world, 2)
    setTime(world, 2, 8)
    condition(world, 70)
    run(world, 3)
    return world
  end
  local a, b = play(), play()
  T.eq(serialize.encode(a.state.alerts), serialize.encode(b.state.alerts))
  T.eq(a.state.alerts.dawn.last, 70)
  T.eq(a.state.alerts.dawn.prior, tun.needs.conditionMax, "the dawn before is the start of the run")
  local loaded = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  T.eq(loaded.state.alerts.dawn.last, 70)
  T.eq(Alerts.conditionDrop(loaded), Alerts.conditionDrop(a))
end)
