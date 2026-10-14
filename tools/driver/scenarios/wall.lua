local Calendar = require("src.sim.systems.calendar")
local FRAMES, DT = 300, 0.05
return function(d)
  d:newGame()
  local world = d:world()
  d:advance(8)
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local dayLength = world.tuning.time.dayLength
  local function at(hour)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(20, DT)
  end
  for n = 1, 4 do
    world.state.weather.sky.days[n] = "clear"
  end
  for _, hour in ipairs({ 12, 18, 23 }) do
    at(hour)
    for _, zoom in ipairs({ 1, 2, 3 }) do
      cam.zoomIndex = zoom
      cam:clamp(view)
      d:frames(20, DT)
      local t0 = love.timer.getTime()
      for _ = 1, FRAMES do
        d.game:update(DT)
        love.graphics.origin()
        d.game:draw()
        love.graphics.present()
      end
      local ms = (love.timer.getTime() - t0) / FRAMES * 1000
      print(string.format("wall h%d zoom%d: %.2f ms", hour, zoom, ms))
    end
  end
end
