-- Wetness maths (D124): soaking and drying run on effect-clock (game) time; wet objects dim; the frost
-- over snow keeps its contrast (#218).
local T = require("harness")
local Wetness = require("src.render.wetness")
local visuals = require("data.tuning.visuals")

local CFG = { riseSeconds = 6, drySeconds = 45, fullRain = 0.7, objectTint = { 0.8, 0.9, 1.0 } }

T.test("wet target saturates at fullRain", function()
  T.near(Wetness.target(CFG, 0), 0, 1e-9)
  T.near(Wetness.target(CFG, 0.35), 0.5, 1e-9)
  T.eq(Wetness.target(CFG, 1), 1)
end)

T.test("wetness soaks in riseSeconds and dries in drySeconds of effect time", function()
  local wet = 0
  for _ = 1, 6 do
    wet = Wetness.advance(CFG, wet, 1, 1)
  end
  T.near(wet, 1, 1e-9)
  for _ = 1, 45 do
    wet = Wetness.advance(CFG, wet, 0, 1)
  end
  T.near(wet, 0, 1e-9)
end)

T.test("a paused clock (zero step) neither soaks nor dries", function()
  T.eq(Wetness.advance(CFG, 0.6, 0, 0), 0.6)
  T.eq(Wetness.advance(CFG, 0.6, 1, 0), 0.6)
end)

T.test("drying is independent of how the same game time is sliced into frames", function()
  local a, b = 1, 1
  for _ = 1, 10 do
    a = Wetness.advance(CFG, a, 0, 1)
  end
  for _ = 1, 100 do
    b = Wetness.advance(CFG, b, 0, 0.1)
  end
  T.near(a, b, 1e-9)
end)

T.test("a faster effect step dries faster, up to the clock's cap", function()
  local EffectClock = require("src.render.effect_clock")
  local function after(speed)
    local clock, wet = EffectClock.new({ maxSpeed = 2, wrap = 3600 }), 1
    for _ = 1, 100 do
      wet = Wetness.advance(CFG, wet, 0, clock:advance(0.1, speed))
    end
    return wet
  end
  T.truthy(after(2) < after(1), "2x dries faster than 1x")
  T.near(after(4), after(2), 1e-9, "4x dries at the 2x cap")
  T.near(after(0), 1, 1e-9, "paused stays wet")
end)

T.test("object tint runs from white (dry) to the tuned tint (soaked) without allocating", function()
  local out = { 0, 0, 0 }
  T.eq(Wetness.objectTint(CFG, 0, out), out)
  T.same(out, { 1, 1, 1 })
  Wetness.objectTint(CFG, 1, out)
  T.near(out[1], 0.8, 1e-9)
  T.near(out[3], 1.0, 1e-9)
  Wetness.objectTint(CFG, 0.5, out)
  T.near(out[2], 0.95, 1e-9)
end)

T.test("frost over snow keeps its contrast against snow, which the bare-ground frost colour lacked", function()
  local snow = Wetness.luma(visuals.snowColor)
  T.truthy(snow - Wetness.luma(visuals.frostColor) < 0.1, "the old crust colour is nearly the snow's brightness")
  T.truthy(snow - Wetness.luma(visuals.frostSnowColor) >= 0.15, "the over-snow crust is clearly darker than snow")
end)
