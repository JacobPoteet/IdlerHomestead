-- Early money made visible (GDD D88, #161): the first junk cleared brings a "where money comes from"
-- card, and the Catalog says how to earn when money is under its cheapest order. Then the starter
-- field (#137): the toast when the routine plans it, and the compact block it lays out.
return function(d)
  d:newGame({ tips = true })
  local world = d:world()
  d:frames(80)
  d:press("Got it") -- the welcome card

  -- The first junk pile cleared: the money card.
  world.events:emit("object.cleared", { object = "junk", tile = 1, yields = { money = 3 } })
  d:advance(2)
  d:press("Got it") -- the plant card comes first (content order); the money card waits out the gap
  d:advance(2)
  d:shot("card")
  d:press("Got it")
  d:frames(3)

  -- The Catalog once the starting $6 is spent (money under the cheapest order): the line says how to earn.
  local Ledger = require("src.sim.systems.ledger")
  Ledger.remove(world, "money", Ledger.get(world, "money"), "test")
  d:pick("Catalog")
  d:frames(3)
  d:shot("catalog")
  d:key("escape")
  d:frames(3)
end
