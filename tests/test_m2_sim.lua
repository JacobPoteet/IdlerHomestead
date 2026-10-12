local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Rng = require("src.core.rng")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Spoilage = require("src.sim.systems.spoilage")
local Fishing = require("src.sim.systems.fishing")
local Food = require("src.sim.systems.food")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local Inventory = require("src.sim.systems.inventory")
local Water = require("src.sim.systems.water")
local Processing = require("src.sim.systems.processing")
local Model = require("src.sim.minigames.fishing_model")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

local function setHour(world, hour)
  local t = world.tuning.time
  local day = math.floor(world.state.calendar.elapsed / t.dayLength + t.startHour / 24)
  world.state.calendar.elapsed = ((day + hour / 24) - t.startHour / 24) * t.dayLength
end

local function onlyCategory(world, category)
  for _, e in ipairs(world.state.priorities) do
    e.enabled = e.category == category
  end
end

local function freeTileNearSpawn(world, objectId)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        if Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if Inventory.canPlace(world, objectId, i) then
            return i
          end
        end
      end
    end
  end
end

-- Spoilage -------------------------------------------------------------------

T.test("spoilage: fresh food decays daily, preserved keeps", function()
  local world = newWorld(1)
  Ledger.add(world, "radish", 40)
  Spoilage.daily(world)
  local left = Ledger.get(world, "radish")
  T.truthy(left >= 28 and left <= 32, "about a quarter spoils (got " .. left .. ")")
  T.eq(Ledger.get(world, "canned_food"), tun.run.startingResources.canned_food)
end)

-- Fishing --------------------------------------------------------------------

T.test("fishing: availability follows season and hour", function()
  local world = newWorld(1)
  setHour(world, 12)
  local ids = {}
  for _, f in ipairs(Fishing.available(world, false)) do
    ids[f.id] = true
  end
  T.truthy(ids.creek_chub and ids.sunfish)
  T.falsy(ids.channel_catfish, "catfish only bite at night")
  T.falsy(ids.smallmouth_bass, "bass aren't around in spring")
  setHour(world, 22)
  local night = {}
  for _, f in ipairs(Fishing.available(world, false)) do
    night[f.id] = true
  end
  T.truthy(night.channel_catfish, "catfish at night (wrapping hours)")
  for _, f in ipairs(Fishing.available(world, true)) do
    T.truthy(f.idle, f.id .. " is idle-catchable")
  end
end)

T.test("fishing: idle routine catches common fish and fills the persistent guide", function()
  local meta = {}
  local world = newWorld(5, meta)
  world.control = "idle"
  onlyCategory(world, "fish")
  setHour(world, 10)
  local caught = {}
  world.events:on("fish.caught", function(e)
    caught[#caught + 1] = e
    T.eq(e.mode, "idle")
    T.eq(reg:get("fish", e.fish).rarity, "common")
  end)
  run(world, tun.fishing.idleAttemptTime * 12)
  T.truthy(#caught >= 2, "caught some fish (" .. #caught .. ")")
  T.truthy(caught[1].first)
  local total = 0
  for _, entry in pairs(meta.fishGuide) do
    total = total + entry.count
  end
  T.eq(total, #caught)
end)

T.test("fishing: active order with the rod emits fishing.ready; hand fills the bucket", function()
  local world = newWorld(5)
  local hs = world.state.actors[1]
  local targets = {}
  for i = 1, #world.state.grid.terrain do
    if world.state.grid.terrain[i] == "water" then
      targets[i] = false
    end
  end
  local _, water = require("src.sim.pathfind").nearest(world, world.state.land.spawn, targets)
  T.truthy(water, "some reachable water")
  local ready
  world.events:on("fishing.ready", function(e)
    ready = e
  end)
  local Actors = require("src.sim.systems.actors")
  T.eq(Actors.order(world, hs, water, { tool = "rod" }).id, "fish")
  T.eq(Actors.order(world, hs, water, {}).id, "fetch_water")
  Actors.order(world, hs, water, { tool = "rod" })
  run(world, 60)
  T.truthy(ready, "reached the bank and cast")
end)

-- Mini-game ------------------------------------------------------------------

local function play(fishId, policy, seed, gear)
  gear = gear or {}
  local m = Model.new({
    fish = reg:get("fish", fishId),
    tuning = tun.fishing,
    rng = Rng.new(seed or 1),
    maxTension = gear.maxTension,
    reelSpeed = gear.reelSpeed,
  })
  local dt, t = 1 / 60, 0
  while not m.result and t < 120 do
    m:update(dt, policy(m))
    t = t + dt
  end
  return m.result
end

-- A decent player: set the hook, then reel while tension is under a threshold.
local function skilled(m)
  if m.phase == "bite" then
    return true
  end
  if m.phase == "fight" then
    return m.tension < 0.7
  end
  return false
end

T.test("minigame: a careful player lands common fish", function()
  local caught = 0
  for seed = 1, 20 do
    if play("creek_chub", skilled, seed) == "caught" then
      caught = caught + 1
    end
  end
  T.truthy(caught >= 18, "caught " .. caught .. "/20")
end)

T.test("minigame: holding nonstop snaps a strong fish off; never pressing misses", function()
  local function always(m)
    return m.phase ~= "wait"
  end
  T.eq(play("golden_trout", always, 3), "slipped")
  T.eq(play("creek_chub", function()
    return false
  end, 3), "missed")
end)

T.test("minigame: hooking then letting go lets the fish escape", function()
  local hooked = false
  local result = play("sunfish", function(m)
    if m.phase == "bite" and not hooked then
      hooked = true
      return true
    end
    return false
  end, 4)
  T.eq(result, "escaped")
end)

T.test("minigame: better gear helps against hard fish", function()
  local base, geared = 0, 0
  for seed = 1, 30 do
    if play("rainbow_trout", skilled, seed) == "caught" then
      base = base + 1
    end
    if play("rainbow_trout", skilled, seed, { maxTension = 1.25, reelSpeed = 1.15 }) == "caught" then
      geared = geared + 1
    end
  end
  T.truthy(geared >= base, string.format("geared %d >= base %d", geared, base))
end)

-- Power ----------------------------------------------------------------------

T.test("power: the folding panel charges the truck by day, not at night", function()
  local world = newWorld(2)
  local truck = world.state.land.truck
  setHour(world, 23)
  run(world, HOUR * 4)
  T.eq(Power.charge(world, truck), 0)
  setHour(world, 10)
  run(world, HOUR * 2)
  T.truthy(Power.charge(world, truck) > 0)
end)

T.test("power: first truck trip is possible within a few days", function()
  local world = newWorld(2)
  local days = 0
  while not Market.canTrip(world) and days < 10 do
    run(world, tun.time.dayLength)
    days = days + 1
  end
  T.truthy(days >= 2 and days <= 5, "first trip after " .. days .. " days")
end)

-- Market ---------------------------------------------------------------------

T.test("market: order needs money, arrives next morning", function()
  local world = newWorld(3)
  local ok, reason = Market.order(world, "radish_seeds")
  T.falsy(ok)
  T.eq(reason, "not enough money")
  Ledger.add(world, "money", 50)
  T.truthy(Market.order(world, "radish_seeds"))
  local before = Ledger.get(world, "seed_radish")
  run(world, HOUR * 2)
  T.eq(Ledger.get(world, "seed_radish"), before, "not delivered the same day")
  run(world, tun.time.dayLength)
  T.eq(Ledger.get(world, "seed_radish"), before + 5)
end)

T.test("market: equipment can't be bought twice; pickup-only needs a trip", function()
  local world = newWorld(3)
  Ledger.add(world, "money", 200)
  T.eq(Market.cannotBuy(world, "basic_rod", false), "owned")
  T.truthy(Market.order(world, "big_bucket"))
  T.eq(Market.cannotBuy(world, "big_bucket", false), "ordered")
  T.eq(Market.cannotBuy(world, "used_panel", false), "pickup only")
  T.eq(Market.cannotBuy(world, "used_panel", true), nil)
end)

T.test("market: the big bucket raises bucket capacity", function()
  local world = newWorld(3)
  local base = Water.bucketCapacity(world)
  Inventory.addEquipment(world, "big_bucket")
  T.eq(Water.bucketCapacity(world), base + 4)
end)

T.test("market: a truck trip sells the crate, limited by cargo", function()
  local world = newWorld(3)
  Ledger.add(world, "scrap", tun.economy.cargoCapacity + 10)
  Food.sort(world)
  T.falsy(Market.startTrip(world), "no charge yet")
  world.state.power.charge[world.state.land.truck] = tun.economy.tripCost
  T.truthy(Market.startTrip(world))
  local earned = Market.sellCrate(world)
  T.truthy(earned > 0)
  T.eq(Ledger.get(world, "scrap"), 10)
  T.eq(Ledger.get(world, "money"), earned)
  T.truthy(Market.buyInTown(world, "radish_seeds") or Ledger.get(world, "money") < Market.itemPrice(world, "radish_seeds"))
  Market.endTrip(world)
  T.eq(Market.sellCrate(world), 0, "can't sell from home")
end)

-- Food rules -----------------------------------------------------------------

T.test("food rules: pantry first, surplus to the crate, pins override", function()
  local world = newWorld(4)
  Ledger.add(world, "radish", 40) -- 12000 cal; pantry is 3 days = 6000
  Food.sort(world)
  local pantryUnits = math.ceil(tun.food.defaultPantryDays * tun.needs.dailyCalories / 300)
  T.eq(world.state.food.crate.radish, 40 - pantryUnits)
  Food.setPin(world, "radish", "keep")
  T.eq(world.state.food.crate.radish, nil)
  Food.setPin(world, "radish", "sell")
  T.eq(world.state.food.crate.radish, 40)
  Food.setPin(world, "radish", nil)
  Food.setDays(world, 0, 0)
  T.eq(world.state.food.crate.radish, 40)
end)

T.test("food rules: eating trims the crate reservation", function()
  local world = newWorld(4)
  Ledger.add(world, "radish", 10)
  Food.setPin(world, "radish", "sell")
  Ledger.remove(world, "radish", 4)
  T.eq(world.state.food.crate.radish, 6)
end)

T.test("food rules: fish is held for the smoker once one is placed", function()
  local world = newWorld(4)
  Ledger.add(world, "creek_chub", 30)
  Food.setDays(world, 0, 10)
  T.eq(world.state.food.crate.creek_chub, 30, "no smoker: sell")
  Inventory.addObject(world, "smoker")
  T.truthy(Inventory.place(world, "smoker", freeTileNearSpawn(world, "smoker")))
  Food.sort(world)
  T.eq(world.state.food.crate.creek_chub, nil, "smoker placed: preserve")
end)

-- Processing -----------------------------------------------------------------

T.test("processing: the routine loads the smoker and fish becomes smoked fish", function()
  local world = newWorld(6)
  world.control = "idle"
  onlyCategory(world, "process")
  Inventory.addObject(world, "smoker")
  local tile = freeTileNearSpawn(world, "smoker")
  T.truthy(Inventory.place(world, "smoker", tile))
  Ledger.add(world, "creek_chub", 6)
  Ledger.add(world, "wood", 10)
  Food.sort(world)
  run(world, 30)
  local _, anchor = Grid.object(world, tile)
  T.truthy(Processing.batch(world, anchor), "smoker loaded")
  T.eq(Ledger.get(world, "creek_chub"), 2, "a batch of 4")
  run(world, reg:get("recipes", "smoke_fish").hours * HOUR + 1)
  T.truthy(Ledger.get(world, "smoked_fish") >= 4)
end)

-- Persistence ----------------------------------------------------------------

T.test("M2 state survives a save round-trip", function()
  local meta = {}
  local world = newWorld(8, meta)
  Ledger.add(world, "money", 100)
  Market.order(world, "bait")
  Food.setPin(world, "radish", "keep")
  local data = serialize.decode(serialize.encode({ run = world.state, meta = meta }))
  local restored = World.new({ registry = reg, tuning = tun, meta = data.meta }, data.run)
  T.eq(#restored.state.market.orders, 1)
  T.eq(restored.state.food.pins.radish, "keep")
  T.truthy(Inventory.hasEquipment(restored, "basic_rod"))
end)
