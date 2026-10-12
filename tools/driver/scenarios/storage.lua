-- Full stores (D59, D60): the red firewood chip and "Full" pill, a tap refused because a store is
-- full (names the store), and a paid order held at the gate with its refund button in the Catalog.
-- The scenario tightens the stores directly (storage buildings are not built yet), then plays through
-- the real HUD and input.
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)

  -- 1. A full firewood store: the chip turns red and a pill names it.
  Ledger.add(world, "firewood", Ledger.capacity(world, "firewood"))
  d:frames(3)
  d:shot("full_chip")

  -- 2. Tap a rock while the stone store has no room for a rock's biggest yield.
  Ledger.setCapacity(world, "stone", Ledger.get(world, "stone"))
  local tx, ty = d:nearestObject({ rock = true })
  assert(tx, "no rock on the map")
  d:clickTile(tx, ty)
  d:frames(2)
  assert(world.state.actors[1].order == nil, "the tap should have been refused")
  d:shot("refused_tap")

  -- 3. A paid order that falls due with no room waits at the gate.
  Ledger.add(world, "money", 40)
  assert(Market.order(world, "radish_seeds"))
  Ledger.setCapacity(world, "seed_radish", Ledger.get(world, "seed_radish") + 2)
  local hours = 0
  while #Market.heldOrders(world) == 0 and hours < 40 do
    d:advance(1)
    hours = hours + 1
  end
  assert(#Market.heldOrders(world) == 1, "the order was never held")
  local refund = "Refund $" .. Market.heldOrders(world)[1].paid
  d:scene().toast = nil
  d:frames(3)
  d:shot("held_hud")
  d:press("Catalog")
  d:frames(2)
  d:shot("held_catalog")
  d:press(refund)
  d:frames(2)
  assert(#world.state.market.orders == 0, "the refund did not cancel the order")
  d:shot("refunded")
end
