-- The lantern (C7, #361, D191, docs/PLAN_DEPTH.md §5.3, §6.1): night gear that turns some threats aside. Owning the equipment
-- item Lantern.ITEM is all there is to it: no fuel, no lighting chore, no state. `Lantern.guard(world, threatId)` is the
-- chance it turns that threat aside, added to the threat's own guard roll beside the dog's (raiders, animals), listed per
-- threat in tuning.lantern.guards. The Tonight card's exposure word counts it too (tuning.night.exposure.guards).
-- (The trip line and the bell of the first plan were cut, D184.)

local Inventory = require("src.sim.systems.inventory")

local Lantern = {}

--- The catalog equipment id that means "this run has a lantern".
Lantern.ITEM = "lantern"

--- Does this run have a lantern?
function Lantern.owned(world)
  return Inventory.hasEquipment(world, Lantern.ITEM)
end

--- The chance (0..1) the lantern turns `threatId` aside; 0 without it or for a threat it does not cover.
function Lantern.guard(world, threatId)
  if not Lantern.owned(world) then
    return 0
  end
  return rawget(world.tuning.lantern.guards, threatId) or 0
end

--- Does the lantern cover this threat?
function Lantern.covers(world, threatId)
  return (rawget(world.tuning.lantern.guards, threatId) or 0) > 0
end

return Lantern
