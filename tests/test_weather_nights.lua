-- Weather nights (C5, #359, D190, docs/PLAN_DEPTH.md §6.1, src/sim/systems/weather.lua): the cold front and the pipe
-- freeze on the night threat framework. The front is a forecast miss that raises tonight's warmth need from dusk; the pipe
-- freeze stops the pumps and the morning's cistern drink until noon, and has free answers (a shack, lagging, a little
-- wood). Neither can empty a larder, kill a plant or cost more than a share of a night's wood.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Events = require("src.sim.systems.events")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local NightThreats = require("src.sim.systems.nightthreats")
local Power = require("src.sim.systems.power")
local Readiness = require("src.sim.systems.readiness")
local Shelter = require("src.sim.systems.shelter")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local DPS = tun.time.daysPerSeason
local AUTUMN, WINTER = 2 * DPS + 1, 3 * DPS + 1
local FRONT, PIPES = tun.weather.coldFront, tun.weather.pipeFreeze

-- Only the weather nights have a chance in this file: the animals and the raiders stay home.
tun.cat.mice.chancePerDay = 0
for _, id in ipairs({ "raccoon", "deer", "bear" }) do
  tun.raiders[id].chancePerDay = 0
end

local function newWorld(seed, meta)
  local world = World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
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

-- A certain cold front in autumn and winter (the pipes never freeze unless a test asks).
local function frontOnly(fn, extra)
  local overrides = {
    { FRONT.chance, "autumn", 8 },
    { FRONT.chance, "winter", 8 },
    { PIPES, "chance", 0 },
  }
  for _, o in ipairs(extra or {}) do
    overrides[#overrides + 1] = o
  end
  with(overrides, fn)
end

-- A certain pipe freeze, and no cold front.
local function pipesOnly(fn, extra)
  local overrides = {
    { FRONT.chance, "autumn", 0 },
    { FRONT.chance, "winter", 0 },
    { PIPES, "chance", 8 },
  }
  for _, o in ipairs(extra or {}) do
    overrides[#overrides + 1] = o
  end
  with(overrides, fn)
end

--- Place an object on the nearest free tile to the spawn where it fits.
local function place(world, id)
  local grid = world.state.grid
  local nx, ny = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - nx) ^ 2 + (y - ny) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  T.truthy(best, "a spot for " .. id)
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

--- A night just after sunset on `day` (the Tonight card's hour), nothing special in the larder.
local function duskWorld(seed, day, hour, meta)
  local world = newWorld(seed, meta)
  setTime(world, day, hour or 19.25)
  return world
end

local function landAt(world, hour)
  setTime(world, Events.slot(world).day, hour)
  return NightThreats.land(world)
end

-- Content ----------------------------------------------------------------------------------------------

T.test("weather nights: both are content on the weather handler and the audit finds nothing", function()
  local world = newWorld()
  T.same(NightThreats.audit(world), {})
  for _, id in ipairs({ "cold_front", "pipe_freeze" }) do
    local d = reg:get("night_threats", id)
    T.eq(d.handler, "weather")
    T.eq(d.exposure, 0, "weather is attracted by nothing")
    T.truthy(d.warn.line and d.outcomes.turned.report and d.outcomes.landed.report)
    T.truthy(reg:has("notes", d.journalNote))
  end
  T.same(reg:get("night_threats", "pipe_freeze").seasons, { "winter" })
  T.same(reg:get("night_threats", "cold_front").seasons, { "autumn", "winter" })
  local lagging = reg:get("catalog", "pipe_lagging")
  T.truthy(lagging.equipment and lagging.modifiers.pipeGuard >= 1)
  T.eq(lagging.needs[1], "pipe_freeze", "the first freeze writes the note that teaches it")
  T.eq(reg:has("night_threats", "windstorm"), false, "windstorm is cut (D184)")
  T.eq(reg:has("night_threats", "power_outage"), false, "power outage is cut (D184)")
  T.truthy(PIPES.shelterRank <= reg:get("objects", "shack").shelterRank, "a shack keeps the pipes")
  T.truthy(reg:get("objects", "camp").shelterRank < PIPES.shelterRank, "a camp does not")
end)

-- The cold front -----------------------------------------------------------------------------------------

T.test("cold front: planned at dusk, it raises tonight's warmth need from the sign until the midnight draw", function()
  frontOnly(function()
    local world = duskWorld(3, AUTUMN + 4)
    local before = Needs.warmthNeeded(world)
    T.truthy(before > 0, "an autumn night needs a fire")
    T.eq(Weather.frontTonight(world), false)
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world).id, "cold_front")
    T.eq(Events.slot(world).kind, "threat", "it claims the night slot")
    T.truthy(NightThreats.sign(world).line:find("cold front"), "the dusk sign names it")
    T.eq(Weather.frontTonight(world), true)
    T.near(Needs.warmthNeeded(world), before * FRONT.warmthMultiplier, 1e-9)
    T.truthy(landAt(world, FRONT.hour + 0.25))
    local last = NightThreats.history(world)[1]
    T.eq(last.outcome, "landed", "a front is never turned away")
    T.eq(Weather.frontTonight(world), true, "still on until the night's draw has used it")
    Needs.warm(world) -- the midnight draw
    T.eq(Weather.frontTonight(world), false, "over once the draw has used it")
    T.near(Needs.warmthNeeded(world), before, 1e-9)
  end)
end)

T.test(
  "cold front: the Tonight card, the thermostat and the draw all use the raised need; the forecast does not",
  function()
    frontOnly(function()
      local world = duskWorld(4, WINTER + 1)
      local forecast = Weather.expectedWarmthNeed(world, "winter", world.state.calendar.day - 3 * DPS)
      NightThreats.plan(world)
      local need = Needs.warmthNeeded(world)
      T.near(Readiness.tonight(world).warmth.need, need, 1e-9, "the Tonight card")
      T.near(
        need,
        Weather.warmthNeed(world) * Shelter.nightInsulation(world),
        1e-9,
        "the thermostat's figure (power.lua)"
      )
      T.near(
        Weather.expectedWarmthNeed(world, "winter", world.state.calendar.day - 3 * DPS),
        forecast,
        1e-9,
        "the forecast stays blind to a front: it is a forecast miss"
      )
      local burned
      world.events:on("needs.warmed", function(e)
        burned = e
      end)
      Ledger.add(world, "wood", 100)
      place(world, "campfire")
      Needs.warm(world)
      T.near(burned.needed, need, 1e-9, "the draw burns for the same need")
    end)
  end
)

T.test("cold front: the readiness forecast counts the front only for tonight", function()
  frontOnly(function()
    local world = duskWorld(4, AUTUMN + 2)
    local without = Readiness.winter(world)
    T.truthy(without, "winter readiness is due in autumn")
    NightThreats.plan(world)
    local extra = Readiness.winter(world).fuel.need - without.fuel.need
    T.truthy(extra > 0, "tonight's extra need is in the warmth still to find")
    T.truthy(extra < Needs.warmthNeeded(world), "but only tonight's extra: later nights are the forecast's")
  end)
end)

T.test("cold front: never past the mercy ceiling, never on a cold-snap night, never before its first day", function()
  frontOnly(function()
    with({ { tun.events.mercy, "maxWarmthMultiplier", 1.1 } }, function()
      local world = duskWorld(3, AUTUMN + 4)
      NightThreats.plan(world)
      T.near(Weather.frontFactor(world), 1.1, 1e-9, "the ceiling caps the factor")
    end)
    with({ { tun.events.mercy, "maxWarmthMultiplier", 0.5 } }, function()
      local world = duskWorld(3, AUTUMN + 4)
      NightThreats.plan(world)
      T.eq(Weather.frontFactor(world), 1, "a night already past the ceiling takes no more")
    end)
    local snap = duskWorld(3, WINTER + 4)
    snap.state.weather.winters[1] = { severity = 1, snapStart = 1, snapDays = 7 }
    T.eq(Weather.isColdSnap(snap), true)
    NightThreats.plan(snap)
    T.eq(NightThreats.tonight(snap), nil, "a cold snap is hard enough")
    local early = duskWorld(3, FRONT.firstDay - 1)
    early.state.calendar.day = FRONT.firstDay - 1
    NightThreats.plan(early)
    T.eq(NightThreats.tonight(early), nil)
    local summer = duskWorld(3, DPS + 3)
    NightThreats.plan(summer)
    T.eq(NightThreats.tonight(summer), nil, "no front in summer")
  end)
end)

T.test("cold front: the night's roll is drawn the dusk before and kept, so weather sense can read it", function()
  local meta = { journal = { notes = {}, counts = {}, known = { weather_sense = true }, queue = {}, progress = {} } }
  frontOnly(function()
    -- Dusk of day 17 draws the roll for the night of day 18.
    local world = duskWorld(6, AUTUMN + 2, 19.25, meta)
    NightThreats.plan(world)
    local roll = world.state.weather.frontRoll
    T.eq(roll.day, world.state.calendar.day + 1)
    -- A day later, before dusk: the roll is known, the front is not yet drawn.
    Needs.warm(world) -- the midnight draw has used the earlier front
    setTime(world, roll.day, 10)
    T.eq(Weather.frontTonight(world), false)
    local scale = NightThreats.scale(world, reg:get("night_threats", "cold_front"))
    T.eq(Weather.frontForecast(world, scale), true, "weather sense: on the forecast all day")
    local risks = Readiness.tonight(world).risks
    T.eq(risks[#risks].id, "front")
    -- Without weather sense there is no forecast, only the dusk sign.
    local blind = duskWorld(6, AUTUMN + 2)
    NightThreats.plan(blind)
    setTime(blind, blind.state.weather.frontRoll.day, 10)
    T.eq(Weather.frontForecast(blind, 1), false)
    -- The kept roll is the one the next dusk uses: the front comes exactly when it was forecast.
    setTime(world, roll.day, 19.25)
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world).id, "cold_front")
  end)
  with({ { FRONT.chance, "autumn", 0 } }, function()
    local world = duskWorld(6, AUTUMN + 2, 19.25, meta)
    NightThreats.plan(world)
    setTime(world, world.state.weather.frontRoll.day, 10)
    T.eq(Weather.frontForecast(world, 1), false, "no chance, no forecast")
  end)
end)

T.test("cold front: slipped Footing and the post-bad cooldown scale the chance down (mercy)", function()
  local world = duskWorld(3, AUTUMN + 4)
  local d = reg:get("night_threats", "cold_front")
  local normal = NightThreats.scale(world, d)
  T.eq(normal, 1, "no exposure effect: weather is attracted by nothing")
  world.state.footing.held = false
  world.state.footing.slipped = true
  local slipped = NightThreats.scale(world, d)
  T.truthy(slipped < normal, "slipped Footing scales a threat down")
end)

-- The pipe freeze ----------------------------------------------------------------------------------------

--- A winter dusk with a cistern placed (something to freeze), no shelter better than the truck.
local function pipeWorld(seed, meta)
  local world = duskWorld(seed, WINTER + 2, 17.5, meta)
  place(world, "cistern")
  return world
end

T.test("pipe freeze: planned at dusk with a sign, it freezes the pipes at 23:00 until noon", function()
  pipesOnly(function()
    local world = pipeWorld(3)
    T.eq(Weather.pipesGuarded(world), false, "a truck and no lagging")
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world).id, "pipe_freeze")
    T.truthy(NightThreats.sign(world).line:find("pipes"))
    T.eq(Weather.pipesFrozen(world), false, "not yet")
    T.truthy(landAt(world, PIPES.hour + 0.25))
    T.eq(NightThreats.history(world)[1].outcome, "landed")
    T.eq(Weather.pipesFrozen(world), true)
    local day = world.state.calendar.day
    setTime(world, day + 1, PIPES.thawHour - 0.5)
    T.eq(Weather.pipesFrozen(world), true, "frozen into the morning")
    setTime(world, day + 1, PIPES.thawHour + 0.5)
    T.eq(Weather.pipesFrozen(world), false, "thawed by the sun at noon")
  end)
end)

T.test("pipe freeze: nothing to freeze, nothing planned; and only in winter", function()
  pipesOnly(function()
    local bare = duskWorld(3, WINTER + 2, 17.5)
    NightThreats.plan(bare)
    T.eq(NightThreats.tonight(bare), nil, "no well, pump or cistern")
    local autumn = duskWorld(3, AUTUMN + 3)
    place(autumn, "cistern")
    NightThreats.plan(autumn)
    T.eq(NightThreats.tonight(autumn), nil, "not in autumn")
  end)
end)

T.test(
  "pipe freeze: a shack, a shelter of the tuned rank, or pipe lagging stops it, and the night is reported turned",
  function()
    pipesOnly(function()
      local lagged = pipeWorld(3)
      Inventory.addEquipment(lagged, "pipe_lagging")
      T.eq(Weather.pipesGuarded(lagged), true)
      NightThreats.plan(lagged)
      T.eq(NightThreats.tonight(lagged).id, "pipe_freeze", "a guarded night is still signed")
      landAt(lagged, PIPES.hour + 0.25)
      T.eq(NightThreats.history(lagged)[1].outcome, "turned")
      T.eq(Weather.pipesFrozen(lagged), false)

      local sheltered = pipeWorld(3)
      T.eq(Shelter.id(sheltered), "truck")
      with({ { PIPES, "shelterRank", 0 } }, function()
        T.eq(Weather.pipesGuarded(sheltered), true, "the truck is rank 0")
      end)
      local camp = pipeWorld(3)
      place(camp, "camp")
      T.eq(Weather.pipesGuarded(camp), false, "a camp is under the shack's rank")
      place(camp, "shack")
      T.eq(Weather.pipesGuarded(camp), true, "a shack keeps the pipes")
    end)
  end
)

T.test("pipe freeze: frozen pipes idle the pumps and refuse a bucket at the cistern; the creek stays open", function()
  pipesOnly(function()
    local world = pipeWorld(3)
    local pump = place(world, "dc_pump")
    NightThreats.plan(world)
    landAt(world, PIPES.hour + 0.25)
    T.eq(Water.pumpState(world, pump), "frozen")
    setTime(world, world.state.calendar.day + 1, PIPES.thawHour + 0.5)
    T.truthy(Water.pumpState(world, pump) ~= "frozen", "the sun thaws it")
  end)
end)

T.test(
  "pipe freeze: the morning drink thaws the line with a little wood, and only when the canteen cannot cover the day",
  function()
    pipesOnly(function()
      local world = pipeWorld(3)
      NightThreats.plan(world)
      landAt(world, PIPES.hour + 0.25)
      Ledger.add(world, "water", 30)
      Ledger.add(world, "wood", 20)
      local wood = Ledger.get(world, "wood")
      world.state.needs.canteen = 0
      local thawed
      world.events:on("needs.thawed", function(e)
        thawed = e
      end)
      local shortfall = Needs.drink(world)
      T.eq(shortfall, 0, "the day is drunk")
      T.eq(thawed.wood, PIPES.thawWood)
      T.eq(Ledger.get(world, "wood"), wood - PIPES.thawWood)
      T.eq(Weather.pipesFrozen(world), false, "the line is thawed")
      T.near(Ledger.get(world, "water"), 30 - Needs.waterNeeded(world), 1e-9, "from the cistern, as ever")
    end)
  end
)

T.test("pipe freeze: a full canteen covers the day and burns no wood; the cistern stock is never lost", function()
  pipesOnly(function()
    local world = pipeWorld(3)
    NightThreats.plan(world)
    landAt(world, PIPES.hour + 0.25)
    Ledger.add(world, "water", 30)
    Ledger.add(world, "wood", 20)
    local wood = Ledger.get(world, "wood")
    world.state.needs.canteen = Needs.waterNeeded(world) + 1
    T.eq(Needs.drink(world), 0)
    T.eq(Ledger.get(world, "wood"), wood, "no wood burned")
    T.eq(Ledger.get(world, "water"), 30, "the stock is untouched behind the frozen pipe")
    T.eq(Weather.pipesFrozen(world), true, "left for the sun")
  end)
end)

T.test(
  "pipe freeze: no wood to spare means no thaw; the day is the canteen's, and a dry day is only ever one thirsty day",
  function()
    pipesOnly(function()
      local world = pipeWorld(3)
      place(world, "campfire")
      NightThreats.plan(world)
      landAt(world, PIPES.hour + 0.25)
      Ledger.add(world, "water", 30)
      world.state.needs.canteen = 0
      -- Exactly tonight's fire and one wood short of the thaw: the thaw must not take the fire's wood.
      local night = Needs.woodOutlook(world).perNight
      T.truthy(night > 0, "a fire is needed tonight")
      Ledger.remove(world, "wood", Ledger.get(world, "wood"))
      Ledger.add(world, "wood", night + PIPES.thawWood - 1)
      local before = Needs.condition(world)
      local shortfall = Needs.drink(world)
      T.eq(Ledger.get(world, "wood"), night + PIPES.thawWood - 1, "no wood burned")
      T.truthy(shortfall > 0, "the cistern is out of reach and the canteen is empty")
      T.truthy(Needs.condition(world) < before, "a thirsty day costs Condition, as ever")
      T.truthy(Needs.thirstDays(world) == 1, "one dry day")
      T.eq(Ledger.get(world, "water"), 30, "the stock is untouched")
    end)
  end
)

T.test("pipe freeze: the mercy scales apply, so a slipped homestead is spared more nights", function()
  local world = pipeWorld(3)
  local d = reg:get("night_threats", "pipe_freeze")
  local normal = NightThreats.scale(world, d)
  world.state.footing.held = false
  world.state.footing.slipped = true
  T.truthy(NightThreats.scale(world, d) < normal)
end)

-- State -------------------------------------------------------------------------------------------------

T.test("weather nights: the front and the frozen pipes survive a save round trip", function()
  pipesOnly(function()
    local world = pipeWorld(3)
    NightThreats.plan(world)
    landAt(world, PIPES.hour + 0.25)
    local again = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
    T.eq(Weather.pipesFrozen(again), true)
  end)
  frontOnly(function()
    local world = duskWorld(3, AUTUMN + 4)
    NightThreats.plan(world)
    local again = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
    T.eq(Weather.frontTonight(again), true)
    T.near(Needs.warmthNeeded(again), Needs.warmthNeeded(world), 1e-9)
  end)
end)

T.test("weather nights: a seed gives the same nights twice, and the weather streams move no other stream", function()
  local function nights(seed)
    local log = {}
    with({ { FRONT.chance, "autumn", 0.5 }, { FRONT.chance, "winter", 0.5 }, { PIPES, "chance", 0.5 } }, function()
      local world = newWorld(seed)
      place(world, "cistern")
      for day = AUTUMN, WINTER + DPS - 1 do
        setTime(world, day, 19.25)
        world.state.nightthreats.planDay = 0
        NightThreats.plan(world)
        local t = NightThreats.tonight(world)
        log[#log + 1] = t and t.id or "-"
        world.state.events.slot = nil
      end
    end)
    return table.concat(log, ",")
  end
  T.eq(nights(9), nights(9))
  T.truthy(nights(9):find("cold_front"), "this seed sees a front")
end)

T.test("weather nights: power draw of the heater thermostat stays at the shared warmth figure", function()
  frontOnly(function()
    local world = duskWorld(3, AUTUMN + 4)
    NightThreats.plan(world)
    T.near(Needs.warmthNeeded(world), Weather.warmthNeed(world) * Shelter.nightInsulation(world), 1e-9)
    T.truthy(Power.heatPerNight(world, "autumn") >= 0)
  end)
end)
