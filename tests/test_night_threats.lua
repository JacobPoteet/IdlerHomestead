-- The night threat framework (D187, #355, docs/PLAN_DEPTH.md §5, §6.1, §6.5, src/sim/systems/nightthreats.lua): mice and the
-- fox planned at dusk and landed at 23:00, one a night through the shared slot, exposure as a word, the dusk sign, the mercy
-- rules, and the same raids from the same seeds as the old roll.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Animals = require("src.sim.systems.animals")
local Cat = require("src.sim.systems.cat")
local Events = require("src.sim.systems.events")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local NightThreats = require("src.sim.systems.nightthreats")
local Nightly = require("src.sim.systems.nightly")
local Readiness = require("src.sim.systems.readiness")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local AUTUMN = 2 * DPS + 1
local mice, pred, catCfg = tun.cat.mice, tun.animals.predators, tun.cat.cat
local RAID_HOUR = mice.raidHour

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function clear(world)
  world.state.weather.sky.days[1] = "clear"
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

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

--- Place a coop and keep `n` hens in it (hens live only where a coop gives them room).
local function keepHens(world, n)
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
  Inventory.addObject(world, "chicken_coop")
  T.truthy(Inventory.place(world, "chicken_coop", best), "a spot for the coop")
  Ledger.add(world, "hen", n, "test")
end

--- A late-autumn night just after sunset: 20 potatoes in store, both threats certain, no animals yet.
local function duskWorld(seed)
  local world = newWorld(seed)
  setTime(world, AUTUMN + 2, 19.25)
  clear(world)
  Ledger.add(world, "potato", 20)
  return world
end

local CERTAIN = {
  { mice, "chancePerDay", 4 },
  { pred, "chancePerDay", 4 },
  { pred, "maxGuard", 0 },
}

local function tick(world, n)
  for _ = 1, n or 1 do
    world:tick(STEP)
  end
end

-- Content ---------------------------------------------------------------------------------------

T.test("night threats: the content audit finds nothing, and mice and the fox are in it", function()
  local world = newWorld()
  T.same(NightThreats.audit(world), {})
  T.truthy(reg:has("night_threats", "mice") and reg:has("night_threats", "fox"))
  T.eq(reg:get("night_threats", "fox").outcomes.landed.capital, true)
end)

-- Same seeds, same raids --------------------------------------------------------------------------

T.test("night threats: planning then landing is the old raid roll, draw for draw", function()
  with({ { mice, "chancePerDay", 0.5 } }, function()
    local d = reg:get("night_threats", "mice")
    local weight = d.exposure
    d.exposure = 0 -- exposure off: the odds are the handler's own
    local ok, err = pcall(function()
      for seed = 1, 12 do
        local a, b = duskWorld(seed), duskWorld(seed)
        setTime(a, AUTUMN + 2, RAID_HOUR + 0.25)
        setTime(b, AUTUMN + 2, RAID_HOUR + 0.25)
        NightThreats.plan(a)
        NightThreats.land(a)
        Cat.raid(b)
        T.eq(Ledger.get(a, "potato"), Ledger.get(b, "potato"), "seed " .. seed .. " ruins the same food")
        T.eq(a.state.rng.mice.s, b.state.rng.mice.s, "seed " .. seed .. " draws the same stream")
      end
    end)
    d.exposure = weight
    assert(ok, err)
  end)
end)

T.test("night threats: the fox draws as it did, plan then land", function()
  with({ { pred, "chancePerDay", 0.5 } }, function()
    local d = reg:get("night_threats", "fox")
    local weight = d.exposure
    d.exposure = 0
    local ok, err = pcall(function()
      for seed = 1, 12 do
        local a, b = duskWorld(seed), duskWorld(seed)
        for _, w in ipairs({ a, b }) do
          keepHens(w, 4)
          setTime(w, AUTUMN + 2, RAID_HOUR + 0.25)
        end
        NightThreats.plan(a)
        NightThreats.land(a)
        Animals.raid(b)
        T.eq(Animals.hens(a), Animals.hens(b), "seed " .. seed .. " loses the same hens")
        T.eq(a.state.rng.predators.s, b.state.rng.predators.s)
      end
    end)
    d.exposure = weight
    assert(ok, err)
  end)
end)

-- One threat a night ------------------------------------------------------------------------------

T.test("night threats: one threat a night through the shared slot, and the `night` stream picks between two", function()
  with(CERTAIN, function()
    local seen = {}
    for seed = 1, 24 do
      local world = duskWorld(seed)
      keepHens(world, 4)
      local landed = collect(world, "nightthreat.resolved")
      NightThreats.plan(world)
      local tonight = NightThreats.tonight(world)
      T.truthy(tonight, "something comes when both are certain")
      T.eq(Events.slot(world).kind, "threat")
      T.eq(Events.slot(world).id, tonight.id)
      seen[tonight.id] = true
      setTime(world, AUTUMN + 2, RAID_HOUR + 0.25)
      NightThreats.land(world)
      T.eq(#landed, 1, "one threat a night")
      T.eq(world.state.rng.night ~= nil, true, "its own stream")
      local took = (Ledger.get(world, "potato") < 20 and 1 or 0) + (Animals.hens(world) < 4 and 1 or 0)
      T.eq(took, 1, "and only one thing was taken")
    end
    T.truthy(seen.mice and seen.fox, "both come on some nights")
  end)
end)

T.test("night threats: the dusk plan runs from the tick before the event draw and takes its slot", function()
  with(CERTAIN, function()
    tun.events.chancePerNight = 1
    local ok, err = pcall(function()
      local world = duskWorld(3)
      keepHens(world, 4)
      world.state.events.quiet = 3
      tick(world, 2) -- past sunset: the threat is planned, then the event system sees a taken slot
      T.truthy(NightThreats.tonight(world))
      T.eq(#world.state.events.scheduled, 0, "no event on a night a threat took the slot")
      T.eq(world.state.events.quiet, 3, "the pity timer waits for the threat to end")
      setTime(world, AUTUMN + 2, RAID_HOUR + 0.25)
      tick(world)
      T.eq(NightThreats.tonight(world).status, "done")
      T.eq(world.state.events.quiet, 0, "and resets once it has")
    end)
    tun.events.chancePerNight = 0.3
    assert(ok, err)
  end)
end)

T.test(
  "night threats: turned away uses the slot and resets the pity timer but starts no cooldown; landed starts it",
  function()
    with({ { mice, "chancePerDay", 4 }, { catCfg, "fedCatch", 1 }, { catCfg, "hungryCatch", 1 } }, function()
      local world = duskWorld(2)
      Inventory.addEquipment(world, Cat.ITEM)
      Cat.tick(world, STEP)
      world.state.events.quiet = 3
      NightThreats.plan(world)
      T.eq(NightThreats.tonight(world).id, "mice")
      NightThreats.land(world)
      T.eq(NightThreats.tonight(world).outcome, "turned")
      T.eq(world.state.events.quiet, 0)
      T.eq(world.state.events.coolUntil, 0, "a turned-away threat starts no cooldown")
      T.eq(NightThreats.counts(world, "mice").turned, 1)
    end)
    with({ { mice, "chancePerDay", 4 } }, function()
      local world = duskWorld(2)
      NightThreats.plan(world)
      NightThreats.land(world)
      T.eq(NightThreats.tonight(world).outcome, "landed")
      local day = AUTUMN + 2
      T.eq(world.state.events.coolUntil, day + tun.events.badCooldownNights)
      T.eq(NightThreats.counts(world, "mice").landed, 1)
      T.truthy(Ledger.get(world, "potato") < 20)
    end)
  end
)

T.test("night threats: a night no threat hits leaves the slot to the events", function()
  with({ { mice, "chancePerDay", 0 }, { pred, "chancePerDay", 0 } }, function()
    local world = duskWorld(1)
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world), nil)
    T.eq(Events.slot(world), nil)
    T.eq(NightThreats.sign(world), nil)
  end)
end)

T.test("night threats: a threat outside its content gates does not come", function()
  with({ { mice, "chancePerDay", 4 } }, function()
    local d = reg:get("night_threats", "mice")
    local keep = d.seasons
    rawset(d, "seasons", { "spring" }) -- a gate the shipped threats do not use
    local ok, err = pcall(function()
      local world = duskWorld(1) -- autumn
      NightThreats.plan(world)
      T.eq(NightThreats.tonight(world), nil)
      rawset(d, "seasons", { "autumn" })
      rawset(d, "minYear", 2)
      NightThreats.plan(duskWorld(1))
      T.eq(NightThreats.tonight(duskWorld(1)), nil, "nothing is planned before the tick")
    end)
    rawset(d, "seasons", keep)
    rawset(d, "minYear", nil)
    assert(ok, err)
  end)
end)

-- The dusk sign ------------------------------------------------------------------------------------

T.test(
  "night threats: the dusk sign shows on the Tonight card once the threat is drawn and goes when it has landed",
  function()
    with({ { mice, "chancePerDay", 4 } }, function()
      local world = newWorld(2)
      setTime(world, AUTUMN + 2, 15) -- before sunset: nothing is drawn yet
      clear(world)
      Ledger.add(world, "potato", 20)
      tick(world)
      for _, r in ipairs(Readiness.tonight(world).risks) do
        T.truthy(r.id ~= "sign")
      end
      setTime(world, AUTUMN + 2, 19.25)
      tick(world)
      local sign
      for _, r in ipairs(Readiness.tonight(world).risks) do
        if r.id == "sign" then
          sign = r
        end
      end
      T.truthy(sign, "the sign is there after sunset")
      T.eq(sign.threat, NightThreats.sign(world).id)
      T.eq(sign.line, reg:get("night_threats", sign.threat).warn.line)
      setTime(world, AUTUMN + 2, RAID_HOUR + 0.25)
      tick(world)
      T.eq(NightThreats.sign(world), nil, "gone once it has landed")
    end)
  end
)

T.test("night threats: a threat that will be turned away is signed too", function()
  with({ { mice, "chancePerDay", 4 }, { catCfg, "fedCatch", 1 } }, function()
    local world = duskWorld(2)
    Inventory.addEquipment(world, Cat.ITEM)
    Cat.tick(world, STEP)
    NightThreats.plan(world)
    T.truthy(NightThreats.sign(world))
  end)
end)

-- Exposure -------------------------------------------------------------------------------------------

T.test("night threats: exposure runs low to high by shelter, stores and animals, and the card gets the word", function()
  local x = tun.night.exposure
  local world = newWorld(2)
  local base = Events.exposure(world)
  T.truthy(base.points >= x.min and base.points <= x.max)
  T.eq(base.word, "high", "the truck gives the night the most to work with")
  T.eq(base.parts.animals, 0)
  Ledger.add(world, "smoked_fish", 3)
  keepHens(world, 6)
  local more = Events.exposure(world)
  T.truthy(more.points > base.points or base.points == x.max)
  T.eq(more.parts.stores[1], "smoked_fish")
  T.eq(more.parts.animals, 6)
  T.eq(Readiness.tonight(world).exposure.points, nil, "the Tonight card never sees points")
  T.eq(Readiness.tonight(world).exposure.word, more.word)
end)

T.test("night threats: a guard lowers exposure only for the threats it covers", function()
  local x = tun.night.exposure
  with({ { x, "guards", { shelter_cat = { points = 2, covers = { "fox" } } } } }, function()
    local world = newWorld(2)
    local without = Events.exposure(world)
    Inventory.addEquipment(world, Cat.ITEM)
    local with_ = Events.exposure(world)
    T.near(with_.points, math.max(x.min, without.points - 2), 1e-9, "the word on the card counts every guard")
    T.near(Events.exposure(world, "fox").points, with_.points, 1e-9)
    T.eq(Events.exposure(world, "mice").points, without.points, "mice are not covered")
    T.eq(with_.parts.guards[1], "shelter_cat")
    T.truthy(
      NightThreats.scale(world, reg:get("night_threats", "fox"))
        < NightThreats.scale(world, reg:get("night_threats", "mice"))
    )
  end)
end)

T.test("night threats: exposure scales a threat's chance by its content weight", function()
  local world = newWorld(2)
  local d = reg:get("night_threats", "fox")
  local m = Events.exposure(world, "fox").multiplier
  T.near(NightThreats.scale(world, d), 1 + (m - 1) * d.exposure, 1e-9)
  local weight = d.exposure
  d.exposure = 0
  local ok, err = pcall(function()
    T.near(NightThreats.scale(world, d), 1, 1e-9, "a threat exposure does not shape is unscaled")
  end)
  d.exposure = weight
  assert(ok, err)
end)

-- Mercy ----------------------------------------------------------------------------------------------

T.test(
  "night threats: while Footing is slipped the chance is eased, and the fox takes feed, never the animals",
  function()
    with(CERTAIN, function()
      local world = newWorld(2)
      local d = reg:get("night_threats", "fox")
      local normal = NightThreats.scale(world, d)
      world.state.footing.slipped = true
      T.near(NightThreats.scale(world, d), normal * tun.events.mercy.slippedThreatScale, 1e-9)
      local world2 = duskWorld(2)
      world2.state.footing.slipped = true
      keepHens(world2, 4)
      Ledger.add(world2, "chicken_feed", 10)
      -- Only the fox may come: the mice stay away for this case.
      with({ { mice, "chancePerDay", 0 } }, function()
        NightThreats.plan(world2)
        T.eq(NightThreats.tonight(world2).id, "fox")
        setTime(world2, AUTUMN + 2, RAID_HOUR + 0.25)
        local resolved = collect(world2, "nightthreat.resolved")
        NightThreats.land(world2)
        T.eq(Animals.hens(world2), 4, "no hen is lost while slipped")
        T.eq(resolved[1].outcome, "spared")
        T.eq(
          Ledger.get(world2, "chicken_feed"),
          10 - reg:get("night_threats", "fox").outcomes.landed.lesser.lose.chicken_feed
        )
        T.eq(resolved[1].lost.chicken_feed, 3)
      end)
    end)
    with(CERTAIN, function()
      local world = duskWorld(2)
      keepHens(world, 4)
      with({ { mice, "chancePerDay", 0 } }, function()
        NightThreats.plan(world)
        setTime(world, AUTUMN + 2, RAID_HOUR + 0.25)
        NightThreats.land(world)
        T.truthy(Animals.hens(world) < 4, "with Footing held the fox still takes a hen")
      end)
    end)
  end
)

T.test("night threats: the chance is eased while the post-bad cooldown runs", function()
  local world = newWorld(2)
  setTime(world, 9, 12)
  local d = reg:get("night_threats", "mice")
  local normal = NightThreats.scale(world, d)
  world.state.events.coolUntil = 9
  T.truthy(Events.cooling(world))
  T.near(NightThreats.scale(world, d), normal * tun.night.threats.coolingScale, 1e-9)
  world.state.events.coolUntil = 8
  T.falsy(Events.cooling(world))
end)

-- The morning report and the wake hook ---------------------------------------------------------------

T.test("night threats: the night's ledger lists what was turned away", function()
  with({ { mice, "chancePerDay", 4 }, { catCfg, "fedCatch", 1 } }, function()
    local world = duskWorld(2)
    Inventory.addEquipment(world, Cat.ITEM)
    Cat.tick(world, STEP)
    NightThreats.plan(world)
    NightThreats.land(world)
    local threats = world.state.nightly.open.threats
    T.eq(#threats, 1)
    T.eq(threats[1].id, "mice")
    T.eq(threats[1].outcome, "turned")
    T.truthy(Nightly)
  end)
end)

-- A night event that may wake, made from a shipped one for the length of `fn` (the wake events arrive with their packs).
local function withWakeEvent(fn)
  local e = reg:get("events", "bad_tooth")
  local when, wake = e.when, e.wake
  e.when, e.wake = "night", true
  local ok, err = pcall(fn, e)
  e.when, e.wake = when, wake
  assert(ok, err)
end

T.test("night threats: a wake event goes through the event engine's own road and rules", function()
  withWakeEvent(function(e)
    with({ { mice, "chancePerDay", 4 } }, function()
      local d = reg:get("night_threats", "mice")
      local world = duskWorld(2)
      rawset(d, "wake", e.id)
      local ok, err = pcall(function()
        T.same(NightThreats.audit(world), {}, "a night event that may wake is a valid wake")
        NightThreats.plan(world)
        setTime(world, AUTUMN + 2, RAID_HOUR + 0.25)
        NightThreats.land(world)
        T.eq(#world.state.events.scheduled, 1, "scheduled, not forced")
        T.eq(world.state.events.scheduled[1].id, e.id)
        T.eq(#world.state.events.pending, 0, "the mercy checks run when it comes due")
      end)
      rawset(d, "wake", nil)
      assert(ok, err)
    end)
  end)
end)

T.test("night threats: the wake hook refuses a day event and the nights before the quiet start", function()
  local world = newWorld(2)
  setTime(world, AUTUMN, 12)
  T.falsy(Events.scheduleWake(world, "sprained_ankle"), "an event that cannot wake is not scheduled")
  withWakeEvent(function(e)
    setTime(world, tun.events.firstNight - 1, 12)
    T.falsy(Events.scheduleWake(world, e.id), "none before night 3")
    setTime(world, tun.events.firstNight, 12)
    T.truthy(Events.scheduleWake(world, e.id))
  end)
  local bad = reg:get("night_threats", "mice")
  rawset(bad, "wake", "sprained_ankle")
  local problems = NightThreats.audit(world)
  rawset(bad, "wake", nil)
  T.eq(#problems, 1, "the audit refuses a wake that is a day event")
end)

-- Save ------------------------------------------------------------------------------------------------

T.test("night threats: the state survives a save round trip", function()
  with({ { mice, "chancePerDay", 4 } }, function()
    local world = duskWorld(2)
    NightThreats.plan(world)
    local decoded = serialize.decode(serialize.encode(world.state))
    T.eq(decoded.nightthreats.tonight.id, NightThreats.tonight(world).id)
    T.eq(decoded.nightthreats.planDay, world.state.nightthreats.planDay)
    local loaded = World.new({ registry = reg, tuning = tun }, decoded)
    T.eq(NightThreats.tonight(loaded).status, "pending")
    setTime(loaded, AUTUMN + 2, RAID_HOUR + 0.25)
    tick(loaded)
    T.eq(NightThreats.tonight(loaded).status, "done")
  end)
end)
