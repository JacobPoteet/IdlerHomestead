-- Dissolves, calm signals and weather on plates (GDD §9.4, D142, #298). The driver settles every change at once
-- so other scenarios shoot finished screens; this one lets time run to catch the middle of each dissolve (the
-- wheel, a book opening and closing, the tile card, a lens), then shoots the amber glint and the red beat, frost
-- and snow on the plates of a snowy day, and a paper book by lamplight at night with Ambient effects on and off.
local Book = require("src.scenes.book")
local Buttons = require("src.ui.buttons")
local Calendar = require("src.sim.systems.calendar")
local Motion = require("src.ui.motion")
local Plate = require("src.ui.plate")
local Signals = require("src.ui.signals")
local Text = require("src.ui.text")
local Weather = require("src.sim.systems.weather")

-- A see-through scene that draws plates with a signal each: amber, red, a pulsing button, and small plates.
local function signalScene(app)
  local buttons = Buttons.new(0)
  local scene = { opaque = false }
  function scene.draw()
    local x, y = 8, 60
    for n, kind in ipairs({ "amber", "red" }) do
      local ink, gx, gy = Motion.signal(kind, 110, 24, n)
      Plate.draw(x, y, 110, 24, { ink = ink, glintX = gx, glintY = gy })
      Text.draw(kind == "amber" and "Amber: a glint" or "Red: a slow beat", x + 8, y + 8)
      y = y + 30
    end
    local ink, gx, gy = Motion.signal("amber", 20, 20, 5)
    Plate.draw(x, y, 20, 20, { ink = ink, glintX = gx, glintY = gy })
    buttons:clear()
    buttons:add({ x = x + 30, y = y - 2, w = 90, h = 24, label = "Pulse", pulse = true })
    buttons:draw()
  end
  return scene
end

--- Run the UI clock until `ready()` holds (a glint showing, the beat at its top frame).
local function until_(d, ready)
  for _ = 1, 400 do
    if ready() then
      return
    end
    d:frames(1, 0.05)
  end
  error("the signal never came")
end

return function(d)
  d:newGame()
  local world = d:world()
  local app = d.game.app
  local scene = d:scene()
  local cfg = world.tuning.ui.motion
  d:frames(10)
  d:setSpeed(0)
  d:frames(3)
  Motion.settled = false -- let the dissolves run; every frame below is 0.05 s

  -- The wheel: a held press shows the wheel after its delay; it comes in as a stipple.
  scene:openWheel(scene.app.view.w / 2, scene.app.view.h / 2, false)
  d:frames(1)
  d:shot("wheel_in_mid")
  d:frames(6)
  d:shot("wheel_open")
  scene.wheel = nil
  scene:layout()
  d:frames(1)
  d:shot("wheel_out_mid")
  d:frames(6)

  -- A book opens, and goes: the same dither, both ways.
  Book.open(app, "ledger")
  d:frames(2)
  d:shot("book_in_mid")
  d:frames(8)
  d:shot("book_open")
  app:pop()
  d:frames(1)
  d:shot("book_out_mid")
  d:frames(8)
  assert(app:top() == scene, "the book is gone once it has dissolved away")

  -- The tile card.
  local x, y = d:homesteaderTile()
  scene.selected = (y - 1) * world.state.grid.w + x
  d:frames(1)
  d:shot("card_in_mid")
  d:frames(6)
  scene.selected = nil
  d:frames(1)
  d:shot("card_out_mid")
  d:frames(6)

  -- A lens: the Water lens dissolves over the land, and switching to Power dissolves again.
  scene:showLens("water")
  d:frames(2)
  d:shot("lens_in_mid")
  d:frames(8)
  scene:showLens("power")
  d:frames(2)
  d:shot("lens_switch_mid")
  d:frames(8)
  scene.lens:dismiss()
  d:frames(1)
  d:shot("lens_out_mid")
  d:frames(10)

  -- Reduce motion: the same open is a two-step change, nothing between.
  app.ctx.settings:set("reduceMotion", true)
  d:pressHud("ledger")
  d:frames(1)
  assert(app:top().fade:coverage() == 1, "Reduce motion opens the book in one step")
  d:shot("book_reduce_motion")
  d:pick("Close")
  d:frames(1)
  assert(#app.leaving == 0, "and closes in one step")
  app.ctx.settings:set("reduceMotion", false)
  d:frames(2)

  -- Calm signals on their own plates: the glint on an amber one, the top frame of the beat on a red one.
  local sig = signalScene(app)
  app:push(sig)
  until_(d, function()
    return Signals.glinting(Motion.time(), cfg.amber, 1)
  end)
  d:shot("amber_glint")
  until_(d, function()
    return Signals.beatFrame(Motion.time(), cfg.red) == 3
  end)
  d:shot("red_beat_top")
  until_(d, function()
    return Signals.beatFrame(Motion.time(), cfg.red) == 1
  end)
  d:shot("red_beat_rest")
  app.ctx.settings:set("reduceMotion", true)
  d:frames(1)
  d:shot("signals_reduce_motion")
  app.ctx.settings:set("reduceMotion", false)
  app:pop()
  Motion.settled = true

  -- Night: a paper book by lamplight, then with Ambient effects off.
  local dayLength = world.tuning.time.dayLength
  local function at(frac)
    local step = frac - Calendar.now(world).timeOfDay
    if step < 0 then
      step = step + 1
    end
    world.state.calendar.elapsed = world.state.calendar.elapsed + step * dayLength
    d:frames(20, 0.05)
  end
  at(0.95)
  d:pressHud("ledger")
  d:frames(3)
  d:shot("book_night")
  app:pop()
  d:frames(2)
  app.ctx.settings:set("ambientFx", false)
  d:pressHud("ledger")
  d:frames(3)
  d:shot("book_night_no_ambient")
  app:pop()
  app.ctx.settings:set("ambientFx", true)
  d:frames(2)

  -- A snowy winter day: frost from the corners and snow on the tops of the plates, never over an icon.
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  for _, label in ipairs({ "Rusty toolbox", "Old axe", "Take it" }) do
    d:tryPress(label)
    d:frames(1, 0.05)
  end
  at(0.5)
  d:shot("winter_plates")
  app.ctx.settings:set("ambientFx", false)
  d:frames(2)
  d:shot("winter_no_ambient")
  app.ctx.settings:set("ambientFx", true)
  at(0.95)
  d:shot("winter_night")
end
