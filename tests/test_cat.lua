-- Mice and the cat (GDD §7.7, D54): night raids on the stored food, a cat that answers them.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Cat = require("src.sim.systems.cat")
local Finds = require("src.sim.systems.finds")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local mice, catCfg = tun.cat.mice, tun.cat.cat
local DPS = tun.time.daysPerSeason
local AUTUMN = 2 * DPS + 1

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function clear(world)
  world.state.weather.sky.days[1] = "clear"
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

--- An autumn night where mice are certain, with 20 potatoes in store.
local function raidWorld(seed)
  local world = newWorld(seed)
  setTime(world, AUTUMN, mice.raidHour + 0.25)
  clear(world)
  Ledger.add(world, "potato", 20)
  return world
end

local function giveCat(world)
  Inventory.addEquipment(world, Cat.ITEM)
  Cat.tick(world, STEP)
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

T.test("cat: the shelter cat and the stray cat are content, tied to the mouse note", function()
  local item = reg:get("catalog", Cat.ITEM)
  T.truthy(item.equipment)
  T.eq(item.needs[1], "mice_raid")
  T.truthy(reg:get("notes", "mice_raid"))
  T.truthy(reg:get("finds", "stray_cat").effects.equipment[1] == Cat.ITEM)
end)

T.test("cat: with no cat, a certain raid ruins food through the ledger", function()
  with({ { mice, "chancePerDay", 1 } }, function()
    local world = raidWorld()
    local raids, changes = collect(world, "mice.raided"), {}
    world.events:on("ledger.changed", function(e)
      if e.reason == "mice" then
        changes[#changes + 1] = e
      end
    end)
    T.eq(Cat.raid(world), "raided")
    local lost = math.max(mice.minLoss, math.min(mice.maxLoss, math.floor(20 * mice.lossFraction)))
    T.eq(Ledger.get(world, "potato"), 20 - lost)
    T.eq(#raids, 1)
    T.eq(raids[1].units, lost)
    T.eq(raids[1].lost.potato, lost)
    T.eq(#changes, lost)
  end)
end)

T.test("cat: mice leave fish, cans and seed alone, and skip an empty larder or the first days", function()
  with({ { mice, "chancePerDay", 1 } }, function()
    local world = newWorld()
    setTime(world, AUTUMN, mice.raidHour + 0.25)
    clear(world)
    Ledger.remove(world, "potato", Ledger.get(world, "potato"))
    Ledger.remove(world, "radish", Ledger.get(world, "radish"))
    Ledger.add(world, "canned_food", 5)
    Ledger.add(world, "sunfish", 5)
    Ledger.add(world, "seed_potato", 5)
    local cans, fish, seed =
      Ledger.get(world, "canned_food"), Ledger.get(world, "sunfish"), Ledger.get(world, "seed_potato")
    T.eq(Cat.raid(world), nil)
    T.eq(Ledger.get(world, "canned_food"), cans)
    T.eq(Ledger.get(world, "sunfish"), fish)
    T.eq(Ledger.get(world, "seed_potato"), seed)
    local early = raidWorld()
    setTime(early, mice.firstDay - 1, mice.raidHour + 0.25)
    T.eq(Cat.raid(early), nil)
    T.eq(Ledger.get(early, "potato"), 20)
  end)
end)

T.test(
  "cat: the nightly roll runs once a day from the tick (planned at dusk, landed at the raid hour, D187)",
  function()
    with({ { mice, "chancePerDay", 1 } }, function()
      local world = raidWorld()
      world:tick(STEP) -- it is past sunset and raid hour: the dusk plan is made...
      world:tick(STEP) -- ...and lands on the next tick
      local after = Ledger.get(world, "potato")
      T.truthy(after < 20)
      world:tick(STEP)
      T.eq(Ledger.get(world, "potato"), after)
    end)
  end
)

T.test("cat: rough weather and the harvest season make a raid likelier, never above 1", function()
  local world = newWorld()
  setTime(world, 1, 12)
  clear(world)
  local spring = Cat.raidChance(world)
  world.state.weather.sky.days[1] = "storm"
  T.truthy(Cat.raidChance(world) > spring)
  setTime(world, AUTUMN, 12)
  with({ { mice, "chancePerDay", 0.9 } }, function()
    T.eq(Cat.raidChance(world), 1)
  end)
end)

T.test("cat: a cat arrives once owned, and catches raids by how well it is kept", function()
  with({ { mice, "chancePerDay", 1 }, { catCfg, "fedCatch", 1 }, { catCfg, "hungryCatch", 0 } }, function()
    local world = raidWorld()
    T.falsy(Cat.present(world))
    T.eq(Cat.catchChance(world), 0)
    local arrived = collect(world, "cat.arrived")
    giveCat(world) -- the cat's own tick no longer rolls the raid (the night threat framework does, D187)
    T.truthy(Cat.present(world))
    T.eq(#arrived, 1)
    T.eq(world.state.cat.caught, 0)
    T.eq(Ledger.get(world, "potato"), 20)
    setTime(world, AUTUMN + 1, mice.raidHour + 0.25)
    T.eq(Cat.raid(world), "caught")
    T.eq(Ledger.get(world, "potato"), 20)
    world.state.cat.fed = false
    T.eq(Cat.raid(world), "raided")
    T.truthy(Ledger.get(world, "potato") < 20)
    T.eq(world.state.cat.caught, 1)
  end)
end)

T.test("cat: it eats one fish a day (the cheapest), and goes hungry without", function()
  local world = newWorld()
  giveCat(world)
  Ledger.add(world, "sunfish", 2)
  Ledger.add(world, "brook_trout", 2)
  setTime(world, 3, catCfg.feedHour + 0.25)
  clear(world)
  Cat.tick(world, STEP)
  T.eq(Ledger.get(world, "sunfish"), 2 - catCfg.mealUnits)
  T.eq(Ledger.get(world, "brook_trout"), 2)
  T.truthy(Cat.info(world).fed)
  Cat.tick(world, STEP) -- already fed today
  T.eq(Ledger.get(world, "sunfish"), 2 - catCfg.mealUnits)
  Ledger.remove(world, "sunfish", Ledger.get(world, "sunfish"))
  Ledger.remove(world, "brook_trout", 2)
  setTime(world, 4, catCfg.feedHour + 0.25)
  Cat.tick(world, STEP)
  T.falsy(Cat.info(world).fed)
  T.truthy(Cat.catchChance(world) == catCfg.hungryCatch)
end)

T.test("cat: petting grows the bond once a day, up to the cap", function()
  local world = newWorld()
  T.falsy(Cat.pet(world))
  giveCat(world)
  setTime(world, 3, 12)
  T.truthy(Cat.pet(world))
  T.truthy(Cat.pet(world))
  T.eq(Cat.info(world).bond, 1)
  T.eq(Cat.info(world).pets, 2)
  for day = 4, 4 + catCfg.maxBond + 2 do
    setTime(world, day, 12)
    Cat.pet(world)
  end
  T.eq(Cat.info(world).bond, catCfg.maxBond)
  T.truthy(Cat.catchChance(world) > catCfg.fedCatch)
  T.truthy(Cat.catchChance(world) <= 1)
end)

T.test("cat: it wanders on walkable ground near home and naps in the sun", function()
  local world = newWorld(3)
  giveCat(world)
  clear(world)
  setTime(world, 3, 12)
  local napped, moved = false, false
  local x0, y0 = world.state.cat.x, world.state.cat.y
  for _ = 1, 600 do
    Cat.tick(world, 4)
    local tile = Cat.tile(world)
    T.truthy(Grid.walkable(world, tile), "cat on a walkable tile")
    napped = napped or world.state.cat.mode == "nap"
    moved = moved or world.state.cat.x ~= x0 or world.state.cat.y ~= y0
  end
  T.truthy(moved)
  T.truthy(napped)
  T.truthy(Cat.at(world, Cat.tile(world)))
end)

T.test("cat: it sleeps near home at night", function()
  local world = newWorld(3)
  giveCat(world)
  setTime(world, 3, 1)
  clear(world)
  for _ = 1, 300 do
    Cat.tick(world, 4)
  end
  T.eq(world.state.cat.mode, "sleep")
end)

T.test("cat: the whole thing is deterministic per seed", function()
  local function run(seed)
    local world = newWorld(seed)
    giveCat(world)
    Ledger.add(world, "potato", 30)
    setTime(world, AUTUMN, 6)
    for _ = 1, tun.time.tickRate * 400 do
      world:tick(STEP)
    end
    return serialize.encode(world.state.cat), Ledger.get(world, "potato")
  end
  local a, ap = run(7)
  local b, bp = run(7)
  T.eq(a, b)
  T.eq(ap, bp)
end)

T.test("cat: state survives a save round-trip and carries on the same", function()
  local world = newWorld(2)
  giveCat(world)
  setTime(world, 3, 12)
  clear(world)
  for _ = 1, 60 do
    Cat.tick(world, 4)
  end
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.same(restored.state.cat, world.state.cat)
  clear(restored) -- the test jumped the clock without ticking, so the weather queue is not comparable
  for _ = 1, 60 do
    Cat.tick(world, 4)
    Cat.tick(restored, 4)
  end
  T.eq(serialize.encode(restored.state.cat), serialize.encode(world.state.cat))
end)

T.test("cat: a save from before the cat loads (and an owned cat then moves in)", function()
  local world = newWorld()
  local state = serialize.decode(serialize.encode(world.state))
  state.cat = nil
  local old = World.new({ registry = reg, tuning = tun }, state)
  T.truthy(old.state.cat)
  T.falsy(Cat.present(old))
  giveCat(old)
  T.truthy(Cat.present(old))
end)

T.test("cat: the stray cat find grants the cat, and is not offered once one is owned", function()
  local world = newWorld()
  setTime(world, 10, 12)
  T.truthy(Finds.weight(world, "stray_cat") > 0)
  world.state.finds.pending = { day = 10, choices = { "stray_cat" } }
  T.truthy(Finds.choose(world, "stray_cat"))
  T.truthy(Inventory.hasEquipment(world, Cat.ITEM))
  T.eq(Finds.weight(world, "stray_cat"), 0)
  Cat.tick(world, STEP)
  T.truthy(Cat.present(world))
end)

T.test("cat: the first raid writes the Mice note, which makes the cat an idea", function()
  with({ { mice, "chancePerDay", 1 } }, function()
    local world = raidWorld()
    T.falsy(world.meta.journal and world.meta.journal.known[Cat.ITEM])
    Cat.raid(world)
    T.truthy(Journal.hasNote(world, "mice_raid"))
  end)
end)

T.test("cat: over many nights a cat saves most of the food (balance sanity)", function()
  local function lostOver(withCat)
    local world = newWorld(11)
    clear(world)
    if withCat then
      giveCat(world)
    end
    local total = 0
    with({ { mice, "chancePerDay", 1 } }, function()
      for night = 1, 60 do
        setTime(world, AUTUMN + night, mice.raidHour + 0.25)
        clear(world)
        Ledger.add(world, "potato", 20 - Ledger.get(world, "potato"))
        world.state.cat.fed = true
        Cat.raid(world)
        total = total + (20 - Ledger.get(world, "potato"))
      end
    end)
    return total
  end
  local bare, kept = lostOver(false), lostOver(true)
  T.truthy(bare > 0)
  T.truthy(kept < bare * 0.4, string.format("cat should cut losses a lot (%d vs %d)", kept, bare))
end)
