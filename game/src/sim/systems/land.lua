-- Land: generates the plot for a new run and keeps runtime lookups (occupancy) in sync.
-- Also hands out the run's starting resources once (plus the chosen plot's bonus, state.startBonus = { id = amount }).

local Grid = require("src.sim.grid")
local Landgen = require("src.sim.landgen")
local Ledger = require("src.sim.systems.ledger")

local Land = {}

function Land.init(world)
  local state = world.state
  if not state.grid then
    Landgen.generate(world)
  else
    Grid.rebuildOccupancy(world)
  end
  -- Runs saved before the water table existed get the table their seed would have made.
  if not state.grid.waterTable then
    Landgen.waterTable(world)
  end
  if not state.startingKitGiven then
    state.startingKitGiven = true
    local ids = {}
    for id in pairs(world.tuning.run.startingResources) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      Ledger.add(world, id, world.tuning.run.startingResources[id], "starting kit")
    end
    -- What the chosen plot comes with (D200, #384): set by the run start (Run.startNext), absent on a plain run.
    local bonus = state.startBonus
    ids = {}
    for id in pairs(bonus or {}) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      Ledger.add(world, id, bonus[id], "plot bonus")
    end
  end
end

--- Water table at tile i, 0..1 (how close groundwater is to the surface; wells need a high one).
function Land.waterTable(world, i)
  return world.state.grid.waterTable[i] or 0
end

--- Can a well or pump be sunk at tile i?
function Land.hasWaterTable(world, i)
  return Land.waterTable(world, i) >= world.tuning.water.table.minForWell
end

--- Tile index of the truck (the home base: starting battery, sleeping shelter, trips to town).
function Land.truck(world)
  return world.state.land.truck
end

--- Tile index where the homesteader starts (starting objects are placed around it).
function Land.spawn(world)
  return world.state.land.spawn
end

return Land
