-- What failed (D99, #216, #173): the rescue scene names the cold and the shelter and points at the
-- Shelter page, the first recovery adds one suggested change, and run 2 opens with the "what carried
-- over" cards. The failure is raised on the event bus (the real death takes most of a season); the
-- scenes, the run loop and the cards are the real ones.
return function(d)
  d:newGame({ tips = true })
  local world = d:world()
  world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
  d:frames(4)
  d:frames(150, 1 / 30) -- the lights and the words fade in
  d:shot("rescue")

  d:click(40, 40) -- a tap moves on
  d:frames(4)
  d:shot("recovery") -- cause, next rung, first change, the free study below

  d:press("Head out")
  d:frames(4)
  d:advance(0.1)
  d:frames(120)
  d:shot("run2") -- the "New land, same knowledge" card
end
