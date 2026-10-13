-- Goats (GDD §7.7, D71): a pen, a herd with needs, milk, cheese, winter hay, the trailer and the pen's
-- defences, all on the chicken framework (src/sim/systems/animals.lua).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Alerts = require("src.sim.systems.alerts")
local Animals = require("src.sim.systems.animals")
local Cat = require("src.sim.systems.cat")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Processing = require("src.sim.systems.processing")
local Spoilage = require("src.sim.systems.spoilage")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg, pred = tun.animals.goats, tun.animals.predators
local DPS = tun.time.daysPerSeason
local SPRING, SUMMER, AUTUMN, WINTER = 1, DPS + 1, 2 * DPS + 1, 3 * DPS + 1

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function force(world, kind)
  world.state.weather.sky.days[1] = kind
end

local function with(overrides, fn)
  local saved = {}
  for _, o in ipairs(overrides) do
    saved[#saved + 1] = { o[1], o[2], o[1][o[2]] }
    o[1][o[2]] = o[3]
  end
  local ok, err = pcall(fn)
  for _, s in ipairs(saved) do
    s[1][s[2]] = s[3]
  end
  assert(ok, err)
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

--- The free tile for `id` nearest the truck (so the homesteader can walk to it).
local function spotFor(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, require("src.sim.systems.land").spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  return best
end

--- A summer day-5 morning with a pen placed and `n` goats (clear skies). Returns world, pen tile.
local function penWorld(n, seed)
  local world = newWorld(seed)
  local spot = spotFor(world, "goat_pen")
  T.truthy(spot, "a spot for the pen")
  Inventory.addObject(world, "goat_pen")
  T.truthy(Inventory.place(world, "goat_pen", spot))
  Ledger.add(world, "goat", n or 3, "test")
  setTime(world, SUMMER + 4, cfg.milkHour - 1)
  force(world, "clear")
  return world, spot
end

-- Content ---------------------------------------------------------------------------------------

T.test("goats content: pen, goats, milk, hay, cheese, trailer, notes and art all line up", function()
  local sprites = require("assets.manifest").sprites
  local pen = reg:get("objects", "goat_pen")
  T.truthy(pen.placeable and pen.pen and pen.storage.goat > 0)
  T.truthy(pen.pen.pail > 0 and pen.pen.manger > 0 and pen.pen.trough > 0)
  T.truthy(pen.pen.guard > 0 and pen.pen.guard + pred.goatGuard < pred.maxGuard)
  T.eq(reg:get("resources", "goat").category, "animal")
  T.eq(reg:get("resources", "goat").capacity, 0, "goats live only where a pen gives them room")
  local milk = reg:get("resources", "milk")
  T.truthy(milk.calories and milk.value and tun.food.shelfLife.byCategory[milk.category] <= 2, "milk is food, sells, and spoils fast")
  T.truthy(reg:get("resources", "cheese").category == "preserved" and not Spoilage.perishable(newWorld(), "cheese"))
  T.truthy(reg:get("resources", "cheese").value > reg:get("resources", "milk").value * 2, "cheese sells for more than the milk in it")
  for _, name in ipairs({ "goat_pen", "cheese_press", "goat", "icon_goat", "icon_milk", "icon_hay", "icon_cheese", "icon_goat_pen", "icon_goat_trailer", "icon_cheese_press" }) do
    T.truthy(sprites[name], name .. " sprite")
  end
  for _, id in ipairs({ "goat_pen", "goat_trailer", "goats", "hay_bales", "cheese_press" }) do
    local item = reg:get("catalog", id)
    T.eq(item.page, "animals", id)
    T.truthy(#item.needs > 0, id .. " is a journal idea, not a starter item")
    for _, note in ipairs(item.needs) do
      T.truthy(reg:has("notes", note), id .. " needs note " .. note)
    end
  end
  local goats = reg:get("catalog", "goats")
  T.truthy(goats.pickupOnly and goats.requires == "goat_trailer", "goats ride home on the trailer")
  T.truthy(reg:get("catalog", "goat_trailer").equipment)
  T.truthy(goats.gives.goat <= pen.storage.goat, "a first purchase fits an empty pen")
  T.truthy(reg:get("catalog", "goat_pen").gives.hay <= reg:get("resources", "hay").capacity)
  T.truthy(pen.pen.pail <= milk.capacity, "a full pail fits the milk store")
end)

T.test("goats: the pen, goats and trailer wait for chickens and a frost; milk teaches hay and cheese", function()
  local world = newWorld()
  T.eq(Journal.isIdea(world, "goat_pen"), false)
  world.events:emit("animals.collected", { count = 2 })
  T.eq(Journal.isIdea(world, "goat_pen"), false, "eggs alone are not enough")
  world.events:emit("weather.froze", {})
  T.truthy(Journal.isIdea(world, "goat_pen"))
  T.truthy(Journal.isIdea(world, "goats"))
  T.eq(Journal.isIdea(world, "hay_bales"), false, "hay refills wait for the first milk")
  T.eq(Journal.isIdea(world, "cheese_press"), false)
  world.events:emit("animals.milked", { count = 3 })
  T.truthy(Journal.isIdea(world, "hay_bales"))
  T.eq(Journal.isIdea(world, "cheese_press"), false, "cheese also waits for the first spoiled produce")
  world.events:emit("food.spoiled", { resource = "radish", category = "food", amount = 1 })
  T.truthy(Journal.isIdea(world, "cheese_press"))
  T.eq(Journal.isIdea(world, "goat_trailer"), false)
  world.events:emit("market.trip", {})
  T.truthy(Journal.isIdea(world, "goat_trailer"))
end)

-- Housing and the trailer ------------------------------------------------------------------------

T.test("goats: they need a pen and the trailer, and a full pen leaves new goats waiting", function()
  local world = newWorld()
  T.eq(Ledger.add(world, "goat", 2), 0, "no pen, no room")
  world.state.market.inTown = true
  Ledger.add(world, "money", 300)
  world.meta.journal = world.meta.journal or { known = {} }
  world.meta.journal.known.goats = true
  world.meta.journal.known.goat_trailer = true
  T.eq(Market.cannotBuy(world, "goats", true), "needs a pen")
  local spot = spotFor(world, "goat_pen")
  Inventory.addObject(world, "goat_pen")
  T.truthy(Inventory.place(world, "goat_pen", spot))
  T.eq(Animals.goatHousing(world), 3)
  T.eq(Market.cannotBuy(world, "goats", true), "needs the goat trailer")
  T.eq(Market.cannotBuy(world, "goats", false), "pickup only")
  -- The trailer is an ordinary equipment order that arrives next morning.
  T.truthy(Market.order(world, "goat_trailer"))
  for _ = 1, math.floor(tun.time.dayLength * 1.2 / STEP) do
    world:tick(STEP)
  end
  T.truthy(Inventory.hasEquipment(world, "goat_trailer"), "delivered")
  T.eq(Market.cannotBuy(world, "goats", true), nil)
  T.truthy(Market.buyInTown(world, "goats"))
  T.eq(Animals.goats(world), 2)
  T.eq(Market.cannotBuy(world, "goats", true), "no room", "one slot left, a pair does not fit")
end)

-- Needs ------------------------------------------------------------------------------------------

T.test("goats: the herd eats a season's share of hay, more in a cold snap, and drinks daily", function()
  local world = penWorld(3)
  local s = world.state.animals.goats
  s.feed, s.water = 18, 6
  setTime(world, SUMMER + 4, cfg.careHour + 0.1)
  local before = s.feed
  Animals.careGoats(world)
  T.truthy(math.abs((before - s.feed) - 3 * cfg.feedPerGoat * cfg.feedShare.summer) < 1e-9)
  T.truthy(math.abs((6 - s.water) - 3 * cfg.waterPerGoat) < 1e-9)
  T.eq(s.fed, 1)
  setTime(world, WINTER + 1, cfg.careHour + 0.1)
  local winter = Animals.hayNeed(world)
  T.truthy(math.abs(winter - 3 * cfg.feedPerGoat) < 1e-9, "winter has no browse")
  local w = require("src.sim.systems.weather")
  local original = w.isColdSnap
  local function need(snap)
    w.isColdSnap = function()
      return snap
    end
    local n = Animals.hayNeed(world)
    w.isColdSnap = original
    return n
  end
  T.truthy(math.abs(need(true) - need(false) * cfg.coldSnapFeed) < 1e-9, "a cold snap burns more hay")
end)

T.test("goats: a herd with nothing to eat is hungry, then loses a goat a day after a grace period", function()
  local world = penWorld(3)
  local s = world.state.animals.goats
  local lost = collect(world, "animals.lost")
  local short = collect(world, "animals.short")
  s.water = 6
  for d = 1, cfg.starveAfter do
    setTime(world, SPRING + d, cfg.careHour + 0.1)
    s.water = 6
    Animals.careGoats(world)
    T.eq(Animals.goats(world), 3, "grace day " .. d)
  end
  T.eq(s.hungryDays, cfg.starveAfter)
  T.truthy(#short > 0 and short[1].kind == "goats" and short[1].feed)
  setTime(world, SPRING + cfg.starveAfter + 1, cfg.careHour + 0.1)
  s.water = 6
  Animals.careGoats(world)
  T.eq(Animals.goats(world), 2, "then one goat a day")
  T.eq(lost[#lost].reason, "hunger")
  T.eq(lost[#lost].kind, "goats")
  -- A tended herd recovers: the run of hungry days resets.
  s.feed, s.water = 6, 6
  setTime(world, SPRING + 20, cfg.careHour + 0.1)
  Animals.careGoats(world)
  T.eq(s.hungryDays, 0)
end)

T.test("goats: thirst is quicker than hunger, and no goats means no needs", function()
  T.truthy(cfg.thirstAfter < cfg.starveAfter)
  local world = penWorld(3)
  local s = world.state.animals.goats
  for d = 1, cfg.thirstAfter + 1 do
    setTime(world, SPRING + d, cfg.careHour + 0.1)
    s.feed = 18
    Animals.careGoats(world)
  end
  T.eq(Animals.goats(world), 2)
  local empty = penWorld(0)
  local events = collect(empty, "animals.short")
  setTime(empty, SPRING + 3, cfg.careHour + 0.1)
  local fed, wet = Animals.careGoats(empty)
  T.eq(fed, 1)
  T.eq(wet, 1)
  T.eq(#events, 0)
  T.eq(Animals.feedDaysLeft(empty), math.huge)
end)

-- Milk -------------------------------------------------------------------------------------------

local function milkRun(seed, days)
  local world = penWorld(3, seed)
  local s = world.state.animals.goats
  local got = {}
  for d = 0, days - 1 do
    setTime(world, SUMMER + d, cfg.milkHour + 0.1)
    s.pail = 0
    got[#got + 1] = Animals.milking(world)
  end
  return got
end

T.test("goats: milk yield is deterministic per seed and tracks the season's chance", function()
  local a, b = milkRun(7, 10), milkRun(7, 10)
  T.eq(table.concat(a, ","), table.concat(b, ","))
  T.truthy(table.concat(a, ",") ~= table.concat(milkRun(8, 10), ","), "another seed milks differently")
  local summer = 0
  for seed = 1, 3 do
    for _, n in ipairs(milkRun(seed, DPS)) do
      summer = summer + n
    end
  end
  local world = penWorld(3, 3)
  local winter = 0
  local s = world.state.animals.goats
  for d = 0, DPS * 3 - 1 do
    setTime(world, WINTER + (d % DPS), cfg.milkHour + 0.1)
    s.pail = 0
    winter = winter + Animals.milking(world)
  end
  T.truthy(summer > winter * 3, "goats dry off in winter")
  -- The expected yield is the chance times the average yield per goat per day.
  local mean = (cfg.milkYield.min + cfg.milkYield.max) / 2
  local expected = 3 * DPS * 3 * cfg.milkChance.summer * mean -- 3 goats, a week, 3 seeds
  T.truthy(math.abs(summer - expected) < expected * 0.35, string.format("%d milk vs about %.0f", summer, expected))
end)

T.test("goats: hungry or thirsty goats give less milk, and a storm holds it back", function()
  local world = penWorld(3)
  setTime(world, SUMMER + 4, cfg.milkHour + 0.1)
  local fine = Animals.milkChance(world)
  local s = world.state.animals.goats
  s.fed = 0
  T.truthy(math.abs(Animals.milkChance(world) - fine * cfg.hungryMilk) < 1e-9)
  s.fed, s.wet = 1, 0
  T.truthy(math.abs(Animals.milkChance(world) - fine * cfg.thirstyMilk) < 1e-9)
  s.wet = 1
  force(world, "storm")
  T.truthy(math.abs(Animals.milkChance(world) - fine * cfg.stormMilk) < 1e-9)
end)

T.test("goats: milk waits in the pail until tended, then goes to the ledger and spoils fast", function()
  local world = penWorld(3)
  local s = world.state.animals.goats
  s.pail = 5
  local events = collect(world, "animals.milked")
  Animals.tendPen(world)
  T.eq(s.pail, 0)
  T.eq(Ledger.get(world, "milk"), 5)
  T.eq(events[1].count, 5)
  T.eq(s.collected, 5)
  -- Milk is a batch like any other food (D73): fresh tonight, gone soon after its short shelf life.
  local info = Spoilage.info(world, "milk")
  T.truthy(info.shelfLife <= 2, "milk keeps only a couple of days")
  T.eq(info.tonight, 0, "fresh milk does not rot tonight")
  T.falsy(info.warn)
  Spoilage.ageStock(world, "milk", info.shelfLife)
  T.truthy(Spoilage.info(world, "milk").warn, "the pantry warns once it is at the end of its shelf life")
end)

T.test("goats: a full milk store holds milk in the pail, and a full pail stops the milking (D59)", function()
  local world = penWorld(3)
  local s = world.state.animals.goats
  Ledger.setCapacity(world, "milk", 2)
  s.pail = 5
  Animals.tendPen(world)
  T.eq(Ledger.get(world, "milk"), 2)
  T.eq(s.pail, 3, "the rest waits in the pail")
  local full = collect(world, "animals.pailFull")
  with({ { cfg, "milkChance", { spring = 1, summer = 1, autumn = 1, winter = 1 } } }, function()
    s.pail = reg:get("objects", "goat_pen").pen.pail - 1
    setTime(world, SUMMER + 5, cfg.milkHour + 0.1)
    Animals.milking(world)
    T.eq(s.pail, reg:get("objects", "goat_pen").pen.pail, "the pail tops out")
    T.eq(#full, 1)
    setTime(world, SUMMER + 5, cfg.milkHour + 0.2)
    Animals.milking(world)
    T.eq(#full, 1, "said once a day")
  end)
end)

T.test("goats: tending tops up the manger from the hay stock and the trough for free", function()
  local world = penWorld(3)
  local s = world.state.animals.goats
  local pen = reg:get("objects", "goat_pen").pen
  Ledger.add(world, "hay", 10)
  s.feed, s.water = 0, 0
  Animals.tendPen(world)
  T.eq(s.feed, 10)
  T.eq(Ledger.get(world, "hay"), 0)
  T.eq(s.water, pen.trough)
  Ledger.add(world, "hay", 40)
  Animals.tendPen(world)
  T.eq(s.feed, pen.manger, "the manger holds what it holds")
  T.eq(Ledger.get(world, "hay"), 40 - (pen.manger - 10))
end)

-- The chore --------------------------------------------------------------------------------------

T.test("goats: the routine tends the pen when milk piles up or the manger runs low", function()
  local world = penWorld(3)
  local hs = Actors.homesteader(world)
  local s = world.state.animals.goats
  s.feed, s.water = 18, 6
  s.pail = cfg.collectMin - 1
  local function chore()
    local job = Tasks.chooseIdleJob(world, hs)
    return job and job.task == "tend_pen"
  end
  T.falsy(chore(), "three milk and full bowls: nothing worth a trip")
  s.pail = cfg.collectMin
  T.truthy(chore(), "enough milk")
  s.pail = 0
  s.water = 1
  T.truthy(chore(), "trough low")
  s.water = 6
  s.feed = 3
  T.falsy(chore(), "manger low but no hay to add")
  Ledger.add(world, "hay", 5)
  T.truthy(chore(), "manger low and bales in store")
  Tasks.setPriorityEnabled(world, "animals", false)
  T.falsy(chore())
end)

T.test("goats: a tap on the pen orders the chore, and the homesteader milks", function()
  local world, spot = penWorld(3)
  local hs = Actors.homesteader(world)
  local s = world.state.animals.goats
  s.pail = 3
  local taskType = Actors.order(world, hs, spot)
  T.truthy(taskType and taskType.id == "tend_pen")
  for _ = 1, 600 do
    world:tick(STEP)
  end
  T.eq(s.collected, 3)
  T.eq(Ledger.get(world, "milk"), 3)
  T.truthy(Actors.homesteader(world).job == nil, "the chore is done")
end)

T.test("goats: a tap that cannot collect names the full milk store", function()
  local world, spot = penWorld(3)
  local hs = Actors.homesteader(world)
  local s = world.state.animals.goats
  s.pail, s.water = 3, 6
  Ledger.setCapacity(world, "milk", 1)
  Ledger.add(world, "milk", 1)
  local taskType, full = Actors.order(world, hs, spot)
  T.falsy(taskType)
  T.eq(full, "milk")
end)

-- Cheese -----------------------------------------------------------------------------------------

T.test("goats: the cheese press turns two milk into one cheese, which keeps", function()
  local world = newWorld()
  local spot = spotFor(world, "cheese_press")
  Inventory.addObject(world, "cheese_press")
  T.truthy(Inventory.place(world, "cheese_press", spot))
  Ledger.add(world, "milk", 5)
  local done = collect(world, "processing.done")
  local hs = Actors.homesteader(world)
  local taskType = Actors.order(world, hs, spot)
  T.truthy(taskType and taskType.id == "load_station")
  for _ = 1, 600 do
    world:tick(STEP)
  end
  T.eq(Ledger.get(world, "milk"), 1, "an odd unit is left over")
  local batch = Processing.batch(world, spot)
  T.truthy(batch and batch.count == 2, "four milk make two cheese")
  for _ = 1, math.floor(reg:get("recipes", "make_cheese").hours * tun.time.dayLength / 24 / STEP) + 20 do
    world:tick(STEP)
  end
  T.eq(Ledger.get(world, "cheese"), 2)
  T.eq(done[1].output, "cheese")
  T.eq(Spoilage.info(world, "cheese"), nil, "cheese keeps")
  -- With one milk left the press has nothing to do.
  Ledger.remove(world, "milk", Ledger.get(world, "milk") - 1)
  local hs2 = Actors.homesteader(world)
  T.falsy(Actors.order(world, hs2, spot), "one milk does not make a cheese")
end)

T.test("goats: a placed cheese press is a way to preserve milk (spoilage and sorting know it)", function()
  local world = newWorld()
  T.eq(Spoilage.slowing(world).preserves.dairy, nil)
  Inventory.addObject(world, "cheese_press")
  T.truthy(Inventory.place(world, "cheese_press", spotFor(world, "cheese_press")))
  T.eq(Spoilage.slowing(world).preserves.dairy, true)
end)

-- Predators ---------------------------------------------------------------------------------------

local function raidNight(world)
  setTime(world, AUTUMN + 2, pred.hour + 0.25)
  force(world, "clear")
end

local function raidTally(maxGuard, setup)
  local raided, stopped = 0, 0
  with({ { pred, "chancePerDay", 1 }, { pred, "maxGuard", maxGuard } }, function()
    local world = penWorld(3, 11)
    if setup then
      setup(world)
    end
    raidNight(world)
    for _ = 1, 300 do
      Ledger.add(world, "goat", 3 - Animals.goats(world), "test")
      local result = Animals.raid(world)
      if result == "raided" then
        raided = raided + 1
      elseif result == "stopped" then
        stopped = stopped + 1
      end
    end
  end)
  return raided, stopped
end

T.test("goats: with no defences a raid takes a goat through the ledger", function()
  with({ { pred, "chancePerDay", 1 }, { pred, "maxGuard", 0 } }, function()
    local world = penWorld(3)
    raidNight(world)
    local events = collect(world, "animals.predator")
    T.eq(Animals.raid(world), "raided")
    T.eq(events[1].kind, "goats")
    T.eq(events[1].killed, 1)
    T.eq(Animals.goats(world), 2)
    T.eq(world.state.animals.goats.lost, 1)
  end)
end)

T.test("goats: the pen fence turns raids back, tougher than a coop door, and the fence helps more", function()
  local noGuard = raidTally(0)
  T.eq(noGuard, 300, "no guard: every raid lands")
  local raided, stopped = raidTally(pred.maxGuard)
  local expected = reg:get("objects", "goat_pen").pen.guard + pred.goatGuard
  T.truthy(math.abs(stopped / 300 - expected) < 0.1, string.format("%.2f stopped vs pen guard %.2f", stopped / 300, expected))
  T.truthy(expected > reg:get("objects", "chicken_coop").coop.guard, "goats defend better than hens")
  local fencedRaided = raidTally(pred.maxGuard, function(world)
    Inventory.addEquipment(world, "chicken_fence")
  end)
  T.truthy(fencedRaided < raided, "the predator fence covers the pen too")
  local world = penWorld(3)
  Inventory.addEquipment(world, "chicken_fence")
  T.truthy(Animals.guard(world, "goats") <= pred.maxGuard)
  T.truthy(raided > 0)
end)

T.test("goats: with hens as well the raid picks one, hens are likelier prey, and hen-only runs are unchanged", function()
  with({ { pred, "chancePerDay", 1 }, { pred, "maxGuard", 0 } }, function()
    local hensHit, goatsHit = 0, 0
    local world = penWorld(3, 5)
    local coop = spotFor(world, "chicken_coop")
    Inventory.addObject(world, "chicken_coop")
    T.truthy(Inventory.place(world, "chicken_coop", coop))
    raidNight(world)
    for _ = 1, 300 do
      Ledger.add(world, "goat", 3 - Animals.goats(world), "test")
      Ledger.add(world, "hen", 6 - Animals.hens(world), "test")
      Animals.raid(world)
      if Animals.hens(world) < 6 then
        hensHit = hensHit + 1
      end
      if Animals.goats(world) < 3 then
        goatsHit = goatsHit + 1
      end
    end
    T.eq(hensHit + goatsHit, 300, "one kind per raid")
    T.truthy(hensHit > goatsHit * 2, "six hens against three goats weighted by goatWeight")
  end)
  -- Hen-only draws are the ones chickens drew before goats existed (no extra draws).
  local function stream(withPen)
    local world = penWorld(0, 5)
    Ledger.add(world, "hen", 0)
    if withPen then
      Ledger.add(world, "goat", 0)
    end
    return world:rng("predators"):float()
  end
  T.eq(stream(false), stream(true))
end)

T.test("goats: no goats and no hens means no raid, and a raid is one stream whatever the fence", function()
  local world = penWorld(0)
  raidNight(world)
  T.eq(Animals.raid(world), nil)
  local function run(fence)
    local w = penWorld(3, 5)
    if fence then
      Inventory.addEquipment(w, "chicken_fence")
    end
    raidNight(w)
    Animals.raid(w)
    return w:rng("predators"):float()
  end
  T.eq(run(false), run(true))
  -- A cat keeps predators off the pen as well.
  local calm = Animals.raidChance(penWorld(3))
  local w2 = penWorld(3)
  Inventory.addEquipment(w2, Cat.ITEM)
  Cat.tick(w2, STEP)
  T.truthy(Animals.raidChance(w2) < calm)
end)

-- Warnings ---------------------------------------------------------------------------------------

T.test("goats: low hay turns the animal alert amber, then red, and raises one toast event", function()
  local world = penWorld(3)
  local s = world.state.animals.goats
  setTime(world, WINTER + 1, 10)
  s.feed = 0
  Ledger.add(world, "hay", 100 - 100)
  local raised = collect(world, "alert.raised")
  local need = Animals.hayNeed(world)
  T.eq((Alerts.level(world, "animals")), 2, "no hay at all")
  Ledger.add(world, "hay", math.floor(need * cfg.coldSnapFeed * 2))
  local level = Alerts.level(world, "animals")
  T.truthy(level >= 1, "two days of hay is amber")
  Ledger.add(world, "hay", 30)
  T.eq((Alerts.level(world, "animals")), 0)
  Ledger.remove(world, "hay", Ledger.get(world, "hay"))
  for _ = 1, math.ceil(2 / STEP) do
    world:tick(STEP)
  end
  T.truthy(#raised >= 1 and raised[#raised].kind == "animals")
  local none = newWorld()
  T.eq((Alerts.level(none, "animals")), 0, "no animals, no warning")
end)

-- Saves ------------------------------------------------------------------------------------------

T.test("goats: state survives a save round-trip and carries on the same", function()
  local world, spot = penWorld(3, 9)
  local s = world.state.animals.goats
  s.feed, s.water, s.pail = 9, 2, 4
  s.hungryDays = 1
  Ledger.add(world, "hay", 6)
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(serialize.encode(restored.state.animals), serialize.encode(world.state.animals))
  T.eq(Animals.goats(restored), 3)
  T.eq(Animals.goatHousing(restored), 3)
  T.eq(Grid.object(restored, spot).id, "goat_pen")
  for _, w in ipairs({ world, restored }) do
    setTime(w, SUMMER + 5, cfg.milkHour - 0.01)
    force(w, "clear")
    for _ = 1, 40 do
      w:tick(STEP)
    end
  end
  T.eq(serialize.encode(restored.state.animals), serialize.encode(world.state.animals))
end)

T.test("goats: a save from the chickens-only days loads, gains the goat state, and takes a pen later", function()
  local world = newWorld(4)
  local state = serialize.decode(serialize.encode(world.state))
  state.animals.goats = nil
  state.ledger.amounts.goat = nil
  state.ledger.amounts.milk = nil
  local old = World.new({ registry = reg, tuning = tun }, state)
  T.truthy(old.state.animals.goats)
  T.eq(old.state.animals.goats.pail, 0)
  T.eq(Animals.goats(old), 0)
  T.eq(Animals.pail(old), 0)
  for _ = 1, 100 do
    old:tick(STEP)
  end
  Inventory.addObject(old, "goat_pen")
  T.truthy(Inventory.place(old, "goat_pen", spotFor(old, "goat_pen")))
  T.eq(Ledger.add(old, "goat", 2), 2)
  -- A processing batch saved before `yield` existed (count = output units) still finishes.
  local legacy = newWorld(4)
  local ls = serialize.decode(serialize.encode(legacy.state))
  ls.processing = { [1] = { recipe = "smoke_fish", count = 2, remaining = 0 } }
  local loaded = World.new({ registry = reg, tuning = tun }, ls)
  for _ = 1, 5 do
    loaded:tick(STEP)
  end
  T.eq(Ledger.get(loaded, "smoked_fish"), 2)
end)

-- Balance sanity ---------------------------------------------------------------------------------

--- Net money of a three-goat herd over `days` days of a season: every milk sold at the town price,
--- all hay bought at the catalog price. Returns net $, milk made, hay eaten.
local function fortnight(startDay, days)
  local world = penWorld(3, 2)
  local s = world.state.animals.goats
  local bale = reg:get("catalog", "hay_bales")
  local hayPrice = bale.price / bale.gives.hay
  local milk, eaten = 0, 0
  for d = 0, days - 1 do
    setTime(world, startDay + d, cfg.milkHour + 0.1)
    s.water = 6
    s.feed = reg:get("objects", "goat_pen").pen.manger
    s.pail = 0
    local before = s.feed
    milk = milk + Animals.milking(world)
    setTime(world, startDay + d, cfg.careHour + 0.1)
    Animals.careGoats(world)
    eaten = eaten + (before - s.feed)
  end
  return milk * reg:get("resources", "milk").value - eaten * hayPrice, milk, eaten
end

T.test("goats: balance sanity, summer pays, winter pays nothing, and hay is the winter pressure", function()
  local summerNet, summerMilk, summerHay = fortnight(SUMMER, DPS)
  local winterNet, winterMilk, winterHay = fortnight(WINTER, DPS)
  T.truthy(summerNet > 0, "a summer week in the black")
  T.truthy(summerMilk > winterMilk * 4, "winter gives little milk")
  T.truthy(winterHay > summerHay * 3, "winter eats far more hay")
  T.truthy(winterNet < 0, "a winter herd is a cost the player plans for")
  T.truthy(winterNet > -3 * summerNet, "but not ruinous")
  -- The winter bill: a herd's week of hay fits the hay store with the pen's stack.
  local pen = reg:get("objects", "goat_pen")
  local need = 3 * cfg.feedPerGoat * cfg.feedShare.winter * DPS
  T.truthy(need <= reg:get("resources", "hay").capacity + pen.storage.hay, "a winter week of hay fits the store")
end)
