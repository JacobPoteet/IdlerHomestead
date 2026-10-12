local T = require("harness")
local Events = require("src.core.events")
local Clock = require("src.core.clock")
local Rng = require("src.core.rng")
local serialize = require("src.core.serialize")
local strict = require("src.core.strict")

-- Events ---------------------------------------------------------------------

T.test("events: handlers receive arguments in subscription order", function()
  local bus, log = Events.new(), {}
  bus:on("x", function(a)
    log[#log + 1] = "first:" .. a
  end)
  bus:on("x", function(a)
    log[#log + 1] = "second:" .. a
  end)
  bus:emit("x", 7)
  T.same(log, { "first:7", "second:7" })
end)

T.test("events: unsubscribe during emit is safe", function()
  local bus, count = Events.new(), 0
  local off
  off = bus:on("x", function()
    count = count + 1
    off()
  end)
  bus:on("x", function()
    count = count + 10
  end)
  bus:emit("x")
  bus:emit("x")
  T.eq(count, 21)
end)

T.test("events: onAny sees every event name", function()
  local bus, names = Events.new(), {}
  bus:onAny(function(name)
    names[#names + 1] = name
  end)
  bus:emit("a")
  bus:emit("b")
  T.same(names, { "a", "b" })
end)

-- Clock ----------------------------------------------------------------------

T.test("clock: runs whole ticks and carries remainder", function()
  local clock, ticks = Clock.new({ tickRate = 10, maxTicksPerFrame = 100 }), 0
  local function onTick()
    ticks = ticks + 1
  end
  clock:advance(0.25, onTick)
  T.eq(ticks, 2)
  clock:advance(0.05, onTick)
  T.eq(ticks, 3)
end)

T.test("clock: time scale and pause", function()
  local clock, ticks = Clock.new({ tickRate = 10, maxTicksPerFrame = 100 }), 0
  local function onTick()
    ticks = ticks + 1
  end
  clock.timeScale = 4
  clock:advance(0.5, onTick)
  T.eq(ticks, 20)
  clock.paused = true
  clock:advance(1, onTick)
  T.eq(ticks, 20)
end)

T.test("clock: drops backlog beyond the per-frame cap", function()
  local clock, ticks = Clock.new({ tickRate = 10, maxTicksPerFrame = 5 }), 0
  clock:advance(10, function()
    ticks = ticks + 1
  end)
  T.eq(ticks, 5)
  T.eq(clock.accumulator, 0)
end)

-- RNG ------------------------------------------------------------------------

T.test("rng: same seed gives same sequence", function()
  local a, b = Rng.new(12345), Rng.new(12345)
  for _ = 1, 100 do
    T.eq(a:float(), b:float())
  end
end)

T.test("rng: different seeds diverge", function()
  local a, b = Rng.new(1), Rng.new(2)
  local same = 0
  for _ = 1, 50 do
    if a:float() == b:float() then
      same = same + 1
    end
  end
  T.truthy(same < 3)
end)

T.test("rng: floats in [0,1) and ints in range, roughly uniform", function()
  local r = Rng.new(99)
  local buckets = { 0, 0, 0, 0, 0, 0 }
  for _ = 1, 6000 do
    local f = r:float()
    T.truthy(f >= 0 and f < 1)
    local i = r:int(1, 6)
    buckets[i] = buckets[i] + 1
  end
  for i = 1, 6 do
    T.truthy(buckets[i] > 850 and buckets[i] < 1150, "bucket " .. i .. " = " .. buckets[i])
  end
end)

T.test("rng: state round-trips through serialization", function()
  local r = Rng.new(777)
  for _ = 1, 10 do
    r:float()
  end
  local saved = serialize.decode(serialize.encode(r.store))
  local resumed = Rng.attach(saved)
  for _ = 1, 20 do
    T.eq(resumed:float(), r:float())
  end
end)

T.test("rng: derived streams are independent and stable", function()
  local land = Rng.deriveSeed(42, "land")
  T.eq(land, Rng.deriveSeed(42, "land"))
  T.truthy(land ~= Rng.deriveSeed(42, "weather"))
end)

T.test("rng: weighted pick respects zero weights", function()
  local r = Rng.new(5)
  local items = { { id = "a", w = 0 }, { id = "b", w = 1 } }
  local function weight(it)
    return it.w
  end
  for _ = 1, 100 do
    T.eq(r:weighted(items, weight).id, "b")
  end
end)

-- Serialize ------------------------------------------------------------------

T.test("serialize: round-trips nested data", function()
  local data = {
    name = 'My "farm"\nline2',
    list = { 1, 2.5, -3, true, false },
    map = { ["with space"] = 1, ["end"] = 2, [10] = "ten" },
    nested = { deeper = { x = 0.1 } },
  }
  T.same(serialize.decode(serialize.encode(data)), data)
end)

T.test("serialize: rejects functions, cycles, non-finite numbers", function()
  T.errors(function()
    serialize.encode({ f = print })
  end, "unsupported value type")
  local t = {}
  t.self = t
  T.errors(function()
    serialize.encode(t)
  end, "cycle")
  T.errors(function()
    serialize.encode({ x = math.huge })
  end, "non-finite")
end)

T.test("serialize: decode has no access to globals and rejects bytecode", function()
  local v, err = serialize.decode("os.exit()")
  T.eq(v, nil)
  T.truthy(err)
  local v2, err2 = serialize.decode(string.dump(function() end))
  T.eq(v2, nil)
  T.truthy(err2:find("bytecode"))
end)

T.test("serialize: output is deterministic", function()
  local a = serialize.encode({ b = 1, a = 2, c = { z = 1, y = 2 } })
  local b = serialize.encode({ c = { y = 2, z = 1 }, a = 2, b = 1 })
  T.eq(a, b)
end)

-- Strict ---------------------------------------------------------------------

T.test("strict: unknown reads and new keys error, arrays untouched", function()
  local t = strict.wrap({ a = 1, sub = { b = 2 }, list = { 10, 20 } }, "cfg")
  T.eq(t.a, 1)
  T.eq(t.sub.b, 2)
  T.eq(#t.list, 2)
  T.errors(function()
    return t.missing
  end, "Unknown key 'missing' in cfg")
  T.errors(function()
    return t.sub.nope
  end, "cfg.sub")
  T.errors(function()
    t.newKey = 1
  end, "Cannot add")
  t.a = 5 -- existing keys stay tweakable
  T.eq(t.a, 5)
end)
