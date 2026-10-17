-- Footing (D162, #341, docs/PLAN_DEPTH.md §3.2): the state that moves the player's pressing goal from the night
-- to the season. A state, not an unlock, and run state: a new run starts without it.
--
-- Evaluated once a day, at dusk (the first tick at or after sunset), by the same figures the Tonight card shows.
-- A night is *good* when all four hold: a shelter with a heat source (a camp with a campfire counts), a water
-- source (the drinking-water outlook covers `footing.waterDays`), `footing.fuelNights` nights of fuel and
-- `footing.foodDays` days of food in reserve.
--   Earned:   `footing.streakNights` good nights in a row (any night that is not good resets the count).
--   Slipped:  while held, reserves under `footing.slipFuelNights` of fuel or `footing.slipFoodDays` of food.
--   Regained: `footing.regainNights` good nights in a row while slipped (a night that is not good resets it).
-- While slipped the Tonight card leads again (Readiness.tonightDue) and Footing.paused is true: the accessor that gates
-- new offers (bad events, contracts, charter drafts) and softens outcomes. It pauses no timer (D168): clocks keep running.
--
-- State: world.state.footing = { held, slipped, streak (good nights toward earning), good (good nights toward
--   regaining), last (the day last evaluated), gainedDay?, cardDue (the one-time card has not been shown) }
-- Emits "footing.gained" { day }, "footing.slipped" { day, fuel (nights), food (days) } and "footing.regained" { day }.

local Calendar = require("src.sim.systems.calendar")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")

local Footing = {}

local function state(world)
  return world.state.footing
end

--- Is Footing held (earned, whether or not it has slipped since)?
function Footing.held(world)
  return state(world).held
end

--- Is the gate open (the gate framework, D164, #343, PLAN_DEPTH §3.2)? One accessor for everything that opens at
--- Footing: a catalog item, a contract, a land chunk, a charter, a tier. `gate` is any content definition carrying
--- the flag `requiresFooting`, or a bare gate `{ footing = true }` (or `true`) for a surface that has no definition;
--- nil, false or a definition without the flag is always open. Open is Footing held, slipped or not (a slip pauses
--- the longer goals, D162, it does not close what was opened). Callers ask this, never `Footing.held` directly, so no
--- feature hard-codes the rule.
function Footing.isOpen(world, gate)
  if not gate then
    return true
  end
  if gate == true or rawget(gate, "requiresFooting") or rawget(gate, "footing") then
    return state(world).held
  end
  return true
end

--- Does the definition carry the gate (whether or not it is open now)?
function Footing.gated(def)
  return rawget(def, "requiresFooting") == true
end

--- Is it held but slipped, with reserves to rebuild?
function Footing.slipped(world)
  return state(world).slipped
end

--- Do the longer goals pause (nothing is lost, no timer runs out)? True exactly while Footing is slipped.
function Footing.paused(world)
  return state(world).slipped
end

--- Is tonight the pressing goal (the Tonight card leads)? Until Footing is earned, and again while it is slipped.
function Footing.tonightLeads(world)
  local s = state(world)
  return not s.held or s.slipped
end

--- The four tests of a good night, a list of { id, ok, have, need } (the checklist the player sees, PLAN_DEPTH Q4):
--- shelter (a shelter with a heat source), water (days of drinking water), fuel (nights of wood), food (days).
function Footing.checks(world)
  local cfg = world.tuning.night.footing
  local fuel = Needs.fuelNights(world)
  local food = Needs.foodDays(world)
  local water = Needs.waterOutlook(world).days
  local shelterOk = Shelter.id(world) ~= nil and Needs.heatEfficiency(world) > 0
  return {
    { id = "shelter", ok = shelterOk, have = shelterOk and 1 or 0, need = 1 },
    { id = "water", ok = water >= cfg.waterDays, have = water, need = cfg.waterDays },
    { id = "fuel", ok = fuel >= cfg.fuelNights, have = fuel, need = cfg.fuelNights },
    { id = "food", ok = food >= cfg.foodDays, have = food, need = cfg.foodDays },
  }
end

--- Are all four tests met tonight?
function Footing.goodNight(world)
  for _, c in ipairs(Footing.checks(world)) do
    if not c.ok then
      return false
    end
  end
  return true
end

--- Are the reserves under the slip line (less than a night of fuel or a day of food)?
function Footing.reservesLow(world)
  local cfg = world.tuning.night.footing
  return Needs.fuelNights(world) < cfg.slipFuelNights or Needs.foodDays(world) < cfg.slipFoodDays
end

--- The status for the HUD and the cards: { held, slipped, streak, streakNights, good, regainNights, gainedDay }.
function Footing.status(world)
  local s, cfg = state(world), world.tuning.night.footing
  return {
    held = s.held,
    slipped = s.slipped,
    streak = s.streak,
    streakNights = cfg.streakNights,
    good = s.good,
    regainNights = cfg.regainNights,
    gainedDay = s.gainedDay,
  }
end

--- Is the one-time "Footing gained" card waiting to be shown?
function Footing.cardDue(world)
  return state(world).cardDue
end

--- The card has been shown: it does not show again this run.
function Footing.cardShown(world)
  state(world).cardDue = false
end

--- Judge tonight: advance the state machine one night. Normally called by the dusk tick; public for tests.
function Footing.evaluate(world)
  local s, cfg = state(world), world.tuning.night.footing
  local day = Calendar.now(world).day
  s.last = day
  local good = Footing.goodNight(world)
  if not s.held then
    s.streak = good and s.streak + 1 or 0
    if s.streak >= cfg.streakNights then
      s.held, s.slipped, s.streak, s.good, s.gainedDay, s.cardDue = true, false, 0, 0, day, true
      world.events:emit("footing.gained", { day = day })
    end
  elseif not s.slipped then
    if Footing.reservesLow(world) then
      s.slipped, s.good = true, 0
      world.events:emit("footing.slipped", { day = day, fuel = Needs.fuelNights(world), food = Needs.foodDays(world) })
    end
  else
    s.good = good and s.good + 1 or 0
    if s.good >= cfg.regainNights then
      s.slipped, s.good = false, 0
      world.events:emit("footing.regained", { day = day })
    end
  end
end

function Footing.init(world)
  local s = world.state.footing or {}
  world.state.footing = s
  -- A fresh run starts without it: fill in the fields.
  s.held = s.held or false
  s.slipped = s.slipped or false
  s.streak = s.streak or 0
  s.good = s.good or 0
  s.last = s.last or 0
  s.cardDue = s.cardDue or false
end

function Footing.tick(world)
  local s = state(world)
  local now = Calendar.now(world)
  if s.last == now.day then
    return
  end
  local _, sunset = Calendar.daylight(world)
  if now.hour >= sunset then
    Footing.evaluate(world)
  end
end

return Footing
