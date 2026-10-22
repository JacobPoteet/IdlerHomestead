-- What failed (D99, #216, #173): the rescue scene names the cold and the shelter and points at the
-- Shelter page, the first recovery adds one suggested change and the summary of what came at the homestead (D202,
-- #156), and run 2 opens with the "what carried over" cards. The failure is raised on the event bus (the real death takes most of a season); the
-- scenes, the run loop and the cards are the real ones.
return function(d)
  d:newGame({ tips = true })
  local world = d:world()
  world.meta.journal.known.sturdy_rod = true -- two loadouts unlocked, three still locked (D201)
  world.meta.journal.known.axe = true
  -- What came at the homestead (D202, #156), set in the run state as the threat and event systems keep it: the recovery
  -- summary names the night threats, the field threats, the misfortunes and the one that hurt most.
  world.state.nightthreats.tally.fox = { landed = 2, turned = 1 }
  world.state.nightthreats.tally.mice = { landed = 0, turned = 4 }
  local history = world.state.threats.history
  history[#history + 1] = { year = 1, id = "hail", struck = true, lost = 6, damaged = 2, saved = 4 }
  history[#history + 1] = { year = 1, id = "drought", struck = false, lost = 0, damaged = 0, saved = 0 }
  world.state.events.done.sprained_ankle = 1
  world.state.events.done.festering_cut = 1
  world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
  d:frames(4)
  d:frames(150, 1 / 30) -- the lights and the words fade in
  d:shot("rescue")

  d:click(40, 40) -- a tap moves on
  d:frames(4)
  d:shot("recovery") -- cause, next rung, first change, what came at you, the free study below, and the Choose land button

  d:press("Choose land") -- the plot preview (D200, #384): three plots, traits and a risk and reward tag
  d:frames(4)
  d:shot("plots")
  d:press("Plot C")
  d:frames(4)
  d:shot("plots_chosen")
  d:press("Starting kit") -- starting loadouts (D201, #386): the Journal has taught the rod and the axe, so two are open
  d:frames(4)
  d:shot("kits")
  d:press("Angler")
  d:frames(4)
  d:shot("kits_chosen")
  d:press("Done")
  d:frames(4)
  d:shot("plots_kit") -- the Starting kit button names the kit
  d:press("Done")
  d:frames(4)
  d:shot("recovery_chosen") -- the button names the chosen plot

  d:press("Head out")
  d:frames(4)
  d:advance(0.1)
  d:frames(120)
  d:shot("run2") -- the "New land, same knowledge" card
end
