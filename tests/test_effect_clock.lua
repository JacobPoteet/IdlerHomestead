-- Effect clock (D97): world effects follow game speed and pause; UI time stays real; no jumps.
local T = require("harness")
local EffectClock = require("src.render.effect_clock")

local CFG = { maxSpeed = 4, wrap = 3600 }

T.test("effect clock advances by dt times speed and freezes at 0", function()
  local c = EffectClock.new(CFG)
  T.near(c:advance(0.5, 1), 0.5, 1e-9)
  T.near(c:advance(0.5, 2), 1.0, 1e-9)
  T.near(c.world, 1.5, 1e-9)
  local before = c.world
  T.eq(c:advance(1, 0), 0, "paused takes no step")
  T.eq(c.world, before, "world time stands still while paused")
  T.near(c.real, 2.0, 1e-9, "real time kept running")
end)

T.test("effect clock caps the speed so a night skip does not strobe", function()
  local c = EffectClock.new(CFG)
  T.near(c:advance(1, 8), 4, 1e-9)
  T.near(c:advance(1, 60), 4, 1e-9)
end)

T.test("effect clock changes rate, never value, when speed switches", function()
  local c = EffectClock.new(CFG)
  c:advance(0.016, 1)
  local a = c.world
  c:advance(0, 4)
  T.eq(c.world, a, "a speed change alone moves nothing")
  c:advance(0, 0)
  T.eq(c.world, a, "pausing alone moves nothing")
  c:advance(0.016, 4)
  T.near(c.world, a + 0.064, 1e-9)
end)

T.test("effect clock treats a missing speed as 1 and wraps", function()
  local c = EffectClock.new(CFG)
  T.near(c:advance(2), 2, 1e-9)
  c:advance(3599, 1)
  T.near(c.world, 1, 1e-6)
end)

T.test("effect clock: with the shipped tuning 4x play and 8x sleep run effects at the 2x rate (#265)", function()
  local cfg = require("src.core.tuning").load().visuals.effectClock
  local function rate(speed)
    local c = EffectClock.new(cfg)
    return c:advance(1, speed)
  end
  T.near(rate(1), 1, 1e-9)
  T.near(rate(2), 2, 1e-9)
  T.near(rate(4), rate(2), 1e-9, "4x looks like 2x")
  T.near(rate(8), rate(2), 1e-9, "sleep looks like 2x")
  T.eq(rate(0), 0)
end)
