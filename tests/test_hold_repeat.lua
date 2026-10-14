-- Hold-to-repeat on steppers (D119, #201): the pure timing, the live tuning, and the stepper rules
-- the Pantry and the truck load use (clamping, no extra tap step after a hold).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local HoldRepeat = require("src.ui.hold_repeat")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Food = require("src.sim.systems.food")

local cfg = { delay = 0.5, rate = 10, stageTicks = 3, stageUnits = { 1, 5, 10 } }

T.test("hold repeat: nothing before the delay, then rate per second", function()
  T.eq(HoldRepeat.count(0, cfg), 0)
  T.eq(HoldRepeat.count(0.49, cfg), 0)
  T.eq(HoldRepeat.count(0.5, cfg), 1)
  T.eq(HoldRepeat.count(0.59, cfg), 1)
  T.eq(HoldRepeat.count(0.61, cfg), 2)
  T.eq(HoldRepeat.count(1.5, cfg), 11)
end)

T.test("hold repeat: the step grows by stage and the last stage holds", function()
  local want = { 1, 1, 1, 5, 5, 5, 10, 10, 10, 10 }
  for k, units in ipairs(want) do
    T.eq(HoldRepeat.unitsAt(k, cfg), units)
  end
end)

T.test("hold repeat: units over a window do not depend on how the frames slice it", function()
  local function run(dt, total)
    local sum, t = 0, 0
    for _ = 1, math.floor(total / dt + 0.5) do
      sum = sum + HoldRepeat.units(t, t + dt, cfg)
      t = t + dt
    end
    return sum
  end
  local direct = HoldRepeat.units(0, 1.5, cfg)
  T.eq(direct, 3 * 1 + 3 * 5 + 5 * 10) -- 11 repeats: 3 at 1, 3 at 5, 5 at 10
  T.eq(run(1 / 20, 1.5), direct)
  T.eq(run(0.25, 1.5), direct)
  T.eq(HoldRepeat.units(0.2, 0.4, cfg), 0)
end)

T.test("hold repeat: the shipped tuning reaches 120 within a few seconds", function()
  local ui = tuningLoader.load().ui.holdRepeat
  T.truthy(ui.delay > 0 and ui.rate > 0 and ui.stageTicks >= 1 and #ui.stageUnits >= 2)
  T.eq(ui.stageUnits[1], 1, "a short hold starts at one unit, like a tap")
  local t, total = 0, 0
  while total < 120 and t < 10 do
    total = total + HoldRepeat.units(t, t + 1 / 60, ui)
    t = t + 1 / 60
  end
  T.truthy(total >= 120 and t < 4, "120 takes " .. t .. "s")
end)

T.test("keep stepper clamps at zero and the top", function()
  local tun = tuningLoader.load()
  local world = World.new({ registry = Registry.new():loadAll(), tuning = tun }, World.newState(1))
  Food.setKeep(world, "radish", -45)
  T.eq(Food.keeps(world).radish, 0)
  Food.setKeep(world, "radish", tun.food.maxKeep + 500)
  T.eq(Food.keeps(world).radish, tun.food.maxKeep)
end)

T.test("a button with onRepeat: tap steps once, a hold repeats and swallows the tap", function()
  local Buttons = require("src.ui.buttons")
  local ui = tuningLoader.load().ui.holdRepeat
  local taps, units = 0, 0
  local set = Buttons.new(0)
  local function build()
    set:clear()
    set:add({
      x = 0, y = 0, w = 30, h = 30, label = "+",
      onPress = function() taps = taps + 1 end,
      onRepeat = function(n) units = units + n end,
    })
  end
  build()
  local at = { x = 5, y = 5 }
  -- A quick tap.
  set:action("press", at)
  set:update(0.1, ui)
  set:action("release", at)
  set:action("select", at)
  T.eq(taps, 1)
  T.eq(units, 0)
  -- A hold past the delay: repeats fire, a relayout in the middle keeps the hold, release adds no tap.
  set:action("press", at)
  for _ = 1, 40 do
    set:update(1 / 20, ui)
    build()
  end
  T.truthy(units > 5, "repeats fired")
  set:action("release", at)
  set:action("select", at)
  T.eq(taps, 1, "no extra tap after a hold")
  -- The next plain tap works again.
  set:action("press", at)
  set:action("release", at)
  set:action("select", at)
  T.eq(taps, 2)
end)
