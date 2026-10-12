-- Clearing the messy start (GDD §4.3): brush, rocks, logs, junk and trees become resources.
-- The idle routine clears `autoClear` objects and anything sitting on a planned field tile.
-- Emits "object.cleared" { object, tile, yields }.

local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")

local Clearing = {}

local function clearable(def)
  return def.clearable ~= false and def.clearTime ~= nil
end

--- The largest yield of each resource that clearing this object can give: { [resourceId] = amount }.
function Clearing.mostYield(def)
  local most = {}
  for id, amount in pairs(def.yields or {}) do
    most[id] = type(amount) == "table" and amount[2] or amount
  end
  return most
end

--- The resource whose store lacks room for the biggest possible yield, or nil. Clearing waits for
--- room (D59) rather than discarding part of the yield.
local function shortage(world, def)
  return Ledger.shortfall(world, Clearing.mostYield(def))
end

function Clearing.init(world)
  Tasks.register(world, {
    id = "clear",
    category = "clear",
    verb = "Clear",
    clickOrder = 20,
    candidates = function(w, _, add)
      for anchor, obj in pairs(w.state.grid.objects) do
        local def = w.registry:get("objects", obj.id)
        if clearable(def) and (def.autoClear or Crops.isPlanned(w, anchor)) then
          add(anchor)
        end
      end
    end,
    canDo = function(w, _, i)
      local def = Grid.object(w, i)
      return def ~= nil and clearable(def) and shortage(w, def) == nil
    end,
    blocked = function(w, _, i)
      local def = Grid.object(w, i)
      return def ~= nil and clearable(def) and shortage(w, def) or nil
    end,
    workTime = function(w, _, i)
      local def = Grid.object(w, i)
      -- An axe (chopSpeed) speeds up felling trees and cutting up logs.
      return def.clearTime * (def.chop and Stats.timeFactor(w, "chopSpeed") or 1)
    end,
    complete = function(w, _, i)
      local def, anchor = Grid.object(w, i)
      local rng = w:rng("yields")
      local gained = {}
      local ids = {}
      for id in pairs(def.yields or {}) do
        ids[#ids + 1] = id
      end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local amount = def.yields[id]
        if type(amount) == "table" then
          amount = rng:int(amount[1], amount[2])
        end
        -- canDo (re-checked every tick of the job) guarantees room for the largest roll, so
        -- nothing is lost here; the overflow call is only a same-tick safety net.
        gained[id] = Ledger.addOrOverflow(w, id, amount, "clear")
      end
      Grid.removeObject(w, anchor)
      w.events:emit("object.cleared", { object = def.id, tile = anchor, yields = gained })
    end,
  })
end

return Clearing
