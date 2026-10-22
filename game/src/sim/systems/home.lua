-- The home's condition (B7, #351, D192, docs/PLAN_DEPTH.md §6.2): accessors only, no state. The home events (roof leak,
-- torn tarp, clogged flue, frozen pump, broken tool) open lasting damage flags through the event engine (Events.hasDamage);
-- this module is the one place the rest of the sim asks what an open flag does, so needs and the shelter stay unaware of
-- events:
--   * a torn tarp (flag "torn_canvas") makes a camp colder: Home.insulationFactor multiplies the shelter's insulation (the
--     warmth need), tuning.events.home.tornCanvasInsulation, read by Shelter.insulation;
--   * a clogged flue (flag "clogged_flue") makes the stove give less warmth per log: Home.stoveFactor, read by
--     Needs.heatEfficiency.
-- Both flags mend themselves (the event's `later` repairs them after a few days), so a neglected home costs a share of
-- warmth for a few days and never more (D184). The combined warmth need stays under mercy.maxWarmthMultiplier.

-- Events is read lazily: it requires the shelter and needs systems that read this module.
local function events()
  return require("src.sim.systems.events")
end

local Home = {}

--- Flag names, shared with the event content.
Home.TORN = "torn_canvas"
Home.CLOGGED = "clogged_flue"

--- Multiplier on the shelter's insulation (the night's warmth need) from the tarp: above 1 while the camp's canvas is torn.
function Home.insulationFactor(world, shelterId)
  if shelterId == "camp" and events().hasDamage(world, Home.TORN) then
    return world.tuning.events.home.tornCanvasInsulation
  end
  return 1
end

--- Multiplier (0..1) on the stove's warmth per log: lower while the flue is clogged.
function Home.stoveFactor(world)
  if events().hasDamage(world, Home.CLOGGED) then
    return world.tuning.events.home.cloggedFlueStove
  end
  return 1
end

return Home
