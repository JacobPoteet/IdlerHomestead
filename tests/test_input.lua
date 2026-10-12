-- Gesture recognition, driven with a fake app that records emitted actions.
local T = require("harness")
local Input = require("src.core.input")
local tuning = require("src.core.tuning").load()

local function setup()
  local actions = {}
  local app = {
    view = { w = 640, h = 360, scale = 2 },
    toVirtual = function(_, x, y)
      return x / 2, y / 2
    end,
    action = function(_, name, data)
      actions[#actions + 1] = { name = name, data = data }
    end,
  }
  return Input.new(app, tuning), actions
end

local function names(actions)
  local out = {}
  for _, a in ipairs(actions) do
    out[#out + 1] = a.name
  end
  return table.concat(out, ",")
end

T.test("input: click becomes press, release, select (virtual coords)", function()
  local input, actions = setup()
  input:mousepressed(100, 60, 1, false)
  input:mousereleased(100, 60, 1, false)
  T.eq(names(actions), "press,release,select")
  T.eq(actions[3].data.x, 50)
  T.eq(actions[3].data.y, 30)
end)

T.test("input: drag pans and does not select", function()
  local input, actions = setup()
  input:mousepressed(100, 100, 1, false)
  input:mousemoved(140, 100, 0, 0, false)
  input:mousemoved(160, 120, 0, 0, false)
  input:mousereleased(160, 120, 1, false)
  T.eq(names(actions), "press,pan,pan,release")
  T.eq(actions[3].data.dx, 10)
  T.eq(actions[3].data.dy, 10)
end)

T.test("input: tiny jitter under the threshold still selects", function()
  local input, actions = setup()
  input:touchpressed(1, 100, 100)
  input:touchmoved(1, 102, 101)
  input:touchreleased(1, 102, 101)
  T.eq(names(actions), "press,release,select")
end)

T.test("input: long-press fires context once, no select", function()
  local input, actions = setup()
  input:touchpressed(1, 100, 100)
  input.pointer.startTime = input.pointer.startTime - tuning.input.longPressTime - 0.01
  input:update(0)
  input:update(0)
  input:touchreleased(1, 100, 100)
  T.eq(names(actions), "press,context,release")
end)

T.test("input: right click is context", function()
  local input, actions = setup()
  input:mousepressed(10, 10, 2, false)
  input:mousereleased(10, 10, 2, false)
  T.eq(names(actions), "context")
end)

T.test("input: two-finger pinch zooms and cancels the tap", function()
  local input, actions = setup()
  input:touchpressed(1, 300, 200)
  input:touchpressed(2, 340, 200)
  local spread = 40 * tuning.camera.pinchStepRatio + 2
  input:touchmoved(2, 300 + spread, 200)
  input:touchreleased(2, 300 + spread, 200)
  input:touchreleased(1, 300, 200)
  local zooms, selects = 0, 0
  for _, a in ipairs(actions) do
    if a.name == "zoom" then
      zooms = zooms + 1
      T.eq(a.data.steps, 1)
    elseif a.name == "select" then
      selects = selects + 1
    end
  end
  T.eq(zooms, 1)
  T.eq(selects, 0)
end)

T.test("input: mouse events synthesized from touch are ignored", function()
  local input, actions = setup()
  input:mousepressed(10, 10, 1, true)
  input:mousereleased(10, 10, 1, true)
  T.eq(#actions, 0)
end)

T.test("input: escape cancels; any input resets idle time", function()
  local input, actions = setup()
  input.lastActivity = input.lastActivity - 100
  T.truthy(input:idleSeconds() >= 100)
  input:keypressed("escape")
  T.eq(names(actions), "cancel")
  T.truthy(input:idleSeconds() < 1)
end)
