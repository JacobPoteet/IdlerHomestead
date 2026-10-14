-- Fast sleep (D56, #112): the homesteader goes to bed, time speeds up on its own with a "Sleeping"
-- banner and a countdown, and the morning is back at normal speed. There is no skip control (D105).
local Actors = require("src.sim.systems.actors")

return function(d)
  d:newGame()
  local world = d:world()
  local session = d:scene().session
  d:setSpeed(4)
  local guard = 0
  while not Actors.homesteader(world).asleep do
    d:advance(1)
    guard = guard + 1
    assert(guard < 30, "the homesteader never went to bed")
  end
  d:advance(2) -- a couple of hours into the night
  assert(session:effectiveSpeed() > session:speed(), "sleep should run faster than the chosen speed")
  d:shot("sleeping")

  guard = 0
  while Actors.homesteader(world).asleep do
    d:frames(10)
    guard = guard + 1
    assert(guard < 2000, "sleep never reached morning")
  end
  d:frames(2)
  assert(session:effectiveSpeed() == session:speed(), "normal speed again in the morning")
  d:shot("morning")
end
