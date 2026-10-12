-- Fast sleep and skip-the-night (D56, #112): the homesteader goes to bed, time speeds up on its
-- own with a "Sleeping" banner and a countdown, "Skip night" runs the rest of the night, and the
-- morning is back at normal speed.
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

  d:press("Skip night")
  d:frames(4)
  assert(session:skippingNight(), "the skip should be running")
  d:shot("skipping")

  guard = 0
  while Actors.homesteader(world).asleep do
    d:frames(10)
    guard = guard + 1
    assert(guard < 2000, "the skip never reached morning")
  end
  d:frames(2)
  assert(session:effectiveSpeed() == session:speed(), "normal speed again in the morning")
  d:shot("morning")
end
