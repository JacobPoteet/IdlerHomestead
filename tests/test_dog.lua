-- The farm dog (C4, #358, D189, docs/PLAN_DEPTH.md §6.1, §10.3, src/sim/systems/dog.lua): a companion that guards against
-- some night threats and eats from the food ledger. It plugs into the raiders' and the fox's guard roll; it does not
-- answer the mice (the cat's), and it never takes a meal the homesteader needs.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Animals = require("src.sim.systems.animals")
local Cat = require("src.sim.systems.cat")
local Dog = require("src.sim.systems.dog")
local Events = require("src.sim.systems.events")
local Finds = require("src.sim.systems.finds")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local NightThreats = require("src.sim.systems.nightthreats")
local Needs = require("src.sim.systems.needs")
local Raiders = require("src.sim.systems.raiders")
local Readiness = require("src.sim.systems.readiness")
local TonightText = require("src.ui.tonight_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local DPS = tun.time.daysPerSeason
local SUMMER = DPS + 1
local cfg = tun.dog

-- Mice would claim the night slot too: this file is about the dog, the cat has its own tests.
tun.cat.mice.chancePerDay = 0

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true
  world.state.weather.sky.days[1] = "clear"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- Run `fn` with tuning values overridden, then restore them (also when `fn` fails).
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

local function giveDog(world)
  Inventory.addEquipment(world, Dog.ITEM)
  Dog.tick(world)
end

-- A summer evening with the stores a raccoon wants.
local function duskWorld(seed)
  local world = newWorld(seed)
  setTime(world, SUMMER + 2, 19.25)
  Ledger.add(world, "potato", 20)
  return world
end

local function raccoonPlan(world)
  return Raiders.nightPlan(world, 1, reg:get("night_threats", "raccoon"))
end

-- Content ----------------------------------------------------------------------------------------------

T.test("dog: the farm dog is a unique piece of equipment taught by a raid, and the stray dog is a find", function()
  local item = reg:get("catalog", Dog.ITEM)
  T.truthy(item.equipment and item.unique)
  T.eq(item.needs[1], "raccoon_raid")
  T.truthy(reg:has("notes", item.needs[1]))
  T.truthy(reg:get("finds", "stray_dog").effects.equipment[1] == Dog.ITEM)
  local world = newWorld()
  T.truthy(Finds.weight(world, "stray_dog") > 0)
  Inventory.addEquipment(world, Dog.ITEM)
  T.eq(Finds.weight(world, "stray_dog"), 0, "never offered once a dog is owned")
  T.same(NightThreats.audit(world), {})
end)

T.test("dog: the cat and the dog do not duplicate; every guard names a threat that exists", function()
  T.eq(rawget(cfg.guards, "mice"), nil, "the mice are the cat's")
  for id in pairs(cfg.guards) do
    T.truthy(reg:has("night_threats", id), id .. " is a night threat")
    T.truthy(cfg.guards[id] > 0 and cfg.guards[id] < 1)
  end
  local world = newWorld()
  giveDog(world)
  T.eq(Dog.guard(world, "mice"), 0)
  T.eq(Cat.catchChance(world), 0, "a dog is no cat")
  local guard = tun.night.exposure.guards[Dog.ITEM]
  local covered = {}
  for _, id in ipairs(guard.covers) do
    covered[id] = true
    T.truthy(Dog.covers(world, id), "exposure covers only what the dog guards: " .. id)
  end
  for id in pairs(cfg.guards) do
    T.truthy(covered[id], "exposure covers " .. id)
  end
end)

-- Arrival ----------------------------------------------------------------------------------------------

T.test("dog: owning the dog brings it to a free tile by the spawn point on the next tick", function()
  local world = newWorld()
  T.eq(Dog.present(world), false)
  T.eq(Dog.position(world), nil)
  local arrived = 0
  world.events:on("dog.arrived", function()
    arrived = arrived + 1
  end)
  Dog.tick(world)
  T.eq(Dog.present(world), false, "no dog without the item")
  giveDog(world)
  T.eq(Dog.present(world), true)
  T.eq(arrived, 1)
  Dog.tick(world)
  T.eq(arrived, 1, "it arrives once")
  local x, y, mode = Dog.position(world)
  local sx, sy = Grid.coords(world.state.grid, world.state.land.spawn)
  T.truthy(math.max(math.abs(x - sx), math.abs(y - sy)) <= cfg.postRadius)
  T.truthy(x ~= sx or y ~= sy, "not on the spawn tile")
  T.truthy(Grid.walkable(world, Grid.index(world.state.grid, x, y)))
  T.truthy(mode == "sit" or mode == "sleep")
end)

T.test("dog: the dog finds another post when a building covers its tile", function()
  local world = newWorld()
  giveDog(world)
  local d = world.state.dog
  local i = Grid.index(world.state.grid, d.x, d.y)
  world.occupancy[i] = i -- something now stands there
  world.state.grid.objects[i] = { id = "rock" }
  Dog.tick(world)
  T.truthy(d.x ~= Grid.coords(world.state.grid, i) or d.y ~= select(2, Grid.coords(world.state.grid, i)))
  world.occupancy[i], world.state.grid.objects[i] = nil, nil
end)

-- Upkeep: it eats from the food ledger -----------------------------------------------------------------

T.test("dog: at feedHour it eats one unit of the cheapest food through the ledger, once a day", function()
  with({ { cfg, "keepFoodDays", 0 } }, function()
    local world = newWorld()
    Ledger.add(world, "radish", 10)
    Ledger.add(world, "potato", 10)
    giveDog(world)
    setTime(world, 3, cfg.feedHour - 1)
    Dog.tick(world)
    T.eq(Ledger.get(world, "radish"), 10, "not yet mealtime")
    setTime(world, 3, cfg.feedHour + 0.1)
    local fed
    world.events:on("dog.fed", function(e)
      fed = e
    end)
    Dog.tick(world)
    T.eq(Ledger.get(world, "radish"), 10 - cfg.mealUnits, "the cheapest food")
    T.eq(Ledger.get(world, "potato"), 10)
    T.eq(fed.id, "radish")
    T.eq(Dog.fed(world), true)
    Dog.tick(world)
    T.eq(Ledger.get(world, "radish"), 10 - cfg.mealUnits, "one meal a day")
    setTime(world, 4, cfg.feedHour + 0.1)
    Dog.tick(world)
    T.eq(Ledger.get(world, "radish"), 10 - 2 * cfg.mealUnits, "and again the next day")
    T.eq(Dog.info(world).meals, 2)
  end)
end)

T.test("dog: the mercy rule: it never eats into the homesteader's food reserve; it goes hungry instead", function()
  local world = newWorld()
  Ledger.add(world, "potato", 5)
  giveDog(world)
  local calories = Needs.calories(world)
  -- Hold exactly one meal's worth over the reserve: the dog may eat it, the next day it may not.
  local potato = reg:get("resources", "potato").calories
  with({ { cfg, "keepFoodDays", calories / tun.needs.dailyCalories } }, function()
    setTime(world, 3, cfg.feedHour + 0.1)
    Dog.tick(world)
    T.eq(Dog.fed(world), false, "no meal can be spared")
    T.eq(Needs.calories(world), calories, "nothing was taken")
    T.eq(Dog.info(world).hungry, 1)
    T.eq(Dog.present(world), true, "a hungry dog stays")
  end)
  with({ { cfg, "keepFoodDays", (calories - potato) / tun.needs.dailyCalories } }, function()
    setTime(world, 4, cfg.feedHour + 0.1)
    Dog.tick(world)
    T.eq(Dog.fed(world), true, "exactly one meal over the reserve")
    T.truthy(Needs.calories(world) >= cfg.keepFoodDays * 0 + calories - potato - 1e-9)
  end)
end)

T.test("dog: a hungry dog still watches, at hungryScale of its guard; with no dog the guard is 0", function()
  local world = newWorld()
  T.eq(Dog.guard(world, "raccoon"), 0)
  giveDog(world)
  T.near(Dog.guard(world, "raccoon"), cfg.guards.raccoon, 1e-9)
  world.state.dog.fed = false
  T.near(Dog.guard(world, "raccoon"), cfg.guards.raccoon * cfg.hungryScale, 1e-9)
  T.eq(Dog.guard(world, "mice"), 0)
end)

T.test(
  "dog: an idle homestead feeds the dog for days with nothing to do and the homesteader keeps the reserve",
  function()
    local world = newWorld(4)
    Ledger.add(world, "potato", 30)
    giveDog(world)
    local floor = math.min(Needs.calories(world), cfg.keepFoodDays * tun.needs.dailyCalories)
    for day = 3, 12 do
      setTime(world, day, cfg.feedHour + 0.1)
      Dog.tick(world)
      T.truthy(Needs.calories(world) >= floor - 1e-9, "the reserve holds on day " .. day)
    end
    T.truthy(Dog.info(world).meals > 0)
  end
)

-- The guard --------------------------------------------------------------------------------------------

T.test("dog: the dog turns a raccoon back inside its guard roll; the stream does not depend on it", function()
  with({ { tun.raiders.raccoon, "chancePerDay", 8 } }, function()
    local plain, dogged = duskWorld(5), duskWorld(5)
    giveDog(dogged)
    local pa, pb = raccoonPlan(plain), raccoonPlan(dogged)
    T.truthy(pa and pb)
    T.eq(pa.guardRoll, pb.guardRoll, "the same draws with or without a dog")
    T.eq(plain.state.rng.raccoon.s, dogged.state.rng.raccoon.s)
    pa.guardRoll, pb.guardRoll = cfg.guards.raccoon - 0.01, cfg.guards.raccoon - 0.01
    T.eq(Raiders.nightLand(plain, pa), "raided", "no dog, no bins: it gets in")
    T.eq(Raiders.nightLand(dogged, pb), "stopped", "the dog turned it back")
    T.eq(Ledger.get(dogged, "potato"), 20)
  end)
end)

T.test("dog: a fed dog guards better than a hungry one; the dog and the bins add, capped by maxGuard", function()
  with({ { tun.raiders.raccoon, "chancePerDay", 8 } }, function()
    local world = duskWorld(6)
    giveDog(world)
    local plan = raccoonPlan(world)
    plan.guardRoll = cfg.guards.raccoon * cfg.hungryScale + 0.01
    world.state.dog.fed = false
    local copy = { id = plan.id, guard = plan.guard, picks = plan.picks, guardRoll = plan.guardRoll }
    T.eq(Raiders.nightLand(world, plan), "raided", "hungry: that roll gets through")
    world.state.dog.fed = true
    T.eq(Raiders.nightLand(world, copy), "stopped", "fed: the same roll is turned back")
    Inventory.addEquipment(world, "lidded_bins")
    local bins = tun.raiders.raccoon.maxGuard
    copy.guardRoll = bins - 0.001
    T.eq(Raiders.nightLand(world, copy), "stopped")
    copy.guardRoll = bins + 0.001
    T.eq(Raiders.nightLand(world, copy), "raided", "no defence is perfect")
  end)
end)

T.test("dog: the dog adds its fox guard to the coop's and the pen's, capped", function()
  local world = newWorld()
  local hens, goats = Animals.guard(world), Animals.guard(world, "goats")
  giveDog(world)
  local cap = tun.animals.predators.maxGuard
  T.near(Animals.guard(world), math.min(cap, hens + cfg.guards.fox), 1e-9)
  T.near(Animals.guard(world, "goats"), math.min(cap, goats + cfg.guards.fox), 1e-9)
end)

T.test("dog: the dog lowers the exposure word's points for what it covers, not for mice", function()
  local world = newWorld(2)
  local base, baseFox, baseMice = Events.exposure(world), Events.exposure(world, "fox"), Events.exposure(world, "mice")
  giveDog(world)
  local x = tun.night.exposure
  local guard = x.guards[Dog.ITEM]
  T.near(Events.exposure(world).points, math.max(x.min, base.points - guard.points), 1e-9)
  T.near(Events.exposure(world, "fox").points, math.max(x.min, baseFox.points - guard.points), 1e-9)
  T.eq(Events.exposure(world, "mice").points, baseMice.points, "the mice are not covered")
  T.truthy(
    NightThreats.scale(world, reg:get("night_threats", "raccoon")) < 1 + (base.multiplier - 1) * 0.7 + 1e-9,
    "a covered threat is less likely"
  )
end)

T.test("dog: the Tonight card names the dog among what lowers the exposure", function()
  local world = newWorld(2)
  T.same(Readiness.tonight(world).exposure.guards, {})
  giveDog(world)
  local e = Readiness.tonight(world).exposure
  T.same(e.guards, { "farm dog" })
  local model = TonightText.build(Readiness.tonight(world), {})
  T.truthy(model.notes[2].text:find("dog on watch", 1, true), model.notes[2].text)
end)

-- State ------------------------------------------------------------------------------------------------

T.test("dog: the dog's state is plain data and survives a save", function()
  local world = newWorld()
  giveDog(world)
  local copy = serialize.decode(serialize.encode(world.state.dog))
  T.same(copy, world.state.dog)
end)
