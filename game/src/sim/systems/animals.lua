-- Livestock (GDD §7.7, D63, D71): chickens and goats on one framework. Each kind has a house, a flock
-- count in the ledger, daily needs, a product, a tend chore and night predators.
--
-- Chickens: a hen house, a flock with needs, eggs.
--   The flock is the ledger resource "hen" (its capacity comes from placed coops, so a hen needs a
--   coop and a full coop leaves new hens waiting at the gate, D59). Everything else is flock-wide
--   state kept here:
--     feed, water   what the feeder and waterer hold (units). The tend chore tops them up: feed comes
--                   out of the ledger ("chicken_feed"), water is carried by hand and costs only the
--                   chore's time (D63; the shared water stock is a follow-up).
--     nest          eggs laid and waiting in the nest box. Tending moves them into the ledger ("egg");
--                   if the egg store is full they wait in the box, and a full box stops the laying.
--   Once a day at tuning.animals.hens.careHour the hens eat and drink what the feeder and waterer hold.
--   A short day (under `hungryBelow` of the need met) is a hungry or dry day; a few in a row and a hen
--   is lost each further day (forgiving, but real). Once a day at `layHour` each hen lays by a seeded
--   roll (stream "eggs") that depends on the season and on how well the flock was fed and watered.
-- Goats (D71): the same shape, kept in world.state.animals.goats. The herd is the ledger resource
--   "goat", housed by goat pens (storage). The manger holds hay (ledger "hay"), the trough water, and
--   the pail the milk the goats gave at `milkHour` (stream "milk"; goats dry off in winter and hold
--   their milk in a storm). Winter has no browse, so hay is the winter pressure; a cold snap raises it.
--   Tending the pen moves the milk into the ledger ("milk", the most perishable food).
-- Once a night at `predators.hour` a seeded roll (stream "predators") may bring a fox: more likely
-- in lean seasons and rough weather (Weather.threat, #97), less with the cat about, turned back by
-- the coop's door or the pen's fence plus the predator fence (stat `predatorGuard`), otherwise it takes
-- a hen or two, or one goat (goats are tougher: a bonus guard, and less likely a target).
-- Idle-friendly: the routine's `animals` category tends the coop (tend_coop) and the pen (tend_pen).
--
-- State: world.state.animals = { feed, water, nest, fed, wet (share of need met at the last care),
--   hungryDays, thirstyDays (consecutive short days), careDay, layDay, raidDay (last day each ran),
--   laid, collected, lost, raids, stopped (lifetime counts), nestFullDay,
--   goats = { feed (hay), water, pail, fed, wet, hungryDays, thirstyDays, careDay, milkDay,
--             milked, collected, lost (lifetime), pailFullDay } }
-- Emits "animals.collected" { count } (eggs), "animals.milked" { count }, "animals.tended" { eggs, feed,
-- kind }, "animals.laid" { count }, "animals.nestFull" { lost }, "animals.pailFull" { lost },
-- "animals.short" { feed, water, kind }, "animals.lost" { reason, hens?, goats?, kind },
-- "animals.predator" { day, killed, stopped, kind } with kind = "hens" | "goats".

local Calendar = require("src.sim.systems.calendar")
local Cat = require("src.sim.systems.cat")
local Compost = require("src.sim.systems.compost")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Stats = require("src.sim.stats")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")

local Animals = {}

local HEN, EGG, FEED = "hen", "egg", "chicken_feed"
local GOAT, MILK, HAY = "goat", "milk", "hay"

local function state(world)
  return world.state.animals
end

local function objDef(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id)
end

-- Sum of a house field over every placed building with `part` ("coop" or "pen").
local function total(world, part, field)
  local sum = 0
  for _, anchor in ipairs(Grid.anchorsWith(world, part)) do
    sum = sum + objDef(world, anchor)[part][field]
  end
  return sum
end

local function coopTotal(world, field)
  return total(world, "coop", field)
end

local function penTotal(world, field)
  return total(world, "pen", field)
end

--- Is any coop placed?
function Animals.hasCoop(world)
  return #Grid.anchorsWith(world, "coop") > 0
end

--- Is any goat pen placed?
function Animals.hasPen(world)
  return #Grid.anchorsWith(world, "pen") > 0
end

--- Hens in the flock.
function Animals.hens(world)
  return Ledger.get(world, HEN)
end

--- Goats in the herd.
function Animals.goats(world)
  return Ledger.get(world, GOAT)
end

--- Hens the placed coops can house.
function Animals.housing(world)
  return Ledger.capacity(world, HEN)
end

--- Goats the placed pens can house.
function Animals.goatHousing(world)
  return Ledger.capacity(world, GOAT)
end

--- Eggs waiting in the nest box.
function Animals.nest(world)
  return state(world).nest
end

--- Milk waiting in the pail.
function Animals.pail(world)
  return state(world).goats.pail
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

--- Hay units the herd needs from the manger on a day in the current season (more in a cold snap).
function Animals.hayNeed(world)
  local cfg = world.tuning.animals.goats
  local need = Animals.goats(world) * cfg.feedPerGoat * cfg.feedShare[Calendar.now(world).season]
  if Weather.isColdSnap(world) then
    need = need * cfg.coldSnapFeed
  end
  return need
end

--- Water units the herd drinks on a day.
function Animals.goatWaterNeed(world)
  return Animals.goats(world) * world.tuning.animals.goats.waterPerGoat
end

--- Chance (0..1) that a night's raid is turned back. Hens: the best coop door plus the fence, capped.
--- Goats: the best pen fence plus the fence and the herd's own toughness, capped.
function Animals.guard(world, kind)
  local cfg = world.tuning.animals.predators
  local best = 0
  if kind == "goats" then
    for _, anchor in ipairs(Grid.anchorsWith(world, "pen")) do
      best = math.max(best, objDef(world, anchor).pen.guard)
    end
    best = best + cfg.goatGuard
  else
    for _, anchor in ipairs(Grid.anchorsWith(world, "coop")) do
      best = math.max(best, objDef(world, anchor).coop.guard)
    end
  end
  return math.min(cfg.maxGuard, best + Stats.modifier(world, "predatorGuard"))
end

--- Probability that a predator comes tonight (before the defences): season, weather, cat.
function Animals.raidChance(world)
  local cfg = world.tuning.animals.predators
  local p = cfg.chancePerDay * cfg.seasons[Calendar.now(world).season] * Weather.threat(world)
  if Cat.present(world) then
    p = p * cfg.catFactor
  end
  return math.min(1, p)
end

--- Probability that tonight's raid takes animals of `kind` (default hens): it comes and the defences fail.
function Animals.dangerTonight(world, kind)
  return Animals.raidChance(world) * (1 - Animals.guard(world, kind))
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

--- Facts for the UI about the herd (same shape as info, with pail for nest and hay for feed).
function Animals.goatInfo(world)
  local g = state(world).goats
  local need = Animals.hayNeed(world)
  local stock = Ledger.get(world, HAY)
  return {
    goats = Animals.goats(world),
    housing = Animals.goatHousing(world),
    pail = g.pail,
    pailCap = penTotal(world, "pail"),
    feed = g.feed,
    feedCap = penTotal(world, "manger"),
    stock = stock,
    water = g.water,
    waterCap = penTotal(world, "trough"),
    feedDays = need > 0 and (g.feed + stock) / need or math.huge,
    hungryDays = g.hungryDays,
    thirstyDays = g.thirstyDays,
    guard = Animals.guard(world, "goats"),
    milked = g.milked,
    lost = g.lost,
  }
end

--- Days the animals' feed lasts at today's need (the shortest across hens and goats; math.huge when
--- none are kept). The animal warning (alerts.lua) is judged on this.
function Animals.feedDaysLeft(world)
  local days = math.huge
  if Animals.hens(world) > 0 then
    days = math.min(days, Animals.info(world).feedDays)
  end
  if Animals.goats(world) > 0 then
    days = math.min(days, Animals.goatInfo(world).feedDays)
  end
  return days
end

-- Tending ---------------------------------------------------------------------------------------

local function eggsReady(world)
  return state(world).nest > 0 and Ledger.room(world, EGG) >= 1
end

local function milkReady(world)
  return state(world).goats.pail > 0 and Ledger.room(world, MILK) >= 1
end

-- Feed units a tend would move into the feeder (whole units only).
local function feedToAdd(world)
  local s = state(world)
  return math.max(0, math.min(coopTotal(world, "feeder") - s.feed, math.floor(Ledger.get(world, FEED))))
end

-- Hay units a tend would move into the manger (whole units only).
local function hayToAdd(world)
  local g = state(world).goats
  return math.max(0, math.min(penTotal(world, "manger") - g.feed, math.floor(Ledger.get(world, HAY))))
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

--- Is there anything a tap on the pen would do: milk to collect, hay to add, water to top up?
function Animals.canTendPen(world)
  if not Animals.hasPen(world) then
    return false
  end
  if milkReady(world) then
    return true
  end
  if Animals.goats(world) == 0 then
    return false
  end
  local g, cfg = state(world).goats, world.tuning.animals.goats
  local mangerLow = g.feed <= penTotal(world, "manger") * cfg.topUpBelow
  local troughLow = g.water <= penTotal(world, "trough") * cfg.topUpBelow
  return (mangerLow and hayToAdd(world) >= 1) or troughLow
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

--- Should the idle routine make a trip to the pen: enough milk (it spoils fast), or a low manger or trough?
function Animals.needsTendingPen(world)
  if not Animals.hasPen(world) then
    return false
  end
  local g, cfg = state(world).goats, world.tuning.animals.goats
  if milkReady(world) and g.pail >= cfg.collectMin then
    return true
  end
  if Animals.goats(world) == 0 then
    return false
  end
  local mangerLow = g.feed < penTotal(world, "manger") * cfg.tendBelow
  local troughLow = g.water < penTotal(world, "trough") * cfg.tendBelow
  return (mangerLow and hayToAdd(world) >= 1) or troughLow
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
  local manure = Compost.rake(world, "hens") -- the chore also rakes the house out for the compost bin (D181)
  world.events:emit("animals.tended", { eggs = eggs, feed = feed, kind = "hens", manure = manure })
  return eggs, feed
end

--- Do the pen chore: collect the milk that fits, top up manger (hay from the ledger) and trough.
--- Returns milk collected, hay units added.
function Animals.tendPen(world)
  local g = state(world).goats
  local milk = 0
  if g.pail > 0 then
    milk = math.min(g.pail, math.floor(Ledger.room(world, MILK)))
    if milk > 0 then
      Ledger.add(world, MILK, milk, "milking")
      g.pail = g.pail - milk
      g.collected = g.collected + milk
      world.events:emit("animals.milked", { count = milk })
    end
  end
  local hay = 0
  if Animals.goats(world) > 0 then
    hay = hayToAdd(world)
    if hay > 0 and Ledger.remove(world, HAY, hay, "manger") then
      g.feed = g.feed + hay
    else
      hay = 0
    end
    g.water = penTotal(world, "trough")
  end
  local manure = Compost.rake(world, "goats")
  world.events:emit("animals.tended", { milk = milk, feed = hay, kind = "goats", manure = manure })
  return milk, hay
end

-- The daily rounds -------------------------------------------------------------------------------

-- A herd or flock eats and drinks what its feeder and waterer hold. Updates the share of need met and
-- the run of short days; returns "thirst" or "hunger" when an animal should be lost today, else nil.
local function eatAndDrink(st, cfg, needFeed, needWater)
  local ate = math.min(st.feed, needFeed)
  st.feed = st.feed - ate
  local drank = math.min(st.water, needWater)
  st.water = st.water - drank
  st.fed = needFeed > 0 and ate / needFeed or 1
  st.wet = needWater > 0 and drank / needWater or 1
  st.hungryDays = st.fed < cfg.hungryBelow and st.hungryDays + 1 or 0
  st.thirstyDays = st.wet < cfg.hungryBelow and st.thirstyDays + 1 or 0
  return st.thirstyDays > cfg.thirstAfter and "thirst" or st.hungryDays > cfg.starveAfter and "hunger" or nil
end

--- The hens eat and drink for the day. Returns fed share, watered share (1 with no flock).
function Animals.care(world)
  local s, cfg = state(world), world.tuning.animals.hens
  s.careDay = Calendar.now(world).day
  local hens = Animals.hens(world)
  if hens == 0 then
    return 1, 1
  end
  local reason = eatAndDrink(s, cfg, Animals.feedNeed(world), Animals.waterNeed(world))
  if s.fed < 1 or s.wet < 1 then
    world.events:emit("animals.short", { feed = s.fed < 1, water = s.wet < 1, kind = "hens" })
  end
  if reason and Ledger.remove(world, HEN, 1, "neglect") then
    s.lost = s.lost + 1
    world.events:emit("animals.lost", { reason = reason, hens = Animals.hens(world), kind = "hens" })
  end
  return s.fed, s.wet
end

--- The goats eat and drink for the day. Returns fed share, watered share (1 with no herd).
function Animals.careGoats(world)
  local g, cfg = state(world).goats, world.tuning.animals.goats
  g.careDay = Calendar.now(world).day
  if Animals.goats(world) == 0 then
    return 1, 1
  end
  local reason = eatAndDrink(g, cfg, Animals.hayNeed(world), Animals.goatWaterNeed(world))
  if g.fed < 1 or g.wet < 1 then
    world.events:emit("animals.short", { feed = g.fed < 1, water = g.wet < 1, kind = "goats" })
  end
  if reason and Ledger.remove(world, GOAT, 1, "neglect") then
    g.lost = g.lost + 1
    world.events:emit("animals.lost", { reason = reason, goats = Animals.goats(world), kind = "goats" })
  end
  return g.fed, g.wet
end

--- Probability that one hen lays today, given the season and how the flock was fed and watered.
function Animals.layChance(world)
  local s, cfg = state(world), world.tuning.animals.hens
  local fed = cfg.hungryLay + (1 - cfg.hungryLay) * s.fed
  local wet = cfg.thirstyLay + (1 - cfg.thirstyLay) * s.wet
  return cfg.layChance[Calendar.now(world).season] * fed * wet
end

--- Probability that one goat gives milk today: the season, how the herd was fed and watered, and the
--- weather (storm days).
function Animals.milkChance(world)
  local g, cfg = state(world).goats, world.tuning.animals.goats
  local fed = cfg.hungryMilk + (1 - cfg.hungryMilk) * g.fed
  local wet = cfg.thirstyMilk + (1 - cfg.thirstyMilk) * g.wet
  local p = cfg.milkChance[Calendar.now(world).season] * fed * wet
  if Weather.kind(world) == "storm" then
    p = p * cfg.stormMilk
  end
  return p
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

--- Today's milking: each goat rolls once on the "milk" stream (the chance and the yield are both
--- always drawn, so the stream does not depend on how the herd was fed). Returns milk put in the pail.
function Animals.milking(world)
  local g, cfg = state(world).goats, world.tuning.animals.goats
  g.milkDay = Calendar.now(world).day
  local goats = Animals.goats(world)
  if goats == 0 then
    return 0
  end
  local rng, chance = world:rng("milk"), Animals.milkChance(world)
  local given = 0
  for _ = 1, goats do
    local roll = rng:float()
    local amount = rng:int(cfg.milkYield.min, cfg.milkYield.max)
    if roll < chance then
      given = given + amount
    end
  end
  local stored = math.max(0, math.min(given, penTotal(world, "pail") - g.pail))
  g.pail = g.pail + stored
  g.milked = g.milked + stored
  if stored > 0 then
    world.events:emit("animals.milkGiven", { count = stored })
  end
  if stored < given and g.pailFullDay ~= g.milkDay then
    g.pailFullDay = g.milkDay
    world.events:emit("animals.pailFull", { lost = given - stored })
  end
  return stored
end

--- Tonight's raid, rolled now. Returns "stopped" (the defences held), "raided" (animals were taken) or
--- nil (no predator, no animals, or too early in the run). All rolls and the loss are always drawn, so
--- the stream does not depend on the defences. With both kept, a goat is a likelier target the more
--- goats there are, but each is worth `goatWeight` of a hen as prey.
function Animals.raid(world)
  local s, cfg = state(world), world.tuning.animals.predators
  local day = Calendar.now(world).day
  s.raidDay = day
  local hens, goats = Animals.hens(world), Animals.goats(world)
  if hens == 0 and goats == 0 then
    return nil
  end
  local rng = world:rng("predators")
  local hit = rng:chance(Animals.raidChance(world))
  local guardRoll = rng:float()
  local loss = rng:int(cfg.loss.min, cfg.loss.max)
  local goatLoss, targetRoll = 0, 0
  if goats > 0 then -- hens-only runs draw exactly what they drew before goats
    goatLoss = rng:int(cfg.goatLoss.min, cfg.goatLoss.max)
    targetRoll = rng:float()
  end
  if not hit or day < cfg.firstDay then
    return nil
  end
  local kind = "hens"
  if goats > 0 then
    local henWeight, goatWeight = hens, goats * cfg.goatWeight
    if hens == 0 or targetRoll >= henWeight / (henWeight + goatWeight) then
      kind = "goats"
    end
  end
  s.raids = s.raids + 1
  if guardRoll < Animals.guard(world, kind) then
    s.stopped = s.stopped + 1
    world.events:emit("animals.predator", { day = day, killed = 0, stopped = true, kind = kind })
    return "stopped"
  end
  local killed
  if kind == "goats" then
    killed = math.min(goats, goatLoss)
    Ledger.remove(world, GOAT, killed, "predator")
    s.goats.lost = s.goats.lost + killed
  else
    killed = math.min(hens, loss)
    Ledger.remove(world, HEN, killed, "predator")
    s.lost = s.lost + killed
  end
  world.events:emit("animals.predator", { day = day, killed = killed, stopped = false, kind = kind })
  return "raided"
end

local function register(world, id, verb, clickOrder, part, ready, canTend, needsTending, store, tend)
  Tasks.register(world, {
    id = id,
    category = "animals",
    verb = verb,
    clickOrder = clickOrder,
    candidates = function(w, _, add)
      if needsTending(w) then
        for _, anchor in ipairs(Grid.anchorsWith(w, part)) do
          add(anchor)
        end
      end
    end,
    canDo = function(w, _, i, order)
      local def = Grid.object(w, i)
      if not (def and def[part]) then
        return false
      end
      if order then
        return canTend(w)
      end
      return needsTending(w)
    end,
    blocked = function(w, _, i, order)
      local def = Grid.object(w, i)
      if order and def and def[part] and not canTend(w) and ready(w) > 0 and Ledger.room(w, store) < 1 then
        return store
      end
      return nil
    end,
    workTime = function(w)
      return w.tuning.animals[part == "coop" and "hens" or "goats"].tendTime
    end,
    complete = function(w)
      tend(w)
    end,
  })
end

function Animals.init(world)
  local s = world.state.animals or {}
  world.state.animals = s
  -- A fresh run starts empty: fill in the fields.
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
  local g = s.goats or {}
  s.goats = g
  g.feed = g.feed or 0
  g.water = g.water or 0
  g.pail = g.pail or 0
  g.fed = g.fed or 1
  g.wet = g.wet or 1
  g.hungryDays = g.hungryDays or 0
  g.thirstyDays = g.thirstyDays or 0
  g.careDay = g.careDay or 0
  g.milkDay = g.milkDay or 0
  g.milked = g.milked or 0
  g.collected = g.collected or 0
  g.lost = g.lost or 0
  g.pailFullDay = g.pailFullDay or 0

  register(world, "tend_coop", "Tend hens", 70, "coop", function(w)
    return state(w).nest
  end, Animals.canTend, Animals.needsTending, EGG, Animals.tend)
  register(world, "tend_pen", "Tend goats", 71, "pen", function(w)
    return state(w).goats.pail
  end, Animals.canTendPen, Animals.needsTendingPen, MILK, Animals.tendPen)
end

function Animals.tick(world)
  local s, cfg = state(world), world.tuning.animals
  local now = Calendar.now(world)
  if now.hour >= cfg.hens.layHour and s.layDay < now.day then
    Animals.lay(world)
  end
  if now.hour >= cfg.goats.milkHour and s.goats.milkDay < now.day then
    Animals.milking(world)
  end
  if now.hour >= cfg.hens.careHour and s.careDay < now.day then
    Animals.care(world)
  end
  if now.hour >= cfg.goats.careHour and s.goats.careDay < now.day then
    Animals.careGoats(world)
  end
  if now.hour >= cfg.predators.hour and s.raidDay < now.day then
    Animals.raid(world)
  end
end

return Animals
