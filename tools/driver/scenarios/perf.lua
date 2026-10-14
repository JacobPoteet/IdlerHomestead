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

  --- Wall-clock ms per frame with vsync off, presenting each frame, so the GPU's work is in the number.
  local function wall(label)
    d:frames(20, DT)
    local t0 = love.timer.getTime()
    for _ = 1, FRAMES do
      d.game:update(DT)
      love.graphics.origin()
      d.game:draw()
      love.graphics.present()
    end
    local ms = (love.timer.getTime() - t0) / FRAMES * 1000
    print(string.format("wall %s %s: %.2f ms/frame (%.0f fps)", d.prefix, label, ms, 1000 / ms))
    return ms
  end

  local Calendar = require("src.sim.systems.calendar")
  local v = world.tuning.visuals
  local dayLength = world.tuning.time.dayLength
  local function at(hour)
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(20, DT)
  end
  -- The lighting passes (D127-D131): all on, then each one off in turn, at dusk (shadows, beams) and at night (lights, bloom).
  local passes = {
    { "shadows", function(on) v.shadows.enabled = on end },
    { "reflections", function(on) v.reflections.enabled = on end },
    { "bloom", function(on) v.bloom.enabled = on end },
    { "sunbeams", function(on) v.sunbeams.enabled = on end },
  }
  v.sunbeams.enabled = true
  for n = 1, 4 do
    world.state.weather.sky.days[n] = "clear"
  end
  for _, hour in ipairs({ 18, 23 }) do
    at(hour)
    for _, zoom in ipairs({ 1, 3 }) do
      cam.zoomIndex = zoom
      cam:clamp(view)
      local label = string.format("h%d zoom%d", hour, zoom)
      local all = wall(label .. " all passes")
      for _, p in ipairs(passes) do
        p[2](false)
        local off = wall(label .. " without " .. p[1])
        p[2](true)
        print(string.format("cost %s %s %s: %.2f ms", d.prefix, label, p[1], all - off))
      end
    end
  end
  -- The same, as CPU submit time (what a phone's budget in tuning.perf is about), at the widest zoom at dusk.
  at(18)
  cam.zoomIndex = 1
  cam:clamp(view)
  measure("dusk zoom1 all passes")
  for _, p in ipairs(passes) do
    p[2](false)
    measure("dusk zoom1 without " .. p[1])
    p[2](true)
  end
  at(12)

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
