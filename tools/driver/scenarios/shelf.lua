-- Shelf-life batches and the save stamp (D73, D74, #183): an out-of-date slot on the slot screen,
-- its "can't be loaded" prompt with Delete save / Keep it and the second confirmation; then a Pantry
-- with batches of different ages ("oldest batch spoils in N days"), the red chip and the Pantry
-- warning when a batch rots tonight. The old slot is planted in the driver's in-memory store; stock
-- is added and aged through the sim API.
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Ledger = require("src.sim.systems.ledger")
local Spoilage = require("src.sim.systems.spoilage")

return function(d)
  -- A save written before this build's SAVE_COMPAT.
  local old = Save.newSlotData("Old farm")
  old.compat = Save.SAVE_COMPAT - 1
  old.header = { playtime = 5400, year = 1, season = "summer" }
  old.run = { tick = 1 }
  d.backend.files["slot1.sav"] = serialize.encode(old)
  local before = d.backend.files["slot1.sav"]

  d:press("Play")
  d:frames(2)
  d:shot("slots_outdated")
  d:press("Play") -- the outdated card's only button
  d:frames(2)
  d:shot("outdated_prompt")
  d:press("Keep it")
  d:frames(2)
  assert(d.backend.files["slot1.sav"] == before, "Keep it must leave the file alone")
  d:press("Play")
  d:press("Delete save")
  d:frames(2)
  d:shot("delete_confirm")
  d:press("Delete")
  d:frames(2)
  assert(d.backend.files["slot1.sav"] == nil, "a confirmed delete removes the slot")
  d:shot("slot_deleted")

  -- A new game on the freed slot, with food of several ages.
  d:press("New")
  d:press("Next")
  d:press("Normal")
  d:frames(10)
  local world = d:world()
  d:advance(1)
  Ledger.add(world, "radish", 12)
  Spoilage.ageStock(world, "radish", 4) -- picked four days ago
  Ledger.add(world, "radish", 20) -- today's harvest: a second batch
  Ledger.add(world, "egg", 6)
  Spoilage.ageStock(world, "egg", 9)
  Ledger.add(world, "potato", 8)
  Ledger.add(world, "sunfish", 2)
  d:frames(5)
  d:shot("hud_no_warning") -- nothing rots tonight: no red chip
  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_ages")
  d:key("escape")
  d:frames(2)

  -- Two nights later the sunfish are at the end of their shelf life.
  Spoilage.daily(world)
  Spoilage.daily(world)
  d:frames(3)
  d:tryPress("Got it")
  d:frames(3)
  d:shot("hud_warning")
  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_warning")
  d:key("escape")
end
