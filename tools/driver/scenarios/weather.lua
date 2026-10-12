-- Day-to-day weather (GDD §7.1, D51): the homestead under clear, cloudy and rainy skies, a storm,
-- and the forecast pill. The scenario sets today's weather directly in the sim (the sky is
-- seeded, so a normal run would take a while to roll each one) and gives the look time to ease in.
local Weather = require("src.sim.systems.weather")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4) -- mid-morning, so the light is up
  local days = world.state.weather.sky.days

  local function sky(kinds)
    for n, kind in ipairs(kinds) do
      days[n] = kind
    end
    d:frames(90, 0.05) -- the grade and the rain ease in over a few seconds
  end

  sky({ "clear", "cloudy", "rain", "clear" })
  d:shot("clear")
  sky({ "cloudy", "rain", "clear", "windy" })
  d:shot("cloudy")
  sky({ "rain", "clear", "storm", "cloudy" })
  assert(Weather.isRaining(world), "the rain scenario should be raining")
  d:shot("rain")
  sky({ "storm", "cloudy", "clear", "clear" })
  d:shot("storm")
end
