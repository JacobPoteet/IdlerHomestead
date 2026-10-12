-- Spoilage (GDD §7.2): each day, fresh food loses about 1/spoilDays of its stock.
-- Preserved food (no spoilDays) keeps. Emits "food.spoiled" { resource, category, amount }.

local Ledger = require("src.sim.systems.ledger")

local Spoilage = {}

function Spoilage.daily(world)
  local rng = world:rng("spoilage")
  for _, res in ipairs(world.registry:all("resources")) do
    if res.spoilDays then
      local amount = Ledger.get(world, res.id)
      if amount > 0 then
        local spoiled = math.min(amount, math.floor(amount / res.spoilDays + rng:float()))
        if spoiled > 0 then
          Ledger.remove(world, res.id, spoiled, "spoiled")
          world.events:emit("food.spoiled", { resource = res.id, category = res.category, amount = spoiled })
        end
      end
    end
  end
end

function Spoilage.init(world)
  world.events:on("calendar.newDay", function()
    Spoilage.daily(world)
  end)
end

return Spoilage
