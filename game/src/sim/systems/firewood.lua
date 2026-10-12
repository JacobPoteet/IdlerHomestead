-- Firewood (GDD §4.2, §5.3): the routine splits wood into green firewood at a chopping block
-- (category "fuel"), leaving a little wood for the smoker. Which resources are split from and into
-- is set in tuning.firewood. Green firewood is seasoned in a woodshed
-- (a processing station, see data/content/recipes.lua) and burned for warmth by the needs system.
-- An axe (stat "chopSpeed") speeds up splitting and felling.

local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")

local Firewood = {}

-- Wood to split in one batch (respecting the reserve and firewood storage), or 0.
local function splittable(world, order)
  local cfg = world.tuning.firewood
  local keep = order and 0 or cfg.keepWood
  local room = Ledger.capacity(world, cfg.splitInto) - Ledger.get(world, cfg.splitInto)
  return math.max(0, math.min(cfg.splitBatch, Ledger.get(world, cfg.splitFrom) - keep, room))
end

local function isSplitter(world, i)
  local def = Grid.object(world, i)
  return def ~= nil and def.splitter == true
end

function Firewood.init(world)
  Tasks.register(world, {
    id = "split_wood",
    category = "fuel",
    verb = "Split wood",
    clickOrder = 26,
    candidates = function(w, _, add)
      if splittable(w, nil) <= 0 then
        return
      end
      for anchor, obj in pairs(w.state.grid.objects) do
        if w.registry:get("objects", obj.id).splitter then
          add(anchor)
        end
      end
    end,
    canDo = function(w, _, i, order)
      return isSplitter(w, i) and splittable(w, order) > 0
    end,
    workTime = function(w)
      return w.tuning.firewood.splitTime * Stats.timeFactor(w, "chopSpeed")
    end,
    complete = function(w, _, _, order)
      local cfg = w.tuning.firewood
      local n = splittable(w, order)
      if n > 0 and Ledger.remove(w, cfg.splitFrom, n, "split") then
        Ledger.add(w, cfg.splitInto, n, "split")
      end
    end,
  })
end

return Firewood
