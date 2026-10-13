-- Spoilage made visible (GDD D68, D73, #151, #183): the Pantry with each perishable's shelf life and
-- when its oldest batch spoils, the red chip when something rots tonight, the first-spoil explanation
-- card, and the one-line loss summary after the next bad night. Stock is added, aged and the night's
-- spoilage run through the sim API (the scenario cannot wait for midnight with a sleeping
-- homesteader), the screens are the real ones.
local Ledger = require("src.sim.systems.ledger")
local Spoilage = require("src.sim.systems.spoilage")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)
  Ledger.add(world, "radish", 14)
  Ledger.add(world, "creek_chub", 6)
  Spoilage.ageStock(world, "creek_chub", Spoilage.shelfLife(world, "creek_chub")) -- caught two days ago
  Ledger.add(world, "sunfish", 3)
  Ledger.add(world, "potato", 4)

  d:frames(5)
  d:shot("hud_warning") -- the red "-N" chip in the top bar: the chub rot tonight

  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_rates")
  d:key("escape")
  d:frames(3)

  -- Night one: the loss, then the explanation card the first time.
  Spoilage.daily(world)
  d:frames(3)
  d:shot("first_spoil_card")
  d:press("Got it")
  d:frames(3)

  -- Night two: the rest of the old chub go; just the summary toast. The Pantry's footer remembers it.
  Ledger.add(world, "radish", 10)
  Spoilage.daily(world)
  d:frames(3)
  d:shot("loss_summary_toast")
  -- A bigger harvest: the automatic pantry keeps only what is eaten in time, the rest is spare.
  Ledger.add(world, "radish", 25)
  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_after_loss")
  d:key("escape")
end
