-- Sun shadows: the same yard at dawn, mid-morning, noon, late afternoon and dusk (the cast shadows swing
-- from west to east and shorten at noon), under cloud, and at night (only the contact shadows remain).
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(2)
  for _ = 1, 3 do -- a find popup can open on any day: take the first card
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end
  local scene, view = d:scene(), d.game.app.view
  local tile = world.tuning.display.tileSize
  local tx, ty = Grid.coords(world.state.grid, world.state.land.truck)
  scene.camera.zoomIndex = 3
  scene.camera:centerOn((tx - 0.5) * tile, (ty - 0.5) * tile, view)
  scene.camera:clamp(view)
  local dayLength = world.tuning.time.dayLength
  local function at(hour)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(40, 0.05)
  end
  local days = world.state.weather.sky.days
  for n = 1, 4 do
    days[n] = "clear"
  end
  for _, hour in ipairs({ 7.5, 10, 12.5, 15.5, 18 }) do
    at(hour)
    d:shot(("sun_%04.1f"):format(hour))
  end
  for n = 1, 4 do
    days[n] = "cloudy"
  end
  at(12.5)
  d:shot("cloudy")
  for n = 1, 4 do
    days[n] = "clear"
  end
  at(23)
  d:shot("night")
end
