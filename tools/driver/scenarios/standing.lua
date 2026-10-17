-- Standing orders (B5, #349, D176): the Routine screen before the "Rules of thumb" perk is known (no block, the perk is never
-- named), then with it: Ask me everywhere, a tap on Careful for Body, Bold for Land, and the keyboard (Tab to a button, Enter).
local Events = require("src.sim.systems.events")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(0.5)
  d:pick("Routine")
  d:frames(2)
  d:shot("locked")
  d:key("escape")
  d:frames(2)

  world.meta.journal.known[world.tuning.events.ordersPerk] = true
  d:pick("Routine")
  d:frames(2)
  d:shot("unlocked")

  d:press("Careful") -- the first row is Body
  d:frames(2)
  assert(Events.orderMode(world, "body") == "careful", "a tap on Careful sets the Body rule")
  d:shot("careful_body")

  d:key("tab")
  d:key("tab")
  d:key("return")
  d:frames(2)
  d:shot("keyboard")
end
