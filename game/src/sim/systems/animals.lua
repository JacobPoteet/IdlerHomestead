-- Chickens (GDD §7.7, D63): a hen house, a flock with needs, eggs, and night predators.
--
-- The flock is the ledger resource "hen" (its capacity comes from placed coops, so a hen needs a
-- coop and a full coop leaves new hens waiting at the gate, D59). Everything else is flock-wide
-- state kept here:
--   feed, water   what the feeder and waterer hold (units). The tend chore tops them up: feed comes
--                 out of the ledger ("chicken_feed"), water is carried by hand and costs only the
--                 chore's time (D63; the shared water stock is a follow-up).
--   nest          eggs laid and waiting in the nest box. Tending moves them into the ledger ("egg");
--                 if the egg store is full they wait in the box, and a full box stops the laying.
-- Once a day at tuning.animals.hens.careHour the hens eat and drink what the feeder and waterer hold.
-- A short day (under `shortBelow` of the need met) is a hungry or dry day; a few in a row and a hen
-- is lost each further day (forgiving, but real). Once a day at `layHour` each hen lays by a seeded
-- roll (stream "eggs") that depends on the season and on how well the flock was fed and watered.
-- Once a night at `predators.hour` a seeded roll (stream "predators") may bring a fox: more likely
-- in lean seasons and rough weather (Weather.threat, #97), less with the cat about, turned back by
-- the coop's door and the predator fence (stat `predatorGuard`), otherwise it takes a hen or two.
-- Idle-friendly: the routine's `animals` category tends the coop (tend_coop) on its own.
--
-- State: world.state.animals = { feed, water, nest, fed, wet (share of need met at the last care),
--   hungryDays, thirstyDays (consecutive short days), careDay, layDay, raidDay (last day each ran),
--   laid, collected, lost, raids, stopped (lifetime counts), nestFullDay }
-- Emits "animals.collected" { count }, "animals.tended" { eggs, feed }, "animals.laid" { count },
-- "animals.nestFull" { lost }, "animals.short" { feed, water } (a short day),
-- "animals.lost" { reason = "hunger" | "thirst", hens }, "animals.predator" { day, killed, stopped }.

local Calendar = require("src.sim.systems.calendar")
local Cat = require("src.sim.systems.cat")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")

local Animals = {}

local HEN, EGG, FEED = "hen", "egg", "chicken_feed"

local function state(world)
  return world.state.animals
end

local function coopDef(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id)
end

-- Sum of a coop field (nest, feeder, waterer) over every placed coop.
local function coopTotal(world, field)
  local total = 0
  for _, anchor in ipairs(Grid.anchorsWith(world, "coop")) do
    total = total + coopDef(world, anchor).coop[field]
  end
  return total
end

--- Is any coop placed?
function Animals.hasCoop(world)
  return #Grid.anchorsWith(world, "coop") > 0
end

--- Hens in the flock.
function Animals.hens(world)
  return Ledger.get(world, HEN)
end

--- Hens the placed coops can house.
function Animals.housing(world)
  return Ledger.capacity(world, HEN)
end

--- Eggs waiting in the nest box.
function Animals.nest(world)
  return state(world).nest
end

--- Feed units the flock needs from the feeder on a day in the current season.
function Animals.feedNeed(world)
  local cfg = world.tuning.animals.hens
  return Animals.hens(world) * cfg.feedPerHen * cfg.feedShare[Calendar.now(world).season]
end

--- Water units the flock drinks on a day.
function Animals.waterNeed(world)
  return Animals.hens(world) * world.tuning.animals.hens.waterPerHen
end

--- Chance (0..1) that a night's raid is turned back: the best coop door plus the fence, capped.
function Animals.guard(world)
  local cfg = world.tuning.animals.predators
  local best = 0
  for _, anchor in ipairs(Grid.anchorsWith(world, "coop")) do
    best = math.max(best, coopDef(world, anchor).coop.guard)
  end
  return math.min(cfg.maxGuard, best + Stats.modifier(world, "predatorGuard"))
end

--- Probability that a predator comes tonight (before the coop's defences): season, weather, cat.
function Animals.raidChance(world)
  local cfg = world.tuning.animals.predators
  local p = cfg.chancePerDay * cfg.seasons[Calendar.now(world).season] * Weather.threat(world)
  if Cat.present(world) then
    p = p * cfg.catFactor
  end
  return math.min(1, p)
end

--- Probability that tonight's raid takes hens: it comes and the defences fail.
function Animals.dangerTonight(world)
  return Animals.raidChance(world) * (1 - Animals.guard(world))
end

--- Facts for the UI. Shares are 0..1; feedDays is how long feeder plus stock lasts at today's need.
function Animals.info(world)
  local s = state(world)
  local feedCap, waterCap, nestCap = coopTotal(world, "feeder"), coopTotal(world, "waterer"), coopTotal(world, "nest")
  local need = Animals.feedNeed(world)
  local stock = Ledger.get(world, FEED)
  return {
    hens = Animals.hens(world),
    housing = Animals.housing(world),
    nest = s.nest,
    nestCap = nestCap,
    feed = s.feed,
    feedCap = feedCap,
    stock = stock,
    water = s.water,
    waterCap = waterCap,
    feedDays = need > 0 and (s.feed + stock) / need or math.huge,
    hungryDays = s.hungryDays,
    thirstyDays = s.thirstyDays,
    guard = Animals.guard(world),
    laid = s.laid,
    collected = s.collected,
    lost = s.lost,
  }
end

-- Tending ---------------------------------------------------------------------------------------

local function eggsReady(world)
  return state(world).nest > 0 and Ledger.room(world, EGG) >= 1
end

-- Feed units a tend would move into the feeder (whole units only).
local function feedToAdd(world)
  local s = state(world)
  return math.max(0, math.min(coopTotal(world, "feeder") - s.feed, math.floor(Ledger.get(world, FEED))))
end

--- Is there anything a tap on the coop would do: eggs to collect, feed to add, water to top up?
function Animals.canTend(world)
  if not Animals.hasCoop(world) then
    return false
  end
  if eggsReady(world) then
    return true
  end
  if Animals.hens(world) == 0 then
    return false
  end
  local s, cfg = state(world), world.tuning.animals.hens
  local feederLow = s.feed <= coopTotal(world, "feeder") * cfg.topUpBelow
  local waterLow = s.water <= coopTotal(world, "waterer") * cfg.topUpBelow
  return (feederLow and feedToAdd(world) >= 1) or waterLow
end

--- Should the idle routine make a trip to the coop: enough eggs, or a feeder or waterer running low?
function Animals.needsTending(world)
  if not Animals.hasCoop(world) then
    return false
  end
  local s, cfg = state(world), world.tuning.animals.hens
  if eggsReady(world) and s.nest >= cfg.collectMin then
    return true
  end
  if Animals.hens(world) == 0 then
    return false
  end
  local feederLow = s.feed < coopTotal(world, "feeder") * cfg.tendBelow
  local waterLow = s.water < coopTotal(world, "waterer") * cfg.tendBelow
  return (feederLow and feedToAdd(world) >= 1) or waterLow
end

--- Do the tend chore: collect the eggs that fit, top up feeder (from the ledger) and waterer.
--- Returns eggs collected, feed units added.
function Animals.tend(world)
  local s = state(world)
  local eggs = 0
  if s.nest > 0 then
    eggs = math.min(s.nest, math.floor(Ledger.room(world, EGG)))
    if eggs > 0 then
      Ledger.add(world, EGG, eggs, "eggs")
      s.nest = s.nest - eggs
      s.collected = s.collected + eggs
      world.events:emit("animals.collected", { count = eggs })
    end
  end
  local feed = 0
  if Animals.hens(world) > 0 then
    feed = feedToAdd(world)
    if feed > 0 and Ledger.remove(world, FEED, feed, "feeder") then
      s.feed = s.feed + feed
    else
      feed = 0
    end
    s.water = coopTotal(world, "waterer")
  end
  world.events:emit("animals.tended", { eggs = eggs, feed = feed })
  return eggs, feed
end

-- The daily rounds -------------------------------------------------------------------------------

--- The hens eat and drink for the day. Returns fed share, watered share (1 with no flock).
function Animals.care(world)
  local s, cfg = state(world), world.tuning.animals.hens
  s.careDay = Calendar.now(world).day
  local hens = Animals.hens(world)
  if hens == 0 then
    return 1, 1
  end
  local needFeed, needWater = Animals.feedNeed(world), Animals.waterNeed(world)
  local ate = math.min(s.feed, needFeed)
  s.feed = s.feed - ate
  local drank = math.min(s.water, needWater)
  s.water = s.water - drank
  s.fed = needFeed > 0 and ate / needFeed or 1
  s.wet = needWater > 0 and drank / needWater or 1
  s.hungryDays = s.fed < cfg.hungryBelow and s.hungryDays + 1 or 0
  s.thirstyDays = s.wet < cfg.hungryBelow and s.thirstyDays + 1 or 0
  if s.fed < 1 or s.wet < 1 then
    world.events:emit("animals.short", { feed = s.fed < 1, water = s.wet < 1 })
  end
  local reason = s.thirstyDays > cfg.thirstAfter and "thirst" or s.hungryDays > cfg.starveAfter and "hunger" or nil
  if reason and Ledger.remove(world, HEN, 1, "neglect") then
    s.lost = s.lost + 1
    world.events:emit("animals.lost", { reason = reason, hens = Animals.hens(world) })
  end
  return s.fed, s.wet
end

--- Probability that one hen lays today, given the season and how the flock was fed and watered.
function Animals.layChance(world)
  local s, cfg = state(world), world.tuning.animals.hens
  local fed = cfg.hungryLay + (1 - cfg.hungryLay) * s.fed
  local wet = cfg.thirstyLay + (1 - cfg.thirstyLay) * s.wet
  return cfg.layChance[Calendar.now(world).season] * fed * wet
end

--- Today's laying: each hen rolls once on the "eggs" stream. Returns eggs put in the nest box.
function Animals.lay(world)
  local s = state(world)
  s.layDay = Calendar.now(world).day
  local hens = Animals.hens(world)
  if hens == 0 then
    return 0
  end
  local rng, chance = world:rng("eggs"), Animals.layChance(world)
  local laid = 0
  for _ = 1, hens do
    if rng:float() < chance then
      laid = laid + 1
    end
  end
  local stored = math.max(0, math.min(laid, coopTotal(world, "nest") - s.nest))
  s.nest = s.nest + stored
  s.laid = s.laid + stored
  if stored > 0 then
    world.events:emit("animals.laid", { count = stored })
  end
  if stored < laid and s.nestFullDay ~= s.layDay then
    s.nestFullDay = s.layDay
    world.events:emit("animals.nestFull", { lost = laid - stored })
  end
  return stored
end

--- Tonight's raid, rolled now. Returns "stopped" (the defences held), "raided" (hens were taken) or
--- nil (no predator, no hens, or too early in the run). Both rolls and the loss are always drawn, so
--- the stream does not depend on the defences.
function Animals.raid(world)
  local s, cfg = state(world), world.tuning.animals.predators
  local day = Calendar.now(world).day
  s.raidDay = day
  local hens = Animals.hens(world)
  if hens == 0 then
    return nil
  end
  local rng = world:rng("predators")
  local hit = rng:chance(Animals.raidChance(world))
  local guardRoll = rng:float()
  local loss = rng:int(cfg.loss.min, cfg.loss.max)
  if not hit or day < cfg.firstDay then
    return nil
  end
  s.raids = s.raids + 1
  if guardRoll < Animals.guard(world) then
    s.stopped = s.stopped + 1
    world.events:emit("animals.predator", { day = day, killed = 0, stopped = true })
    return "stopped"
  end
  local killed = math.min(hens, loss)
  Ledger.remove(world, HEN, killed, "predator")
  s.lost = s.lost + killed
  world.events:emit("animals.predator", { day = day, killed = killed, stopped = false })
  return "raided"
end

function Animals.init(world)
  local s = world.state.animals or {}
  world.state.animals = s
  -- Fields are filled in so saves from before chickens keep loading.
  s.feed = s.feed or 0
  s.water = s.water or 0
  s.nest = s.nest or 0
  s.fed = s.fed or 1
  s.wet = s.wet or 1
  s.hungryDays = s.hungryDays or 0
  s.thirstyDays = s.thirstyDays or 0
  s.careDay = s.careDay or 0
  s.layDay = s.layDay or 0
  s.raidDay = s.raidDay or 0
  s.laid = s.laid or 0
  s.collected = s.collected or 0
  s.lost = s.lost or 0
  s.raids = s.raids or 0
  s.stopped = s.stopped or 0
  s.nestFullDay = s.nestFullDay or 0

  Tasks.register(world, {
    id = "tend_coop",
    category = "animals",
    verb = "Tend hens",
    clickOrder = 70,
    candidates = function(w, _, add)
      if Animals.needsTending(w) then
        for _, anchor in ipairs(Grid.anchorsWith(w, "coop")) do
          add(anchor)
        end
      end
    end,
    canDo = function(w, _, i, order)
      local def = Grid.object(w, i)
      if not (def and def.coop) then
        return false
      end
      if order then
        return Animals.canTend(w)
      end
      return Animals.needsTending(w)
    end,
    blocked = function(w, _, i, order)
      local def = Grid.object(w, i)
      if order and def and def.coop and not Animals.canTend(w) and state(w).nest > 0 and Ledger.room(w, EGG) < 1 then
        return EGG
      end
      return nil
    end,
    workTime = function(w)
      return w.tuning.animals.hens.tendTime
    end,
    complete = function(w)
      Animals.tend(w)
    end,
  })
end

function Animals.tick(world)
  local s, cfg = state(world), world.tuning.animals
  local now = Calendar.now(world)
  if now.hour >= cfg.hens.layHour and s.layDay < now.day then
    Animals.lay(world)
  end
  if now.hour >= cfg.hens.careHour and s.careDay < now.day then
    Animals.care(world)
  end
  if now.hour >= cfg.predators.hour and s.raidDay < now.day then
    Animals.raid(world)
  end
end

return Animals
