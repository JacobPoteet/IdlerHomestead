-- Land: generates the plot for a new run and keeps runtime lookups (occupancy) in sync.
-- Also hands out the run's starting resources once.

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
  end
end

return Land
