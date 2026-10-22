-- Perks (GDD §8.2): once per run, known perks add their head starts on top of the starting kit
-- (tuning.run): extra resources, packed equipment, a charged truck. Perk stat modifiers apply
-- all the time through src/sim/stats.lua.
--
-- A run may also start with one loadout (D201, #386; data/content/loadouts.lua): a bundle of existing items with a small
-- penalty, chosen at the recovery screen and written into the run state by Run.startNext. It is handed out with the perks.
--
-- State: world.state.perksApplied = true once the run's head starts have been handed out;
-- world.state.loadout = the loadout id the run started with (absent for the standard start).
-- Emits "perks.applied" { perks = { perkId, ... }, loadout = id? }.

local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")

local Perks = {}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- Hand out one bundle of starting items (a perk or a loadout shares the fields): resources, equipment, objects beside
--- the truck and a truck charge. `penalty` (loadouts) takes resources off the stock, never below zero.
local function hand(world, def, source)
  -- Equipment and objects first: a placed coop is what gives the hens room (the ledger caps a stock at its storage).
  for _, id in ipairs(def.startingEquipment or {}) do
    Inventory.addEquipment(world, id)
  end
  for _, id in ipairs(def.startingObjects or {}) do
    Inventory.placeNearSpawn(world, id)
  end
  local resources = def.startingResources or {}
  for _, id in ipairs(sortedKeys(resources)) do
    Ledger.add(world, id, resources[id], source)
  end
  local penalty = source == "loadout" and def.penalty or {} -- only a loadout has a penalty (perks schema has none)
  for _, id in ipairs(sortedKeys(penalty)) do
    Ledger.remove(world, id, math.min(penalty[id], Ledger.get(world, id)), source)
  end
  if def.truckCharge then
    Power.add(world, Land.truck(world), def.truckCharge)
  end
end

--- The loadout this run started with, as its definition, or nil for the standard start.
function Perks.loadout(world)
  local id = world.state.loadout
  return id and world.registry:get("loadouts", id) or nil
end

--- Give this run's head starts from every known perk, then the chosen loadout.
function Perks.applyRunStart(world)
  local applied = {}
  for _, perk in ipairs(Journal.knownPerks(world)) do
    applied[#applied + 1] = perk.id
    hand(world, perk, "perk")
  end
  local loadout = Perks.loadout(world)
  if loadout then
    hand(world, loadout, "loadout")
  end
  world.events:emit("perks.applied", { perks = applied, loadout = loadout and loadout.id or nil })
  return applied
end

function Perks.init(world)
  if world.state.perksApplied then
    return
  end
  world.state.perksApplied = true
  Perks.applyRunStart(world)
end

return Perks
