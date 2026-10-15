-- Sandbox save mode (D133): accessors only. A slot created as a Sandbox carries `meta.sandbox = true` (the
-- slot's persistent data, so it survives save and load and is never part of a run that can be discarded).
-- In a sandbox slot:
--   * nothing costs resources: the Market lists and hands over every catalog item free and at once (the cheat
--     of D126, permanently), and the ledger does not deduct the costs named in tuning.sandbox.freeReasons;
--   * the homesteader cannot die: Condition still drains on hungry and cold days but stops at
--     tuning.sandbox.conditionFloor, so Needs never reports "depleted" and the run never fails.

local Sandbox = {}

--- Is this world a sandbox slot?
function Sandbox.on(world)
  return world.meta.sandbox == true
end

--- Is a ledger removal for `reason` free in this world (sandbox only)?
function Sandbox.frees(world, reason)
  -- rawget: tuning is strict, and an unlisted reason is just "not free".
  return world.meta.sandbox == true and reason ~= nil and rawget(world.tuning.sandbox.freeReasons, reason) == true
end

--- The lowest Condition can fall to: 0 in a normal slot.
function Sandbox.conditionFloor(world)
  return world.meta.sandbox == true and world.tuning.sandbox.conditionFloor or 0
end

return Sandbox
