-- Weather is anchored to the world (#193): rain streaks and splashes scale with the camera zoom,
-- and snow pans and zooms with the land. Shots: rain at three zooms, then snow at two zooms and
-- after a pan.
local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera

  local function zoomTo(index)
    cam.zoomIndex = index
    cam:clamp(view)
    d:frames(2, 0.05)
  end

  local days = world.state.weather.sky.days
  for n, kind in ipairs({ "rain", "rain", "rain", "rain" }) do
    days[n] = kind
  end
  d:frames(90, 0.05)
  assert(Weather.isRaining(world), "should be raining")
  for _, index in ipairs({ 1, 2, 3 }) do
    zoomTo(index)
    d:shot("rain_zoom" .. index)
  end

  -- Jump the calendar into the frozen season (the snow is a pure function of the date).
  local dayLength = world.tuning.time.dayLength
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  -- Noon on the first frozen day: the snow is part-way in, so the clumps show
  world.state.calendar.elapsed = world.state.calendar.elapsed + (0.5 - Calendar.now(world).timeOfDay) * dayLength
  d:frames(90, 0.05) -- the rain eases off in the frozen season
  -- A noon find card may be up: pick the first offer and take it
  for _, label in ipairs({ "Rusty toolbox", "Old axe", "Take it" }) do
    d:tryPress(label)
    d:frames(1, 0.05)
  end
  d:frames(3, 0.05)
  zoomTo(2)
  d:shot("snow_zoom2_a")
  cam:pan(-48, -24, view)
  d:frames(2, 0.05)
  d:shot("snow_zoom2_b_panned")
  zoomTo(1)
  d:shot("snow_zoom1")
  zoomTo(3)
  d:shot("snow_zoom3")
end
