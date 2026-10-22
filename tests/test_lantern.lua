-- The lantern (C7, #361, D191, docs/PLAN_DEPTH.md §5.3): a one-time buy that adds a guard to the raiders' and the fox's guard
-- roll and lowers the exposure word, with no fuel and no chore. Trip line and bell were cut.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Animals = require("src.sim.systems.animals")
local Events = require("src.sim.systems.events")
local Inventory = require("src.sim.systems.inventory")
local Lantern = require("src.sim.systems.lantern")
local Ledger = require("src.sim.systems.ledger")
local NightThreats = require("src.sim.systems.nightthreats")
local Raiders = require("src.sim.systems.raiders")
local Readiness = require("src.sim.systems.readiness")
local TonightText = require("src.ui.tonight_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local DPS = tun.time.daysPerSeason
local SUMMER = DPS + 1
local cfg = tun.lantern

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

local function duskWorld(seed)
  local world = newWorld(seed)
  setTime(world, SUMMER + 2, 19.25)
  Ledger.add(world, "potato", 20)
  return world
end

T.test("lantern: a unique one-time item taught by the fox, with no fuel or upkeep anywhere", function()
  local item = reg:get("catalog", Lantern.ITEM)
  T.truthy(item.equipment and item.unique)
  T.truthy(item.price > 0)
  T.truthy(reg:has("notes", item.needs[1]))
  T.eq(reg:has("catalog", "lantern_fuel"), false, "no fuel to buy")
  T.eq(reg:has("catalog", "trip_line"), false, "the trip line was cut")
  T.eq(reg:has("catalog", "bell"), false, "the bell was cut")
  local world = newWorld()
  T.eq(Lantern.owned(world), false)
  Inventory.addEquipment(world, Lantern.ITEM)
  T.eq(Lantern.owned(world), true)
  T.same(NightThreats.audit(world), {})
end)

T.test(
  "lantern: every guard names a threat that exists; the mice are not covered; exposure covers the same threats",
  function()
    T.eq(rawget(cfg.guards, "mice"), nil, "the mice are the cat's")
    for id, g in pairs(cfg.guards) do
      T.truthy(reg:has("night_threats", id), id .. " is a night threat")
      T.truthy(g > 0 and g < 1)
    end
    local world = newWorld()
    Inventory.addEquipment(world, Lantern.ITEM)
    local covered = {}
    for _, id in ipairs(tun.night.exposure.guards[Lantern.ITEM].covers) do
      covered[id] = true
      T.truthy(Lantern.covers(world, id), "exposure covers only what the lantern guards: " .. id)
    end
    for id in pairs(cfg.guards) do
      T.truthy(covered[id], "exposure covers " .. id)
    end
    T.eq(Lantern.guard(world, "mice"), 0)
  end
)

T.test("lantern: it turns a raccoon back inside the guard roll; the stream does not depend on it", function()
  with({ { tun.raiders.raccoon, "chancePerDay", 8 } }, function()
    local plain, lit = duskWorld(5), duskWorld(5)
    Inventory.addEquipment(lit, Lantern.ITEM)
    local def = reg:get("night_threats", "raccoon")
    local pa, pb = Raiders.nightPlan(plain, 1, def), Raiders.nightPlan(lit, 1, def)
    T.truthy(pa and pb)
    T.eq(pa.guardRoll, pb.guardRoll)
    pa.guardRoll, pb.guardRoll = cfg.guards.raccoon - 0.01, cfg.guards.raccoon - 0.01
    T.eq(Raiders.nightLand(plain, pa), "raided", "no lantern, no bins: it gets in")
    T.eq(Raiders.nightLand(lit, pb), "stopped", "the lantern turned it back")
    T.eq(Ledger.get(lit, "potato"), 20)
  end)
end)

T.test("lantern: it adds its fox guard to the coop's and the pen's, capped", function()
  local world = newWorld()
  local hens, goats = Animals.guard(world), Animals.guard(world, "goats")
  Inventory.addEquipment(world, Lantern.ITEM)
  local cap = tun.animals.predators.maxGuard
  T.near(Animals.guard(world), math.min(cap, hens + cfg.guards.fox), 1e-9)
  T.near(Animals.guard(world, "goats"), math.min(cap, goats + cfg.guards.fox), 1e-9)
end)

T.test("lantern: it lowers the exposure for what it covers, not for mice", function()
  local world = newWorld(2)
  local base, baseFox, baseMice = Events.exposure(world), Events.exposure(world, "fox"), Events.exposure(world, "mice")
  Inventory.addEquipment(world, Lantern.ITEM)
  local x = tun.night.exposure
  local points = x.guards[Lantern.ITEM].points
  T.near(Events.exposure(world).points, math.max(x.min, base.points - points), 1e-9)
  T.near(Events.exposure(world, "fox").points, math.max(x.min, baseFox.points - points), 1e-9)
  T.eq(Events.exposure(world, "mice").points, baseMice.points, "the mice are not covered")
end)

T.test("lantern: the Tonight card names it among what lowers the exposure", function()
  local world = newWorld(2)
  T.same(Readiness.tonight(world).exposure.guards, {})
  Inventory.addEquipment(world, Lantern.ITEM)
  T.same(Readiness.tonight(world).exposure.guards, { "lantern" })
  local model = TonightText.build(Readiness.tonight(world), {})
  T.truthy(model.notes[2].text:find("antern on watch", 1, true), model.notes[2].text)
end)

T.test("lantern: it has no state of its own, so a save carries nothing extra", function()
  local world = newWorld()
  Inventory.addEquipment(world, Lantern.ITEM)
  T.eq(world.state.lantern, nil)
  local copy = serialize.decode(serialize.encode(world.state))
  T.truthy(copy.inventory ~= nil)
end)
