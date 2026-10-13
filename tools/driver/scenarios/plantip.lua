-- A tip card holds game time (D92, #230): while a first-time tip card is up the clock, the speed button
-- (Paused) and the routine takeover wait; closing it brings the chosen speed back.
return function(d)
  d:newGame({ tips = true })
  local session = d.game.app.ctx.session
  local world = d:world()
  d:frames(80) -- the welcome card is due a few game seconds in
  assert(d:scene().card, "the welcome card is up")
  d:shot("card_paused") -- speed button reads Paused, the badge says Paused
  local before = world.state.tick
  d:frames(120)
  assert(world.state.tick == before, "no game time passes under the card")
  assert(session:speed() > 0, "the chosen speed is kept")
  d:press("Got it")
  d:frames(30)
  assert(world.state.tick > before, "time runs once the card is closed")
  d:shot("card_closed")
end
