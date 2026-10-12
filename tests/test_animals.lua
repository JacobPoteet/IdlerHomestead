-- Chickens (GDD §7.7, D63): a coop, hens with needs, eggs, the tend chore and night predators.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Animals = require("src.sim.systems.animals")
local Cat = require("src.sim.systems.cat")
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local hens, pred = tun.animals.hens, tun.animals.predators
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

--- Run `fn` with tuning values overridden, then restore them.
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

--- The free tile for a coop nearest the truck (so the homesteader can walk to it).
local function coopSpot(world)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, require("src.sim.systems.land").spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, "chicken_coop", i) then
      best, bestDist = i, dist
    end
  end
  return best
end

--- A summer day-5 morning with a coop placed and `n` hens (clear skies). Returns world, coop tile.
local function coopWorld(n, seed)
  local world = newWorld(seed)
  local spot = coopSpot(world)
  T.truthy(spot, "a spot for the coop")
  Inventory.addObject(world, "chicken_coop")
  T.truthy(Inventory.place(world, "chicken_coop", spot))
  Ledger.add(world, "hen", n or 3, "test")
  setTime(world, SUMMER + 4, hens.layHour - 1)
  force(world, "clear")
  return world, spot
end

-- Content ---------------------------------------------------------------------------------------

T.test("animals content: coop, hens, eggs, feed, notes and art all line up", function()
  local sprites = require("assets.manifest").sprites
  local coop = reg:get("objects", "chicken_coop")
  T.truthy(coop.placeable and coop.coop and coop.storage.hen > 0)
  T.truthy(coop.coop.nest > 0 and coop.coop.feeder > 0 and coop.coop.waterer > 0)
  T.truthy(coop.coop.guard > 0 and coop.coop.guard < tun.animals.predators.maxGuard)
  T.eq(reg:get("resources", "hen").category, "animal")
  T.eq(reg:get("resources", "hen").capacity, 0, "hens live only where a coop gives them room")
  T.truthy(reg:get("resources", "egg").calories and reg:get("resources", "egg").value)
  for _, name in ipairs({ "chicken_coop", "hen", "icon_hen", "icon_egg", "icon_chicken_coop", "icon_chicken_feed", "icon_chicken_fence" }) do
    T.truthy(sprites[name], name .. " sprite")
  end
  for _, id in ipairs({ "chicken_coop", "hens", "chicken_feed", "chicken_fence" }) do
    local item = reg:get("catalog", id)
    T.eq(item.page, "animals", id)
    T.truthy(#item.needs > 0, id .. " is a journal idea, not a starter item")
    for _, note in ipairs(item.needs) do
      T.truthy(reg:has("notes", note), id .. " needs note " .. note)
    end
  end
  T.truthy(reg:get("catalog", "hens").pickupOnly, "animals ride home in the truck")
  T.truthy(reg:get("catalog", "chicken_fence").modifiers.predatorGuard > 0)
  local found = false
  for _, cat in ipairs(reg:all("task_categories")) do
    found = found or cat.id == "animals"
  end
  T.truthy(found, "the animals task category exists")
  local inChapter = false
  for _, chapter in ipairs(reg:all("chapters")) do
    for _, page in ipairs(chapter.pages) do
      inChapter = inChapter or (chapter.id == "animals" and page == "animals")
    end
  end
  T.truthy(inChapter, "the animals page belongs to the Animals chapter")
end)

T.test("animals: the coop is a journal idea once the harvest and town notes are written", function()
  local world = newWorld()
  T.eq(Journal.isIdea(world, "chicken_coop"), false)
  world.events:emit("crop.harvested", {})
  world.events:emit("market.trip", {})
  T.truthy(Journal.isIdea(world, "chicken_coop"))
  T.truthy(Journal.isIdea(world, "hens"))
  T.eq(Journal.isIdea(world, "chicken_feed"), false, "feed refills wait for the first eggs")
  world.events:emit("animals.collected", { count = 2 })
  T.truthy(Journal.isIdea(world, "chicken_feed"))
  world.events:emit("animals.predator", { day = 5, killed = 0, stopped = true })
  T.eq(Journal.isIdea(world, "chicken_fence"), false, "a raid turned back is no lesson")
  world.events:emit("animals.predator", { day = 6, killed = 1, stopped = false })
  T.truthy(Journal.isIdea(world, "chicken_fence"))
end)

-- Housing ---------------------------------------------------------------------------------------

T.test("animals: hens need a coop, and a full coop leaves new hens waiting", function()
  local world = newWorld()
  T.eq(Ledger.add(world, "hen", 3), 0, "no coop, no room")
  world.state.market.inTown = true
  Ledger.add(world, "money", 100)
  world.meta.journal = world.meta.journal or { known = {} }
  T.eq(Market.cannotBuy(world, "hens", true) == "unknown" or Market.cannotBuy(world, "hens", true) == "needs a coop", true)
  -- Know the item, then the housing is what is missing.
  world.meta.journal.known.hens = true
  T.eq(Market.cannotBuy(world, "hens", true), "needs a coop")
  local spot = coopSpot(world)
  Inventory.addObject(world, "chicken_coop")
  T.truthy(Inventory.place(world, "chicken_coop", spot))
  T.eq(Animals.housing(world), 6)
  T.eq(Market.cannotBuy(world, "hens", true), nil)
  T.truthy(Market.buyInTown(world, "hens"))
  T.eq(Animals.hens(world), 3)
  T.truthy(Market.buyInTown(world, "hens"))
  T.eq(Animals.hens(world), 6)
  T.eq(Market.cannotBuy(world, "hens", true), "no room", "a full coop refuses more hens, taking no money")
end)

T.test("animals: the coop never goes on the road", function()
  local world = newWorld()
  local grid = world.state.grid
  local placeable = 0
  for i = 1, #grid.terrain do
    if Inventory.canPlace(world, "chicken_coop", i) then
      placeable = placeable + 1
      local x, y = Grid.coords(grid, i)
      T.truthy(Grid.terrain(world, i).id ~= "road" and Grid.terrain(world, Grid.index(grid, x + 1, y)).id ~= "road", "tile " .. i)
    end
  end
  T.truthy(placeable > 0)
end)

-- Needs: feed and water ---------------------------------------------------------------------------

T.test("animals: the flock eats a season's share of feed and drinks daily", function()
  local world = coopWorld(6)
  local s = world.state.animals
  s.feed, s.water = 10, 4
  setTime(world, SUMMER + 4, hens.careHour + 0.1)
  local fed, wet = Animals.care(world)
  T.eq(fed, 1)
  T.eq(wet, 1)
  T.near(s.feed, 10 - 6 * hens.feedPerHen * hens.feedShare.summer, 1e-9)
  T.near(s.water, 4 - 6 * hens.waterPerHen, 1e-9)
  -- Winter: no forage, so the same flock needs more than twice as much.
  setTime(world, WINTER + 1, hens.careHour + 0.1)
  s.feed = 10
  Animals.care(world)
  T.near(s.feed, 10 - 6 * hens.feedPerHen * hens.feedShare.winter, 1e-9)
  T.truthy(hens.feedShare.winter >= 2 * hens.feedShare.summer, "winter is the feed pressure")
end)

T.test("animals: a flock with nothing to eat is hungry, then loses a hen a day after a grace period", function()
  local world = coopWorld(6)
  local s = world.state.animals
  local short, lost = collect(world, "animals.short"), collect(world, "animals.lost")
  s.water = 4
  for day = 1, hens.starveAfter do
    setTime(world, SUMMER + 4 + day, hens.careHour + 0.1)
    s.water = 4
    Animals.care(world)
    T.eq(Animals.hens(world), 6, "grace day " .. day)
  end
  T.eq(s.hungryDays, hens.starveAfter)
  T.eq(#short, hens.starveAfter)
  setTime(world, SUMMER + 5 + hens.starveAfter, hens.careHour + 0.1)
  s.water = 4
  Animals.care(world)
  T.eq(Animals.hens(world), 5)
  T.eq(lost[1].reason, "hunger")
  -- A fed day starts the count again.
  s.feed = 10
  setTime(world, SUMMER + 6 + hens.starveAfter, hens.careHour + 0.1)
  s.water = 4
  Animals.care(world)
  T.eq(s.hungryDays, 0)
  T.eq(Animals.hens(world), 5)
end)

T.test("animals: thirst is quicker than hunger", function()
  local world = coopWorld(6)
  local s = world.state.animals
  local lost = collect(world, "animals.lost")
  for day = 1, hens.thirstAfter + 1 do
    setTime(world, SUMMER + 4 + day, hens.careHour + 0.1)
    s.feed = 10
    Animals.care(world)
  end
  T.eq(Animals.hens(world), 5)
  T.eq(lost[1].reason, "thirst")
  T.truthy(hens.thirstAfter < hens.starveAfter)
end)

T.test("animals: no hens, no needs, no events", function()
  local world = coopWorld(0)
  local events = collect(world, "animals.short")
  setTime(world, SUMMER + 4, hens.careHour + 0.1)
  Animals.care(world)
  T.eq(#events, 0)
  T.eq(world.state.animals.hungryDays, 0)
  T.eq(Animals.lay(world), 0)
  T.eq(Animals.raid(world), nil)
end)

-- Eggs ------------------------------------------------------------------------------------------

--- Eggs laid over `years` copies of the season that starts on `seasonStart` (7 days each).
local function layDays(world, seasonStart, years)
  local total = 0
  for year = 0, years - 1 do
    for d = 0, DPS - 1 do
      setTime(world, seasonStart + year * 4 * DPS + d, hens.layHour + 0.1)
      total = total + Animals.lay(world)
      world.state.animals.nest = 0 -- empty the box so it never limits the count
    end
  end
  return total
end

T.test("animals: egg yield is deterministic per seed and tracks the season's lay chance", function()
  local function run(seed)
    local world = coopWorld(6, seed)
    world.state.animals.fed, world.state.animals.wet = 1, 1
    return layDays(world, SUMMER, 6)
  end
  T.eq(run(7), run(7), "same seed, same eggs")
  local expected = 6 * DPS * 6 * hens.layChance.summer
  local got = run(7)
  T.truthy(math.abs(got - expected) < expected * 0.2, string.format("%d eggs in 42 summer days vs ~%.0f expected", got, expected))
  local winter = coopWorld(6, 7)
  local w = layDays(winter, WINTER, 6)
  T.truthy(w < got / 2, "winter lays far less than summer")
end)

T.test("animals: hungry or thirsty hens lay less", function()
  local function eggs(fed, wet)
    local world = coopWorld(6, 3)
    world.state.animals.fed, world.state.animals.wet = fed, wet
    return layDays(world, SUMMER, 6)
  end
  local full = eggs(1, 1)
  T.truthy(eggs(0, 1) < full * 0.5)
  T.truthy(eggs(1, 0) < full * 0.3)
end)

T.test("animals: eggs wait in the nest box until tended, then go to the ledger", function()
  local world = coopWorld(6)
  local s = world.state.animals
  local collected = collect(world, "animals.collected")
  s.nest = 5
  s.feed, s.water = 2, 1
  Ledger.add(world, "chicken_feed", 30)
  local eggs, feed = Animals.tend(world)
  T.eq(eggs, 5)
  T.eq(Ledger.get(world, "egg"), 5)
  T.eq(s.nest, 0)
  T.eq(collected[1].count, 5)
  T.eq(feed, 10, "the feeder is filled to its capacity from the sack")
  T.eq(s.feed, 12)
  T.eq(Ledger.get(world, "chicken_feed"), 20)
  T.eq(s.water, 4, "the waterer is full")
  T.eq(s.collected, 5)
end)

T.test("animals: eggs are food and can be sold from the crate", function()
  local world = coopWorld(3)
  Ledger.add(world, "egg", 30)
  Food.setPin(world, "egg", "sell")
  T.eq(Food.crateOf(world, "egg"), 30)
  local _, total = Market.crateQuote(world)
  T.eq(total, 30 * Market.sellPrice(world, "egg"))
end)

T.test("animals: a full egg store holds eggs in the nest box instead of losing them (D59)", function()
  local world = coopWorld(6)
  local s = world.state.animals
  Ledger.setCapacity(world, "egg", 4)
  Ledger.add(world, "egg", 4)
  s.nest = 6
  local overflow = collect(world, "ledger.overflow")
  local eggs = Animals.tend(world)
  T.eq(eggs, 0)
  T.eq(s.nest, 6, "all six still in the box")
  T.eq(#overflow, 0, "nothing discarded")
  -- Room appears: whatever fits is taken.
  Ledger.remove(world, "egg", 2)
  T.eq((Animals.tend(world)), 2)
  T.eq(s.nest, 4)
  T.eq(Ledger.get(world, "egg"), 4)
end)

T.test("animals: a full nest box stops the laying and says so once a day", function()
  local world = coopWorld(6)
  local s = world.state.animals
  local full = collect(world, "animals.nestFull")
  s.nest = reg:get("objects", "chicken_coop").coop.nest - 1
  s.fed, s.wet = 1, 1
  with({ { hens.layChance, "summer", 1.5 } }, function()
    setTime(world, SUMMER + 4, hens.layHour + 0.1)
    local laid = Animals.lay(world)
    T.eq(laid, 1)
  end)
  T.eq(s.nest, reg:get("objects", "chicken_coop").coop.nest)
  T.eq(#full, 1)
  T.eq(full[1].lost, 5)
end)

-- The chore -------------------------------------------------------------------------------------

T.test("animals: the routine tends the coop when eggs pile up or the feeder runs low", function()
  local world, spot = coopWorld(6)
  local hs = Actors.homesteader(world)
  local s = world.state.animals
  s.feed, s.water = 12, 4
  s.nest = hens.collectMin - 1
  -- (Other chores, such as clearing brush, may still be on the board: look only for the coop.)
  local function chore()
    local job = Tasks.chooseIdleJob(world, hs)
    return job and job.task == "tend_coop"
  end
  T.falsy(chore(), "two eggs and full bowls: nothing worth a trip")
  s.nest = hens.collectMin
  T.truthy(chore(), "enough eggs")
  s.nest = 0
  s.water = 1
  T.truthy(chore(), "waterer low")
  s.water = 4
  s.feed = 3
  T.falsy(chore(), "feeder low but no feed to add")
  Ledger.add(world, "chicken_feed", 5)
  T.truthy(chore(), "feeder low and a sack in store")
  -- The category can be switched off in the routine.
  Tasks.setPriorityEnabled(world, "animals", false)
  T.falsy(chore())
  T.truthy(spot)
end)

T.test("animals: the animals category sits in the default priorities, after harvest and water", function()
  local world = newWorld()
  local order = {}
  for _, entry in ipairs(world.state.priorities) do
    order[entry.category] = #order + 1
    order[#order + 1] = entry.category
  end
  T.truthy(order.animals, "listed")
  T.truthy(order.animals > order.harvest and order.animals > order.water)
end)

T.test("animals: a tap on the coop orders the chore, and the homesteader does it", function()
  local world, spot = coopWorld(3)
  local hs = Actors.homesteader(world)
  local s = world.state.animals
  s.nest = 2
  local taskType = Actors.order(world, hs, spot)
  T.truthy(taskType and taskType.id == "tend_coop")
  for _ = 1, 600 do
    world:tick(STEP)
  end
  T.eq(s.collected, 2, "the two eggs that were waiting")
  T.eq(Ledger.get(world, "egg"), 2)
  T.truthy(Actors.homesteader(world).job == nil, "the chore is done")
end)

T.test("animals: a tap that cannot collect names the full egg store", function()
  local world, spot = coopWorld(3)
  local hs = Actors.homesteader(world)
  local s = world.state.animals
  s.nest = 3
  s.water = 4
  Ledger.setCapacity(world, "egg", 1)
  Ledger.add(world, "egg", 1)
  local taskType, full = Actors.order(world, hs, spot)
  T.eq(taskType, nil)
  T.eq(full, "egg")
end)

T.test("animals: a month untended keeps the flock alive for the grace period, then it thins (forgiving but real)", function()
  local world = coopWorld(6)
  local s = world.state.animals
  s.feed, s.water = 12, 4
  setTime(world, SUMMER + 4, 6)
  local start = Animals.hens(world)
  for _ = 1, 3 * tun.time.dayLength * tun.time.tickRate do
    world:tick(STEP)
  end
  T.eq(Animals.hens(world), start, "three days with full bowls and nobody home: no losses")
  for _ = 1, 12 * tun.time.dayLength * tun.time.tickRate do
    world:tick(STEP)
  end
  T.truthy(Animals.hens(world) < start, "a fortnight of neglect costs hens")
end)

-- Predators -------------------------------------------------------------------------------------

--- Tonight is autumn, clear, past the first days, with the raid certain to come.
local function raidNight(world)
  setTime(world, AUTUMN + 2, pred.hour + 0.25)
  force(world, "clear")
end

local function raidTally(guardOverride, extra)
  local raided, stopped = 0, 0
  with({ { pred, "chancePerDay", 1 }, { pred, "maxGuard", guardOverride } }, function()
    local world = coopWorld(6, 11)
    if extra then
      extra(world)
    end
    raidNight(world)
    for _ = 1, 300 do
      Ledger.add(world, "hen", 6 - Animals.hens(world), "test")
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

T.test("animals: with no defences every raid takes hens through the ledger", function()
  with({ { pred, "chancePerDay", 1 }, { pred, "maxGuard", 0 } }, function()
    local world = coopWorld(6)
    raidNight(world)
    local events, changes = collect(world, "animals.predator"), {}
    world.events:on("ledger.changed", function(e)
      if e.id == "hen" and e.reason == "predator" then
        changes[#changes + 1] = e
      end
    end)
    T.eq(Animals.raid(world), "raided")
    local killed = events[1].killed
    T.truthy(killed >= pred.loss.min and killed <= pred.loss.max)
    T.eq(Animals.hens(world), 6 - killed)
    T.eq(#changes, 1)
    T.eq(world.state.animals.lost, killed)
  end)
end)

T.test("animals: the coop door and the fence turn raids back (more fence, more turned back)", function()
  local noGuard = raidTally(0)
  T.eq(noGuard, 300, "no guard: every raid lands")
  local coopRaided, coopStopped = raidTally(tun.animals.predators.maxGuard)
  T.truthy(coopStopped > 0 and coopRaided > 0, "the door stops many, not all")
  local expected = reg:get("objects", "chicken_coop").coop.guard
  T.truthy(math.abs(coopStopped / 300 - expected) < 0.1, string.format("%.2f stopped vs coop guard %.2f", coopStopped / 300, expected))
  local fencedRaided = raidTally(tun.animals.predators.maxGuard, function(world)
    Inventory.addEquipment(world, "chicken_fence")
  end)
  T.truthy(fencedRaided < coopRaided, "the fence cuts the losses")
  -- Never perfect.
  local world = coopWorld(6)
  Inventory.addEquipment(world, "chicken_fence")
  T.truthy(Animals.guard(world) <= pred.maxGuard)
end)

T.test("animals: storms make raids likelier, the cat fewer, and no hens means no raid", function()
  local world = coopWorld(6)
  raidNight(world)
  local calm = Animals.raidChance(world)
  force(world, "storm")
  T.truthy(Animals.raidChance(world) > calm, "storm weather raises the odds (Weather.threat)")
  force(world, "clear")
  Inventory.addEquipment(world, Cat.ITEM)
  Cat.tick(world, STEP)
  T.truthy(Cat.present(world))
  T.truthy(Animals.raidChance(world) < calm, "a cat on the place keeps foxes away")
  local empty = coopWorld(0)
  raidNight(empty)
  T.eq(Animals.raid(empty), nil)
end)

T.test("animals: a raid is rolled once a night, from its own stream, whatever the defences", function()
  local function run(fence)
    local world = coopWorld(6, 5)
    if fence then
      Inventory.addEquipment(world, "chicken_fence")
    end
    raidNight(world)
    Animals.raid(world)
    return world:rng("predators"):float()
  end
  T.eq(run(false), run(true), "the stream advances the same with or without a fence")
end)

T.test("animals: no raids before the first days of a run", function()
  with({ { pred, "chancePerDay", 1 } }, function()
    local world = coopWorld(6)
    setTime(world, pred.firstDay - 1, pred.hour + 0.25)
    T.eq(Animals.raid(world), nil)
    T.eq(Animals.hens(world), 6)
  end)
end)

-- Saves -----------------------------------------------------------------------------------------

T.test("animals: state survives a save round-trip and carries on the same", function()
  local world, spot = coopWorld(5, 9)
  local s = world.state.animals
  s.feed, s.water, s.nest = 7, 2, 4
  s.hungryDays = 1
  Ledger.add(world, "chicken_feed", 6)
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(serialize.encode(restored.state.animals), serialize.encode(world.state.animals))
  T.eq(Animals.hens(restored), 5)
  T.eq(Animals.housing(restored), 6)
  T.eq(Grid.object(restored, spot).id, "chicken_coop")
  -- Both advance a night identically.
  for _, w in ipairs({ world, restored }) do
    setTime(w, SUMMER + 5, hens.layHour - 0.01)
    force(w, "clear")
    for _ = 1, 40 do
      w:tick(STEP)
    end
  end
  T.eq(serialize.encode(restored.state.animals), serialize.encode(world.state.animals))
end)

T.test("animals: a save from before chickens loads, gains the category, and takes a coop later", function()
  local world = newWorld(4)
  local state = serialize.decode(serialize.encode(world.state))
  state.animals = nil
  state.ledger.amounts.hen = nil
  local kept = {}
  for _, entry in ipairs(state.priorities) do
    if entry.category ~= "animals" then
      kept[#kept + 1] = entry
    end
  end
  state.priorities = kept
  local old = World.new({ registry = reg, tuning = tun }, state)
  T.truthy(old.state.animals)
  T.eq(old.state.animals.nest, 0)
  T.eq(Animals.hens(old), 0)
  local found = false
  for _, entry in ipairs(old.state.priorities) do
    found = found or (entry.category == "animals" and entry.enabled)
  end
  T.truthy(found, "the animals category is appended and on")
  for _ = 1, 100 do
    old:tick(STEP)
  end
  Inventory.addObject(old, "chicken_coop")
  T.truthy(Inventory.place(old, "chicken_coop", coopSpot(old)))
  T.eq(Ledger.add(old, "hen", 3), 3)
end)

-- Balance sanity --------------------------------------------------------------------------------

--- Net money of a six-hen flock over `days` days of a season, buying all feed at the catalog price
--- and selling every egg at the town price. Returns net $, eggs, feed units eaten.
local function fortnight(startDay, days)
  local world = coopWorld(6, 2)
  local s = world.state.animals
  local sackPrice = reg:get("catalog", "chicken_feed").price / reg:get("catalog", "chicken_feed").gives.chicken_feed
  local eggs, fed = 0, 0
  for d = 0, days - 1 do
    setTime(world, startDay + d, hens.layHour + 0.1)
    s.feed, s.water = s.feed + 0, 4
    local before = s.feed
    Ledger.add(world, "chicken_feed", 40 - Ledger.get(world, "chicken_feed"))
    Animals.tend(world)
    eggs = eggs + Animals.lay(world)
    setTime(world, startDay + d, hens.careHour + 0.1)
    Animals.care(world)
    fed = fed + (12 - s.feed) - 0 * before
  end
  local value = reg:get("resources", "egg").value
  return eggs * value - fed * sackPrice, eggs, fed
end

T.test("animals: balance sanity, summer pays, winter pays little, and feed is the winter pressure", function()
  local summerNet, summerEggs, summerFeed = fortnight(SUMMER, DPS)
  local winterNet, winterEggs, winterFeed = fortnight(WINTER, DPS)
  T.truthy(summerNet > 0, "a summer week in the black")
  T.truthy(summerEggs > winterEggs * 2, "winter lays far less")
  T.truthy(winterFeed > summerFeed * 2, "winter eats far more feed")
  T.truthy(winterNet < summerNet / 2, "winter barely pays its way")
  T.truthy(winterNet > -summerNet, "but a bad winter is not ruinous")
end)

T.test("animals: the flock fits the coop and the hens' sack fits the feed store", function()
  local coop = reg:get("objects", "chicken_coop")
  T.truthy(reg:get("catalog", "hens").gives.hen <= coop.storage.hen, "a first purchase fits an empty coop")
  T.truthy(reg:get("catalog", "chicken_coop").gives.chicken_feed <= reg:get("resources", "chicken_feed").capacity)
  T.truthy(coop.coop.nest <= reg:get("resources", "egg").capacity, "a full nest box fits the egg store")
end)
