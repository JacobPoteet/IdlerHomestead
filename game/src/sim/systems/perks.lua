-- Perks (GDD §8.2): once per run, known perks add their head starts on top of the starting kit
-- (tuning.run): extra resources, packed equipment, a charged truck. Perk stat modifiers apply
-- all the time through src/sim/stats.lua.
--
-- State: world.state.perksApplied = true once the run's head starts have been handed out.
-- Emits "perks.applied" { perks = { perkId, ... } }.

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

--- Give this run's head starts from every known perk.
function Perks.applyRunStart(world)
  local applied = {}
  local truck = Land.truck(world)
  for _, perk in ipairs(Journal.knownPerks(world)) do
    applied[#applied + 1] = perk.id
    local resources = perk.startingResources or {}
    for _, id in ipairs(sortedKeys(resources)) do
      Ledger.add(world, id, resources[id], "perk")
    end
    for _, id in ipairs(perk.startingEquipment or {}) do
      Inventory.addEquipment(world, id)
    end
    if perk.truckCharge then
      Power.add(world, truck, perk.truckCharge)
    end
  end
  world.events:emit("perks.applied", { perks = applied })
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
