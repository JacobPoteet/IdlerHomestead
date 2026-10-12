-- Finds (GDD §8.4, D53): "pick 1 of 3" offers, seeded per run, answered in a modal.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Finds = require("src.sim.systems.finds")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.finds
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

--- Run a day's roll with the chance forced to `p`. Returns nothing; read Finds.isDue / pending.
local function roll(world, day, p, systemOnly)
  local original = cfg.chancePerDay
  cfg.chancePerDay = p
  setTime(world, day, cfg.rollHour + 0.5)
  if systemOnly then
    Finds.tick(world) -- just this system, for tests that fake the homesteader's job
  else
    world:tick(STEP)
  end
  cfg.chancePerDay = original
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

local function distinct(list)
  local seen = {}
  for _, id in ipairs(list) do
    T.falsy(seen[id], "duplicate " .. id)
    seen[id] = true
  end
end

T.test("finds: content effects reference real resources, objects and catalog equipment", function()
  T.truthy(#reg:all("finds") >= cfg.choices + 2, "enough finds for variety")
  for _, def in ipairs(reg:all("finds")) do
    for id in pairs(def.effects.resources or {}) do
      T.truthy(reg:has("resources", id), def.id .. " resource " .. id)
    end
    for id in pairs(def.effects.objects or {}) do
      T.truthy(reg:has("objects", id), def.id .. " object " .. id)
    end
    for _, id in ipairs(def.effects.equipment or {}) do
      T.truthy(reg:get("catalog", id).equipment, def.id .. " equipment " .. id)
    end
    for season in pairs(def.seasons or {}) do
      T.truthy(season == "spring" or season == "summer" or season == "autumn" or season == "winter", season)
    end
    if def.lacks and def.lacks.resource then
      T.truthy(reg:has("resources", def.lacks.resource))
    end
  end
end)

T.test("finds: an offer has distinct choices and the same seed gives the same offer", function()
  local offers = {}
  for run = 1, 2 do
    local w = newWorld(7)
    setTime(w, SPRING + 4, 10)
    local pending = Finds.offer(w)
    T.eq(#pending.choices, cfg.choices)
    distinct(pending.choices)
    offers[run] = pending.choices
  end
  T.same(offers[1], offers[2])
  -- Another seed can differ (any seed in a handful does).
  local differs = false
  for seed = 8, 14 do
    local w = newWorld(seed)
    setTime(w, SPRING + 4, 10)
    differs = differs or table.concat(Finds.offer(w).choices) ~= table.concat(offers[1])
  end
  T.truthy(differs)
end)

T.test("finds: choosing applies the effects and the others are gone", function()
  local w = newWorld(3)
  setTime(w, SPRING + 4, 10)
  local picked = collect(w, "finds.picked")
  local pending = Finds.offer(w)
  local first, second = pending.choices[1], pending.choices[2]
  T.truthy(Finds.choose(w, first))
  T.eq(Finds.pending(w), nil)
  T.eq(#picked, 1)
  T.eq(picked[1].find, first)
  T.same(picked[1].offered, pending.choices)
  local ok, reason = Finds.choose(w, second)
  T.falsy(ok)
  T.eq(reason, "no offer")
  T.eq(Finds.history(w)[1].picked, first)
end)

T.test("finds: an id that was not offered is refused", function()
  local w = newWorld(3)
  Finds.offer(w)
  local pending = Finds.pending(w)
  local other
  for _, def in ipairs(reg:all("finds")) do
    local listed = false
    for _, id in ipairs(pending.choices) do
      listed = listed or id == def.id
    end
    if not listed then
      other = def.id
    end
  end
  local ok, reason = Finds.choose(w, other)
  T.falsy(ok)
  T.eq(reason, "not offered")
  T.truthy(Finds.pending(w), "still pending")
end)

T.test("finds: each effect kind goes through the existing systems", function()
  local w = newWorld(5)
  local seeds, cans = Ledger.get(w, "seed_potato"), Ledger.get(w, "canned_food")
  local function take(id)
    w.state.finds.pending = { day = 1, choices = { id } }
    T.truthy(Finds.choose(w, id))
  end
  take("heirloom_seeds")
  T.eq(Ledger.get(w, "seed_potato"), seeds + 6)
  take("dusty_cans")
  T.eq(Ledger.get(w, "canned_food"), cans + 5)
  local panels = Inventory.objectCount(w, "folding_panel")
  take("used_panel")
  T.eq(Inventory.objectCount(w, "folding_panel"), panels + 1)
  T.falsy(Inventory.hasEquipment(w, "axe"))
  take("rusty_axe")
  T.truthy(Inventory.hasEquipment(w, "axe"))
  local truck = Land.truck(w)
  local charge = Power.charge(w, truck)
  take("jump_pack")
  T.truthy(Power.charge(w, truck) > charge)
  local money = Ledger.get(w, "money")
  take("loose_cash")
  T.eq(Ledger.get(w, "money"), money + 25)
end)

T.test("finds: equipment already owned is never offered", function()
  local w = newWorld(5)
  Inventory.addEquipment(w, "axe")
  T.eq(Finds.weight(w, "rusty_axe"), 0)
  for seed = 1, 30 do
    local x = newWorld(seed)
    Inventory.addEquipment(x, "axe")
    for _, id in ipairs(Finds.draw(x)) do
      T.truthy(id ~= "rusty_axe")
    end
  end
end)

T.test("finds: weights follow the season and what the player lacks", function()
  local w = newWorld(5)
  setTime(w, SPRING + 1, 10)
  local spring = Finds.weight(w, "heirloom_seeds")
  setTime(w, WINTER + 1, 10)
  T.truthy(spring > Finds.weight(w, "heirloom_seeds") * 5, "seed tin is a spring thing")
  setTime(w, AUTUMN + 1, 10)
  local stocked = Finds.weight(w, "dusty_cans")
  Ledger.remove(w, "canned_food", Ledger.get(w, "canned_food"))
  T.near(Finds.weight(w, "dusty_cans"), stocked * cfg.lackBoost, 1e-9)
  setTime(w, SUMMER, 10)
  T.truthy(Finds.weight(w, "used_panel") > 0)
end)

T.test("finds: the daily roll queues an offer, respects first day and cooldown", function()
  local w = newWorld(11)
  roll(w, 1, 1)
  T.falsy(Finds.isDue(w), "too early in the run")
  roll(w, cfg.firstDay, 1)
  T.truthy(Finds.isDue(w) or Finds.pending(w), "roll hit")
  T.truthy(Finds.pending(w), "calm moment: offered at once")
  Finds.choose(w, Finds.pending(w).choices[1])
  -- Cooldown from the pick day.
  local pickDay = w.state.finds.lastPick
  roll(w, pickDay + cfg.cooldownDays - 1, 1)
  T.falsy(Finds.isDue(w) or Finds.pending(w), "cooling down")
  roll(w, pickDay + cfg.cooldownDays, 1)
  T.truthy(Finds.pending(w), "cooldown over")
end)

T.test("finds: chance 0 never offers and the frequency is occasional", function()
  local w = newWorld(12)
  for day = 1, 40 do
    roll(w, day, 0)
  end
  T.falsy(Finds.pending(w))
  T.eq(#Finds.history(w), 0)
  -- With the real chance, answering every offer, a run of weeks sees a few and not a flood.
  local x = newWorld(12)
  local offers = collect(x, "finds.offered")
  for day = 1, 4 * DPS do
    setTime(x, day, cfg.rollHour + 0.5)
    x:tick(STEP)
    if Finds.pending(x) then
      Finds.choose(x, Finds.pending(x).choices[1])
    end
  end
  T.truthy(#offers >= 1 and #offers <= 4 * DPS / cfg.cooldownDays, "offers in a season: " .. #offers)
end)

T.test("finds: not offered while the homesteader rests or fishes; queued, then offered", function()
  local w = newWorld(13)
  local hs = Actors.homesteader(w)
  -- Resting.
  hs.asleep = true
  roll(w, cfg.firstDay + 2, 1)
  T.truthy(Finds.isDue(w), "queued")
  T.falsy(Finds.pending(w), "not while resting")
  hs.asleep = false
  w:tick(STEP)
  T.truthy(Finds.pending(w), "offered when awake")
  Finds.choose(w, Finds.pending(w).choices[1])
  -- Fishing by hand.
  local x = newWorld(14)
  local actor = Actors.homesteader(x)
  actor.job = { task = "fish", ordered = true, path = {}, step = 1 }
  roll(x, cfg.firstDay + 2, 1, true)
  T.truthy(Finds.isDue(x))
  T.falsy(Finds.pending(x), "not mid-fishing")
  actor.job = nil
  Finds.tick(x)
  T.truthy(Finds.pending(x))
  -- Bedtime (late evening) counts too.
  local y = newWorld(15)
  setTime(y, cfg.firstDay + 2, 23.5)
  T.truthy(Finds.isBusy(y))
end)

T.test("finds: a pending offer waits, is not replaced, and survives a save round trip", function()
  local a = newWorld(21)
  setTime(a, SPRING + 4, 10)
  local pending = Finds.offer(a)
  local choices = { unpack(pending.choices) }
  roll(a, SPRING + 12, 1)
  T.same(Finds.pending(a).choices, choices)
  local b = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  T.same(Finds.pending(b).choices, choices)
  T.truthy(Finds.choose(b, choices[2]))
  T.eq(Finds.history(b)[1].picked, choices[2])
  -- The stream continues the same way from the saved state.
  local c = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  Finds.choose(a, choices[2])
  Finds.choose(c, choices[2])
  T.same(Finds.draw(a), Finds.draw(c))
end)

T.test("finds: a due-but-queued offer survives a save and a save from before finds loads", function()
  local a = newWorld(22)
  a.state.finds.due = true
  local b = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  T.truthy(Finds.isDue(b))
  local old = serialize.decode(serialize.encode(newWorld(23).state))
  old.finds = nil
  old.rng.finds = nil
  local c = World.new({ registry = reg, tuning = tun }, old)
  T.eq(Finds.pending(c), nil)
  T.eq(#Finds.history(c), 0)
  roll(c, SPRING + 5, 1)
  T.truthy(Finds.pending(c))
  local half = serialize.decode(serialize.encode(newWorld(24).state))
  half.finds = { rollDay = 3 }
  local d = World.new({ registry = reg, tuning = tun }, half)
  T.eq(#Finds.history(d), 0)
  T.eq(Finds.isDue(d), false)
end)

T.test("finds: a paused sim never rolls or offers", function()
  local w = newWorld(31)
  setTime(w, SPRING + 5, 10)
  -- Nothing ticks, nothing happens: state is untouched.
  T.falsy(Finds.isDue(w))
  T.falsy(Finds.pending(w))
  T.eq(w.state.finds.rollDay, 0)
end)
