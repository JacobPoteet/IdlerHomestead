-- Water hauling (GDD §5.3, rung 0): fill the bucket at the creek, carry it to the crops.
-- The actor's bucket (actor.bucket = waterings left) is what makes distance to water matter.

local Grid = require("src.sim.grid")
local Tasks = require("src.sim.systems.tasks")
local Crops = require("src.sim.systems.crops")
local Stats = require("src.sim.stats")
local Weather = require("src.sim.systems.weather")

local Water = {}

--- Waterings a full bucket holds (base + equipment such as the big bucket).
function Water.bucketCapacity(world)
  return world.tuning.actors.bucketCapacity + Stats.modifier(world, "bucketCapacity")
end

function Water.init(world)
  Tasks.register(world, {
    id = "fetch_water",
    category = "water",
    verb = "Fill bucket",
    clickOrder = 60,
    candidates = function(w, actor, add)
      -- Only head for the creek when the bucket is empty and something is thirsty.
      if actor.bucket > 0 or not Crops.anyNeedsWater(w) then
        return
      end
      for _, terrainId in ipairs({ "water", "ford" }) do
        for _, i in ipairs(Grid.bankTiles(w, terrainId)) do
          if Weather.waterTarget(w, i) then
            add(i)
          end
        end
      end
    end,
    canDo = function(w, actor, i)
      return Grid.terrain(w, i).water == true and actor.bucket < Water.bucketCapacity(w)
    end,
    workTime = function(w, _, i)
      return w.tuning.farming.fetchWaterTime + Weather.iceWork(w, i)
    end,
    complete = function(w, actor, i)
      Weather.openHole(w, i)
      actor.bucket = Water.bucketCapacity(w)
    end,
  })
end

return Water
