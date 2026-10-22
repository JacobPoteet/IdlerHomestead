-- Night raiders (C2 + C3, #356, D188, docs/PLAN_DEPTH.md §6.1): the raccoon, deer and rabbits, and the black bear.
-- The handler behind three night threats of data/content/night_threats.lua (handler "raiders"); the night threat
-- framework (nightthreats.lua) asks it to plan at dusk and to land at the threat's hour, exactly as it does the cat and
-- the animals. It owns no state: the framework keeps the tally and the history, the crops system keeps the browse mark.
--
--   raccoon  opens a food store and spoils part of ONE kind (fresh produce, eggs, milk, feed). Answer: lidded bins.
--   deer     deer and rabbits browse a few unripe crops on the field's edge. Answer: a scarecrow.
--   bear     a black bear strips ONE of the stores that smell (smoked fish, cheese, feed, hay). Answer: a bear box.
--
-- THE RULE (D184): nothing here kills or destroys capital. A raccoon or a bear takes a share of one store, capped at
-- `maxLoss` units. Deer browse a crop: it keeps growing and gives a smaller harvest (`Crops.browse`, `browseCut`), never
-- a dead plant. The framework's mercy rules scale the chance while Footing is slipped and after a landed threat.
--
-- Streams: one per threat id (`raccoon`, `deer`, `bear`), so a raider never moves another threat's draws. A plan draws
-- the hit, the guard roll and the pick rolls whatever the stores or the guard (so the stream does not depend on them);
-- the picks are used at landing, so nothing is drawn at the hour. The guard is the catalog stat the threat's content
-- names (`raccoonGuard`, `cropGuard`, `bearGuard`), capped by `maxGuard`.
--
-- Emits "raider.stopped" { id } when a raid was turned back, and "raider.raided" { id, lost = { [resource] = n }?,
-- units?, tiles? (crop tiles browsed) } when it landed.

local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Stats = require("src.sim.stats")

local Raiders = {}

local function cfg(world, id)
  return world.tuning.raiders[id]
end

local function set(list)
  local out = {}
  for _, v in ipairs(list or {}) do
    out[v] = true
  end
  return out
end

-- The stores a store raider can take from: { { id, n } } in registry order (whole units only), and the total units. THE FOOD
-- RESERVE (mercy, PLAN_DEPTH 6.5): food the homesteader eats is only offered down to `mercy.keepFoodDays` days in stock,
-- so a raid never takes the meal the next days need; feed and hay (no calories) are offered whole.
local function stock(world, c)
  local categories, ids = set(c.targetCategories), set(c.targetResources)
  local keep = world.tuning.raiders.mercy.keepFoodDays * world.tuning.needs.dailyCalories
  local spare = Needs.calories(world) - keep -- calories a raid may still take
  local list, total = {}, 0
  for _, res in ipairs(world.registry:all("resources")) do
    if categories[res.category] or ids[res.id] then
      local n = math.floor(Ledger.get(world, res.id))
      if res.calories and res.calories > 0 then
        n = math.min(n, math.floor(math.max(0, spare) / res.calories))
        spare = spare - n * res.calories
      end
      if n > 0 then
        list[#list + 1] = { id = res.id, n = n }
        total = total + n
      end
    end
  end
  return list, total
end

-- Does this threat have anything to take right now?
local function hasTarget(world, id, c)
  if id == "deer" then
    return #Crops.edgeTiles(world) > 0
  end
  local _, total = stock(world, c)
  return total > 0
end

-- The chance a raid is turned back: the catalog stat the content names, capped.
local function guardChance(world, plan, c)
  return math.min(c.maxGuard, Stats.modifier(world, plan.guard))
end

--- The in-game hour tonight's raid lands (the night threat framework calls Raiders.nightLand then).
function Raiders.nightHour(world, d)
  return cfg(world, d.id).hour
end

--- Plan tonight's raid for the threat `d` (the night threat framework calls this at dusk, C2, D188): draws the threat's
--- stream, and returns a plan ({ id, guard (the stat), guardRoll, picks }) when it comes and has something to take, or nil.
--- `scale` multiplies the chance (exposure and the mercy rules, 1 = unchanged).
function Raiders.nightPlan(world, scale, d)
  local c = cfg(world, d.id)
  local now = Calendar.now(world)
  local rng = world:rng(d.id)
  local chance = c.chancePerDay * c.yearScale[math.min(now.year, #c.yearScale)]
  local hit = rng:chance(math.min(1, chance * (scale or 1)))
  local guardRoll = rng:float()
  local picks = {}
  for k = 1, c.maxTiles do
    picks[k] = rng:float()
  end
  if not hit or now.day < c.firstDay or not hasTarget(world, d.id, c) then
    return nil
  end
  return { id = d.id, guard = d.guard, guardRoll = guardRoll, picks = picks }
end

-- A store raid: one kind picked by weight of stock, a share of it taken through the ledger (reason = the threat id).
local function raidStores(world, plan, c)
  local list, total = stock(world, c)
  local x, pick = plan.picks[1] * total, list[#list]
  for _, entry in ipairs(list) do
    if x < entry.n then
      pick = entry
      break
    end
    x = x - entry.n
  end
  local units = math.min(pick.n, math.max(c.minLoss, math.min(c.maxLoss, math.floor(pick.n * c.lossFraction))))
  Ledger.remove(world, pick.id, units, plan.id)
  local lost = { [pick.id] = units }
  world.events:emit("raider.raided", { id = plan.id, lost = lost, units = units })
  return { lost = lost, units = units }
end

-- Deer and rabbits: a share of the edge's unripe crops browsed, at most `maxTiles`.
local function raidField(world, plan, c)
  local tiles = Crops.edgeTiles(world)
  local count = math.min(#tiles, c.maxTiles, math.max(1, math.ceil(#tiles * c.shareOfEdge)))
  local browsed = {}
  for k = 1, count do
    local at = math.min(#tiles, math.floor(plan.picks[k] * #tiles) + 1)
    local tile = table.remove(tiles, at)
    Crops.browse(world, tile)
    browsed[#browsed + 1] = tile
  end
  world.events:emit("raider.raided", { id = plan.id, tiles = #browsed })
  return { tiles = #browsed }
end

--- Land a planned raid: "stopped" (the guard turned it back), "raided" (it took its share; the second result says what:
--- { lost, units } for a store, { tiles } for a field), or nil when what it came for is gone by now.
function Raiders.nightLand(world, plan)
  local c = cfg(world, plan.id)
  if not hasTarget(world, plan.id, c) then
    return nil
  end
  if plan.guardRoll < guardChance(world, plan, c) then
    world.events:emit("raider.stopped", { id = plan.id })
    return "stopped"
  end
  if plan.id == "deer" then
    return "raided", raidField(world, plan, c)
  end
  return "raided", raidStores(world, plan, c)
end

return Raiders
