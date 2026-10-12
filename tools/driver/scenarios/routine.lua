-- The routine survives the night (D54, #113): start it, sleep through bedtime, and find it running
-- again in the morning; then take control and let the idle hint appear.
local Actors = require("src.sim.systems.actors")
local Sleep = require("src.sim.systems.sleep")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(2)
  d:press("Start routine")
  d:advance(1)
  d:shot("on")

  -- Run through the evening into the night: the routine rests.
  local guard = 0
  while not Actors.homesteader(world).asleep do
    d:advance(1)
    guard = guard + 1
    assert(guard < 24, "the homesteader never went to bed")
  end
  d:shot("asleep")

  -- Sunrise: the routine picks itself back up without a keypress.
  guard = 0
  while Actors.homesteader(world).asleep or Sleep.isBedtime(world) do
    d:advance(1)
    guard = guard + 1
    assert(guard < 24, "the homesteader never woke")
  end
  d:advance(1)
  assert(d:scene().session:routineForced(), "the routine should resume in the morning")
  d:shot("morning")

  -- Take control (a tap hands it back), then stand idle: the hint appears.
  d:clickTile(d:homesteaderTile())
  d:setSpeed(4)
  local guard2 = 0
  while not d:scene().toast do
    d:advance(1)
    guard2 = guard2 + 1
    assert(guard2 < 12, "the idle hint never appeared")
  end
  d:shot("hint")
end
