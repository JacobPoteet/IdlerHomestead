-- A find (GDD §8.4): the pick-1-of-3 modal, a card selected, and the toast after taking it.
-- The offer is queued through the sim (Finds.offer); the modal opens by itself on the homestead.
local Finds = require("src.sim.systems.finds")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)
  Finds.offer(world)
  d:frames(3)
  d:shot("offer")
  local card = d:scene().cards[2]
  d:click(card.x + card.w / 2, card.y + card.h / 2)
  d:frames(2)
  d:shot("selected")
  d:press("Take it")
  d:frames(2)
  d:shot("taken_toast")
end
