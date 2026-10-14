-- Fishing (GDD §7.10).
--
-- Idle: the routine casts at the creek (category "fish") and sometimes lands a common fish.
-- Active: with the rod in hand, tapping water walks the homesteader to the bank; when they're set
-- up, "fishing.ready" is emitted and the UI runs the tension mini-game
-- (src/sim/minigames/fishing_model.lua), then reports the result with Fishing.land().
--
-- The fish guide (catch counts, best size) lives in world.meta.fishGuide so it outlasts runs.
-- Emits "fishing.ready" { tile, actor }, "fish.caught" { fish, size, mode, first },
--       "fish.lost" { fish, reason } (reason "slipped" | "escaped" | "full").
-- Fishing waits for room (D59): no cast starts, and no fish is offered, when a catch could not be kept.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")

local Fishing = {}

--- How active the fish are today (1 = normal), from the weather: scales routine catch odds and
--- how fast they bite when the player fishes (D51).
function Fishing.activity(world)
  return Weather.fishActivity(world)
end

function Fishing.hasRod(world)
  return Stats.modifier(world, "rod") >= 1
end

local function inHours(hours, hour)
  for _, range in ipairs(hours) do
    local from, to = range[1], range[2]
    if from <= to then
      if hour >= from and hour < to then
        return true
      end
    elseif hour >= from or hour < to then -- wraps midnight
      return true
    end
  end
  return false
end

--- Fish species biting right now (season & hour). idleOnly limits to routine-catchable fish.
function Fishing.available(world, idleOnly)
  local now = Calendar.now(world)
  local list = {}
  for _, fish in ipairs(world.registry:all("fish")) do
    local ok = not idleOnly or fish.idle == true
    if ok and fish.seasons then
      ok = false
      for _, s in ipairs(fish.seasons) do
        ok = ok or s == now.season
      end
    end
    if ok and fish.hours then
      ok = inHours(fish.hours, now.hour)
    end
    if ok then
      list[#list + 1] = fish
    end
  end
  return list
end

--- The biting fish whose store still has room for one more. A fish that could not be kept is never
--- offered (D59), so a catch is never lost to a full store. Second return: the id of the first
--- biting fish whose store is full (nil if none), to say what is in the way.
local function withRoom(world, mode)
  local roomy, fullId = {}, nil
  for _, fish in ipairs(Fishing.available(world, mode == "idle")) do
    if Ledger.room(world, fish.id) >= 1 then
      roomy[#roomy + 1] = fish
    else
      fullId = fullId or fish.id
    end
  end
  return roomy, fullId
end

--- Can a catch be kept right now? False (plus the full fish's id) when fish are biting but every
--- one of them has no room; true when nothing is biting at all (that is "nothing", not "full").
function Fishing.canStore(world, mode)
  local roomy, fullId = withRoom(world, mode)
  if #roomy > 0 or not fullId then
    return true
  end
  return false, fullId
end

--- Pick which fish bites. mode: "idle" | "active". Returns a fish definition, or nil when nothing
--- is biting (second return nil) or every biting fish has a full store (second return "full").
function Fishing.rollFish(world, mode)
  local list, fullId = withRoom(world, mode)
  if #list == 0 then
    return nil, fullId and "full" or nil
  end
  local boost = world.tuning.fishing.rarityBoostActive
  return world:rng("fishing"):weighted(list, function(fish)
    if mode == "active" and fish.rarity ~= "common" then
      return fish.weight * boost
    end
    return fish.weight
  end)
end

function Fishing.rollSize(world, fish)
  local rng = world:rng("fishing")
  -- Product of two rolls skews toward the small end; big ones are special.
  local t = rng:float() * rng:float()
  return math.floor(fish.sizeMin + (fish.sizeMax - fish.sizeMin) * t + 0.5)
end

--- Record a caught fish: adds it to stock and the persistent fish guide. Returns true. If its store
--- filled up while the fish was on the line, the fish gets away instead ("fish.lost" with reason
--- "full", never counted as caught) and this returns false.
function Fishing.land(world, fishId, size, mode)
  local fish = world.registry:get("fish", fishId)
  if Ledger.room(world, fish.id) < 1 then
    world.events:emit("fish.lost", { fish = fish.id, reason = "full" })
    return false
  end
  Ledger.add(world, fish.id, 1, "fishing")
  world.meta.fishGuide = world.meta.fishGuide or {}
  local entry = world.meta.fishGuide[fish.id]
  local first = entry == nil
  if first then
    entry = { count = 0, best = 0, firstDay = Calendar.now(world).day }
    world.meta.fishGuide[fish.id] = entry
  end
  entry.count = entry.count + 1
  entry.best = math.max(entry.best, size)
  world.events:emit("fish.caught", { fish = fish.id, size = size, mode = mode, first = first })
  return true
end

--- A hooked fish got away in the mini-game. reason: "slipped" | "escaped".
function Fishing.lose(world, fishId, reason)
  world.registry:get("fish", fishId)
  world.events:emit("fish.lost", { fish = fishId, reason = reason })
end

function Fishing.init(world)
  world.meta.fishGuide = world.meta.fishGuide or {}
  Tasks.register(world, {
    id = "fish",
    category = "fish",
    verb = "Fish",
    clickOrder = 55, -- before filling the bucket, so the rod wins when it's in hand
    candidates = function(w, _, add)
      -- Rod ownership doesn't depend on the tile, so check it once rather than per candidate.
      if not Fishing.hasRod(w) or not Fishing.canStore(w, "idle") then
        return
      end
      for _, i in ipairs(Grid.bankTiles(w, "water")) do
        if Weather.waterTarget(w, i) then
          add(i)
        end
      end
    end,
    canDo = function(w, _, i, order)
      if order and order.tool ~= "rod" then
        return false
      end
      return Grid.terrain(w, i).water == true
        and Fishing.hasRod(w)
        and Fishing.canStore(w, order and "active" or "idle")
    end,
    blocked = function(w, _, i, order)
      if not (order and order.tool == "rod") or Grid.terrain(w, i).water ~= true or not Fishing.hasRod(w) then
        return nil
      end
      return select(2, Fishing.canStore(w, "active"))
    end,
    -- The idle search: `candidates` already checked the rod once for all tiles.
    canDoCandidate = function(w, _, i)
      return Grid.terrain(w, i).water == true
    end,
    workTime = function(w, actor, i)
      local cfg = w.tuning.fishing
      -- In winter, cut through the ice first (once per hole): ice fishing.
      return (actor.job and actor.job.ordered and cfg.castTime or cfg.idleAttemptTime) + Weather.iceWork(w, i)
    end,
    complete = function(w, actor, i, order)
      Weather.openHole(w, i)
      if order then
        w.events:emit("fishing.ready", { tile = i, actor = actor.id })
        return
      end
      local cfg = w.tuning.fishing
      local chance = cfg.idleCatchChance
      if Ledger.remove(w, "bait", 1, "fishing") then
        chance = chance + cfg.baitIdleBonus
      end
      chance = math.min(cfg.maxIdleChance, chance * Fishing.activity(w))
      if w:rng("fishing"):chance(chance) then
        local fish = Fishing.rollFish(w, "idle")
        if fish then
          Fishing.land(w, fish.id, Fishing.rollSize(w, fish), "idle")
        end
      end
    end,
  })
end

return Fishing
