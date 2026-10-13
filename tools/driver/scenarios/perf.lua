-- Frame-cost probe (#19, D103): the CPU time a busy homestead frame takes to update and to submit,
-- at each zoom, in clear weather and in rain, read from the same probes the F3 overlay shows
-- (src/core/perf.lua). Prints one line per case; takes no screenshots. The GPU's own time is not
-- included (draw submission returns before the GPU is done), so on a phone also watch the overlay's
-- FPS. Use `size=desktop`, `size=phone`, `size=landscape` to compare view sizes.
local Perf = require("src.core.perf")

local FRAMES = 150
local DT = 0.05 -- one sim tick per frame at 1x

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(8)
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local budget = world.tuning.perf

  local function measure(label)
    d:frames(20, DT) -- settle: shaders compiled, caches warm
    Perf.enabled = true
    Perf.window = FRAMES
    Perf.reset()
    for _ = 1, FRAMES do
      d.game:update(DT)
      love.graphics.origin()
      d.game:draw()
      Perf.endFrame()
    end
    local s = Perf.summary()
    Perf.enabled = false
    print(
      string.format(
        "perf %s %s: sim %.3f ms/tick, update %.2f ms, draw %.2f ms (worst %.2f), budget draw %.1f",
        d.prefix,
        label,
        s.tickMs,
        s.updateMs,
        s.drawMs,
        s.worstDrawMs,
        budget.drawMs
      )
    )
  end

  local days = world.state.weather.sky.days
  for _, weather in ipairs({ "clear", "rain" }) do
    for n = 1, 4 do
      days[n] = weather
    end
    d:frames(60, DT)
    for index = 1, #cam.zoomLevels do
      cam.zoomIndex = index
      cam:clamp(view)
      measure(weather .. " zoom" .. index)
    end
  end
end
