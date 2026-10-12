-- Power network (GDD §7.5, §7.6): sources, batteries, sinks, priorities, the truck as a battery.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Spoilage = require("src.sim.systems.spoilage")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24
local TICK_HOURS = STEP / HOUR

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
  end
end

--- Jump the clock to `hour` on day `day` (1-based) without ticking systems.
local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

-- Seasons are 7 days: spring 1-7, summer 8-14, autumn 15-21, winter 22-28.
local SPRING, SUMMER, WINTER = 1, 8, 22

--- Place an object on the free tile nearest the spawn. Returns its anchor.
local function place(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

--- Remove the starting folding panel so tests control the generation.
local function clearPanels(world)
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "folding_panel" then
      Grid.removeObject(world, anchor)
    end
  end
end

--- Change numbers inside content for one test, then put them back (content tables are shared).
local function with(changes, fn)
  local saved = {}
  for _, c in ipairs(changes) do
    saved[#saved + 1] = { c[1], c[2], c[1][c[2]] }
    c[1][c[2]] = c[3]
  end
  local ok, err = pcall(fn)
  for _, s in ipairs(saved) do
    s[1][s[2]] = s[3]
  end
  if not ok then
    error(err, 0)
  end
end

local function sink(id)
  return reg:get("objects", id).sink
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

-- Content ---------------------------------------------------------------------------------

T.test("power content: sinks and sources are well formed and have art", function()
  local sprites = require("assets.manifest").sprites
  local tiers = {}
  for _, id in ipairs(tun.power.defaultOrder) do
    tiers[id] = true
  end
  local curves = { solar = true, wind = true, hydro = true, fuel = true }
  local schedules = { always = true, dark = true, heat = true, fill = true }
  for _, def in ipairs(reg:all("objects")) do
    if def.sink then
      T.truthy(tiers[def.sink.tier], def.id .. ": sink tier is in tuning.power.defaultOrder")
      T.truthy(def.sink.draw > 0, def.id .. ": sink draw")
      T.truthy(schedules[def.sink.schedule], def.id .. ": sink schedule")
    end
    if def.source then
      T.truthy(curves[def.source.curve], def.id .. ": source curve")
      T.truthy(def.source.peak > 0, def.id .. ": source peak")
      if def.source.curve ~= "fuel" and def.source.curve ~= "solar" then
        for _, season in ipairs(tun.time.seasons) do
          T.truthy(tun.power.curves[def.source.curve][season], def.id .. ": curve for " .. season)
        end
      else
        T.eq(def.source.curve == "fuel", def.source.fuel ~= nil, def.id .. ": only fuel sources name a fuel")
      end
    end
    if def.sink or def.source or def.battery then
      T.truthy(sprites[def.id] or def.id == "truck", def.id .. " has a sprite")
    end
  end
  T.eq(sprites.icon_fuel ~= nil, true)
  local names = {}
  for _, id in ipairs(tun.power.defaultOrder) do
    names[#names + 1] = tun.power.tierNames[id]
  end
  T.eq(#names, #tun.power.defaultOrder)
end)

T.test("power content: the catalog offers every network object", function()
  for _, id in ipairs({ "solar_array", "battery_bank", "wind_turbine", "micro_hydro", "generator", "electric_heater", "lamp", "chest_freezer" }) do
    T.eq(reg:get("catalog", id).object, id)
    T.truthy(reg:get("catalog", id).price > 0)
  end
  T.eq(reg:get("catalog", "fuel_can").gives.fuel, 5)
  T.truthy(tun.power.truckReserveKwh > tun.economy.tripCost, "the truck keeps enough for a trip")
end)

-- Network math ------------------------------------------------------------------------------

T.test("power: with nothing on the network satisfaction is full and nothing is wasted twice", function()
  local world = newWorld()
  run(world, 1)
  T.eq(Power.satisfaction(world), 1)
  T.eq(#Power.sinkList(world), 0)
  T.eq(Power.tierRatio(world, "heating"), 1)
end)

T.test("power: spare solar charges the home bank before the truck, with charging losses", function()
  local world = newWorld()
  local bank = place(world, "battery_bank")
  local truck = Land.truck(world)
  setTime(world, SPRING, 11)
  local fed = 0
  for _ = 1, 100 do
    world:tick(STEP)
    fed = fed + Power.flow(world).charging * TICK_HOURS
  end
  T.truthy(fed > 0)
  T.near(Power.charge(world, bank), fed * reg:get("objects", "battery_bank").efficiency, 1e-9)
  T.eq(Power.charge(world, truck), 0, "bank tier outranks the truck tier")
end)

T.test("power: a battery stops charging when full and the rest is wasted", function()
  local world = newWorld()
  local bank = place(world, "battery_bank")
  Power.add(world, bank, 100)
  T.eq(Power.charge(world, bank), reg:get("objects", "battery_bank").battery)
  setTime(world, SPRING, 11)
  world:tick(STEP)
  T.truthy(Power.flow(world).wasted > 0 or Power.charge(world, Land.truck(world)) > 0)
  T.eq(Power.charge(world, bank), 20)
end)

T.test("power: a charge-rate limit caps a battery's intake", function()
  with({ { reg:get("objects", "truck"), "maxRate", 1 } }, function()
    local world = newWorld()
    clearPanels(world)
    place(world, "solar_array")
    local truck = Land.truck(world)
    setTime(world, SPRING, 12)
    world:tick(STEP)
    T.truthy(Power.flow(world).generation > 1, "enough sun to exceed the charger")
    T.near(Power.charge(world, truck), 1 * TICK_HOURS, 1e-9)
    T.truthy(Power.flow(world).wasted > 1)
  end)
end)

T.test("power: a sink is served from the bank at night and drains it exactly", function()
  local world = newWorld()
  local bank = place(world, "battery_bank")
  place(world, "chest_freezer")
  Power.add(world, bank, 5)
  local start = Power.charge(world, bank)
  setTime(world, SPRING, 2)
  world:tick(STEP)
  T.near(start - Power.charge(world, bank), sink("chest_freezer").draw * TICK_HOURS, 1e-9)
  T.eq(Power.satisfaction(world), 1)
  T.near(Power.flow(world).discharging, sink("chest_freezer").draw, 1e-9)
end)

T.test("power: when supply is short the higher tier is served and the lower is shed", function()
  with({
    { sink("chest_freezer"), "draw", 0.5 },
    { sink("lamp"), "draw", 0.5 },
    { sink("lamp"), "schedule", "always" },
  }, function()
    local world = newWorld()
    place(world, "chest_freezer")
    local lamp = place(world, "lamp")
    local freezer = world.state.grid.objects
    local freezerAnchor
    for anchor, obj in pairs(freezer) do
      if obj.id == "chest_freezer" then
        freezerAnchor = anchor
      end
    end
    setTime(world, SPRING, 12)
    world:tick(STEP)
    local gen = Power.flow(world).generation
    T.truthy(gen > 0.5 and gen < 1, "the folding panel covers the freezer but not both")
    T.eq(Power.sinkRatio(world, freezerAnchor), 1, "freezer outranks lights")
    T.near(Power.sinkRatio(world, lamp), (gen - 0.5) / 0.5, 1e-9)
    T.near(Power.satisfaction(world), gen / 1.0, 1e-9)
    T.eq(Power.sinkState(world, lamp), "short")
    -- Reorder: lights above the freezer.
    T.truthy(Power.moveTier(world, "lights", -1))
    T.truthy(Power.moveTier(world, "lights", -1))
    world:tick(STEP)
    T.eq(Power.sinkRatio(world, lamp), 1)
    T.truthy(Power.sinkRatio(world, freezerAnchor) < 1)
    -- The order is bounded.
    local order = Power.order(world)
    T.eq(order[1], "heating")
    T.eq(order[2], "lights")
    T.falsy(Power.moveTier(world, "heating", -1))
  end)
end)

T.test("power: a sink the player switches off draws nothing", function()
  with({ { sink("chest_freezer"), "draw", 0.5 } }, function()
    local world = newWorld()
    local freezer = place(world, "chest_freezer")
    setTime(world, SPRING, 12)
    world:tick(STEP)
    T.eq(Power.sinkState(world, freezer), "ok")
    Power.setEnabled(world, freezer, false)
    world:tick(STEP)
    T.eq(Power.sinkState(world, freezer), "off")
    T.eq(Power.flow(world).demand, 0)
    Power.setEnabled(world, freezer, true)
    world:tick(STEP)
    T.eq(Power.flow(world).demand, 0.5)
  end)
end)

T.test("power: the lamp only draws in the dark", function()
  local world = newWorld()
  local lamp = place(world, "lamp")
  setTime(world, SPRING, 12)
  world:tick(STEP)
  T.eq(Power.sinkState(world, lamp), "idle")
  setTime(world, SPRING, 23)
  world:tick(STEP)
  T.truthy(Power.sinkState(world, lamp) == "ok" or Power.sinkState(world, lamp) == "short")
  T.eq(Power.flow(world).demand, sink("lamp").draw)
end)

-- The truck as a battery ------------------------------------------------------------------

T.test("power: homestead load competes with charging the truck", function()
  with({ { sink("chest_freezer"), "draw", 0.5 } }, function()
    local function truckAfter(withFreezer, truckFirst)
      local world = newWorld(3)
      if withFreezer then
        place(world, "chest_freezer")
      end
      if truckFirst then
        while Power.order(world)[1] ~= "truck" do
          for i, id in ipairs(Power.order(world)) do
            if id == "truck" then
              Power.moveTier(world, "truck", -1)
              break
            end
          end
        end
      end
      setTime(world, SPRING, 9)
      run(world, HOUR * 3)
      return Power.charge(world, Land.truck(world)), world
    end
    local alone = truckAfter(false)
    local loaded = truckAfter(true)
    local prioritised = truckAfter(true, true)
    T.truthy(alone > 0)
    T.truthy(loaded < alone, "the freezer eats charge the truck would have had")
    T.truthy(prioritised > loaded, "moving the truck up the list gives it the sun back")
    T.near(alone - loaded, 0.5 * HOUR * 3 / HOUR, 0.05, "the truck loses about the freezer's energy")
  end)
end)

T.test("power: the truck lends charge above its trip reserve and never below", function()
  with({ { sink("chest_freezer"), "draw", 2 } }, function()
    local world = newWorld()
    clearPanels(world)
    place(world, "chest_freezer")
    local truck = Land.truck(world)
    Power.add(world, truck, tun.power.truckReserveKwh + 1)
    setTime(world, SPRING, 2)
    run(world, HOUR * 2) -- 4 kWh wanted, 1 kWh lendable
    T.near(Power.charge(world, truck), tun.power.truckReserveKwh, 1e-6)
    T.truthy(Power.satisfaction(world) < 1)
    -- With lending off the truck keeps everything.
    local world2 = newWorld()
    clearPanels(world2)
    place(world2, "chest_freezer")
    Power.add(world2, Land.truck(world2), tun.power.truckReserveKwh + 10)
    Power.setTruckLends(world2, false)
    setTime(world2, SPRING, 2)
    run(world2, HOUR)
    T.eq(Power.charge(world2, Land.truck(world2)), tun.power.truckReserveKwh + 10)
    T.eq(Power.satisfaction(world2), 0)
  end)
end)

T.test("power: a truck trip still drains the truck battery", function()
  local world = newWorld()
  local truck = Land.truck(world)
  Power.add(world, truck, 30)
  T.truthy(Power.drain(world, truck, tun.economy.tripCost))
  T.eq(Power.charge(world, truck), 30 - tun.economy.tripCost)
  T.falsy(Power.drain(world, truck, 100))
end)

-- Generators ---------------------------------------------------------------------------------

T.test("power: a generator covers a shortfall and burns fuel; no fuel, no power", function()
  with({ { sink("chest_freezer"), "draw", 1 } }, function()
    local world = newWorld()
    clearPanels(world)
    place(world, "chest_freezer")
    local gen = place(world, "generator")
    local src = reg:get("objects", "generator").source
    Ledger.add(world, "fuel", 3)
    setTime(world, SPRING, 2)
    run(world, HOUR * 2) -- 2 kWh needed
    T.eq(Power.satisfaction(world), 1)
    local burned = 3 - Ledger.get(world, "fuel") - world.state.power.tank -- fuel units used so far (the tank holds the part-burned unit)
    T.near(burned, 2 * src.fuelPerKwh, 0.05)
    -- Out of fuel:
    Ledger.remove(world, "fuel", Ledger.get(world, "fuel"))
    world.state.power.tank = 0
    world:tick(STEP)
    T.eq(Power.satisfaction(world), 0)
    -- Fuel but switched off:
    Ledger.add(world, "fuel", 3)
    Power.setEnabled(world, gen, false)
    world:tick(STEP)
    T.eq(Power.satisfaction(world), 0)
    Power.setEnabled(world, gen, true)
    world:tick(STEP)
    T.eq(Power.satisfaction(world), 1)
    T.near(Power.output(world), 1, 1e-9)
  end)
end)

T.test("power: batteries are used before the generator", function()
  with({ { sink("chest_freezer"), "draw", 1 } }, function()
    local world = newWorld()
    clearPanels(world)
    local bank = place(world, "battery_bank")
    place(world, "chest_freezer")
    place(world, "generator")
    Ledger.add(world, "fuel", 5)
    Power.add(world, bank, 10)
    setTime(world, SPRING, 2)
    run(world, HOUR)
    T.eq(Ledger.get(world, "fuel"), 5)
    T.near(Power.charge(world, bank), 9, 0.01)
  end)
end)

-- Wind, hydro, weather hooks -------------------------------------------------------------------

T.test("power: wind output follows the season and is deterministic from the seed", function()
  local function averageWind(seed, day)
    local world = newWorld(seed)
    clearPanels(world)
    place(world, "wind_turbine")
    setTime(world, day, 0)
    local total, ticks = 0, 0
    for _ = 1, math.floor(HOUR * 24 * 2 / STEP) do
      world:tick(STEP)
      total = total + Power.output(world)
      ticks = ticks + 1
    end
    return total / ticks
  end
  local winter = averageWind(5, WINTER)
  local summer = averageWind(5, SUMMER)
  T.truthy(winter > summer, "wind is strongest in winter")
  T.truthy(winter > 0 and winter <= reg:get("objects", "wind_turbine").source.peak)
  T.eq(averageWind(5, WINTER), winter, "same seed, same wind")
  T.truthy(averageWind(6, WINTER) ~= winter, "another seed blows differently")
end)

T.test("power: micro-hydro needs the creek beside it and runs day and night", function()
  local world = newWorld()
  local grid = world.state.grid
  local near, far
  for i = 1, #grid.terrain do
    if Inventory.canPlace(world, "micro_hydro", i) then
      near = near or i
    elseif Inventory.canPlace(world, "lamp", i) then
      far = far or i
    end
  end
  T.truthy(near, "a creek-side spot exists")
  T.truthy(far, "and most spots are not beside the creek")
  clearPanels(world)
  Inventory.addObject(world, "micro_hydro")
  T.truthy(Inventory.place(world, "micro_hydro", near))
  setTime(world, SPRING, 2)
  world:tick(STEP)
  T.near(Power.output(world), reg:get("objects", "micro_hydro").source.peak * tun.power.curves.hydro.spring, 1e-9)
end)

T.test("power: today's weather scales generation (D51)", function()
  local world = newWorld()
  setTime(world, SPRING, 12)
  world.state.weather.sky.days[1] = "clear"
  world:tick(STEP)
  local clear = Power.output(world)
  world.state.weather.sky.days[1] = "cloudy"
  world:tick(STEP)
  local cloudy = Power.output(world)
  T.near(cloudy, clear * (1 - tun.weather.kinds.cloudy.cloud), clear * 0.01)
end)

-- The winter squeeze --------------------------------------------------------------------------

local function dayBalance(day)
  -- One full day with an array, a bank, a heater, a freezer and a lamp: energy made vs wanted.
  local world = newWorld(4)
  clearPanels(world)
  place(world, "solar_array")
  place(world, "battery_bank")
  place(world, "electric_heater")
  place(world, "chest_freezer")
  place(world, "lamp")
  setTime(world, day, 6)
  local made, wanted, served = 0, 0, 0
  for _ = 1, math.floor(HOUR * 24 / STEP) do
    world:tick(STEP)
    local f = Power.flow(world)
    made = made + f.generation * TICK_HOURS
    wanted = wanted + f.demand * TICK_HOURS
    served = served + f.served * TICK_HOURS
  end
  return made, wanted, served
end

T.test("power: winter squeeze - short sun and a heater outrun an array, summer does not", function()
  local summerMade, summerWanted, summerServed = dayBalance(SUMMER)
  local winterMade, winterWanted, winterServed = dayBalance(WINTER)
  T.truthy(summerMade > summerWanted, "summer: plenty")
  T.near(summerServed, summerWanted, 1e-6, "summer: everything served")
  T.truthy(winterWanted > summerWanted * 3, "winter: heating and long nights multiply the load")
  T.truthy(winterMade < winterWanted, "winter: the array cannot keep up")
  T.truthy(winterServed < winterWanted, "winter: something is shed")
  T.truthy(winterMade < summerMade * 0.6, "winter: far less sun")
end)

T.test("power: shedding follows the priority list, so heating beats the freezer in winter", function()
  local world = newWorld(4)
  clearPanels(world)
  local heater = place(world, "electric_heater")
  local freezer = place(world, "chest_freezer")
  local solar = place(world, "folding_panel")
  setTime(world, WINTER, 18) -- dark, cold, and the panel makes nothing
  place(world, "battery_bank")
  local bank
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "battery_bank" then
      bank = anchor
    end
  end
  Power.add(world, bank, 0.5) -- almost nothing stored
  local brownouts = collect(world, "power.brownout")
  run(world, HOUR * 2)
  T.truthy(solar ~= nil)
  T.eq(Power.sinkState(world, heater), "short")
  T.truthy(Power.tierRatio(world, "heating") <= 1)
  T.truthy(#brownouts >= 1 and brownouts[1].tier, "a brownout is announced")
  local perDay = {}
  for _, e in ipairs(brownouts) do
    perDay[e.tier] = (perDay[e.tier] or 0) + 1
  end
  for tier, n in pairs(perDay) do
    T.eq(n, 1, tier .. ": announced once a day")
  end
  T.truthy(Power.sinkRatio(world, freezer) <= Power.sinkRatio(world, heater) + 1e-9, "the freezer is shed first")
end)

-- Effects: heat, study, spoilage ---------------------------------------------------------------

T.test("power: an electric heater makes warmth that replaces firewood", function()
  local world = newWorld(4)
  local bank = place(world, "battery_bank")
  place(world, "electric_heater")
  Power.add(world, bank, 20)
  setTime(world, WINTER, 18)
  Ledger.add(world, "seasoned_firewood", 10)
  local need = Needs.warmthNeeded(world)
  T.truthy(need > 0)
  run(world, HOUR * 5) -- stay before midnight, when the night is accounted
  local warmthMade = world.state.power.warmth
  local expected = sink("electric_heater").draw * sink("electric_heater").effects.warmthPerKwh * 5
  T.near(warmthMade, expected, expected * 0.02, "warmth follows the energy delivered")
  local warmed = collect(world, "needs.warmed")
  local before = Ledger.get(world, "seasoned_firewood")
  Needs.warm(world)
  T.near(warmed[1].electric, math.min(warmthMade, need), 1e-9)
  T.eq(before - Ledger.get(world, "seasoned_firewood"), math.ceil(need - warmthMade), "the heater saves wood")
  T.truthy(math.ceil(need - warmthMade) < math.ceil(need))
  T.eq(world.state.power.warmth, 0, "the warmth was taken")
end)

T.test("power: the heater's thermostat stops once the night's warmth is made", function()
  with({ { sink("electric_heater").effects, "warmthPerKwh", 1 } }, function()
    local world = newWorld(4)
    local bank = place(world, "battery_bank")
    local heater = place(world, "electric_heater")
    Power.add(world, bank, 20)
    setTime(world, WINTER, 18)
    local need = Needs.warmthNeeded(world)
    run(world, HOUR * 12)
    T.truthy(world.state.power.warmth >= need - 0.01 and world.state.power.warmth < need + 0.05)
    T.eq(Power.sinkState(world, heater), "idle")
    T.eq(Needs.warm(world), 0, "no cold, no wood")
  end)
end)

T.test("power: the heater idles in summer and without a night's need", function()
  local world = newWorld(4)
  local heater = place(world, "electric_heater")
  setTime(world, SUMMER, 23)
  world:tick(STEP)
  T.eq(Power.sinkState(world, heater), "idle")
  T.eq(world.state.power.warmth, 0)
end)

T.test("power: a powered lamp speeds study and a powered freezer slows spoilage", function()
  local world = newWorld(4)
  local bank = place(world, "battery_bank")
  place(world, "lamp")
  place(world, "chest_freezer")
  Power.add(world, bank, 20)
  setTime(world, SPRING, 23)
  run(world, HOUR * 4) -- past midnight, the lamp still on, the freezer partly cooled
  T.near(Power.effect(world, "studySpeed"), sink("lamp").effects.studySpeed, 1e-6)
  T.truthy(Power.effect(world, "spoilSlow") > 0)
  T.truthy(Power.effect(world, "spoilSlow") <= sink("chest_freezer").effects.spoilSlow)
  T.eq(Power.effect(world, "nothing"), 0)
  -- Spoilage: a big stock of fresh radishes, with and without the freezer's effect.
  local function spoiled(freezerEffect)
    local w = newWorld(9)
    w.state.power.flow.effects.spoilSlow = freezerEffect
    Ledger.add(w, "radish", 20)
    local before = Ledger.get(w, "radish")
    Spoilage.daily(w)
    return before - Ledger.get(w, "radish")
  end
  T.truthy(spoiled(0) > spoiled(3), "the freezer saves food")
end)

-- Save / load / determinism -------------------------------------------------------------------

local function buildNetwork(seed)
  local world = newWorld(seed)
  clearPanels(world)
  place(world, "solar_array")
  place(world, "wind_turbine")
  local bank = place(world, "battery_bank")
  place(world, "chest_freezer")
  place(world, "lamp")
  place(world, "electric_heater")
  place(world, "generator")
  Ledger.add(world, "fuel", 5)
  Power.add(world, bank, 4)
  setTime(world, WINTER, 14)
  return world
end

T.test("power: same seed and inputs give identical networks", function()
  local a, b = buildNetwork(7), buildNetwork(7)
  run(a, HOUR * 30)
  run(b, HOUR * 30)
  T.eq(serialize.encode(a.state.power), serialize.encode(b.state.power))
  T.eq(serialize.encode(a.state.ledger), serialize.encode(b.state.ledger))
end)

T.test("power: the network survives a save and load mid-run", function()
  local a = buildNetwork(7)
  run(a, HOUR * 9)
  local copy = serialize.decode(serialize.encode(a.state))
  local b = World.new({ registry = reg, tuning = tun }, copy)
  run(a, HOUR * 9)
  run(b, HOUR * 9)
  T.eq(serialize.encode(a.state.power), serialize.encode(b.state.power))
  T.eq(Power.satisfaction(a), Power.satisfaction(b))
end)

T.test("power: player settings are saved", function()
  local a = buildNetwork(7)
  local freezer
  for anchor, obj in pairs(a.state.grid.objects) do
    if obj.id == "chest_freezer" then
      freezer = anchor
    end
  end
  Power.setEnabled(a, freezer, false)
  Power.setTruckLends(a, false)
  Power.moveTier(a, "truck", -1)
  local b = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(a.state)))
  T.falsy(Power.isEnabled(b, freezer))
  T.falsy(Power.truckLends(b))
  T.eq(Power.order(b)[6], "truck")
end)

T.test("power: a save from before the network existed still loads", function()
  local a = newWorld(2)
  local truck = Land.truck(a)
  Power.add(a, truck, 12)
  local state = serialize.decode(serialize.encode(a.state))
  state.power = { charge = { [truck] = 12 } } -- the old shape: charges only
  local b = World.new({ registry = reg, tuning = tun }, state)
  T.eq(Power.charge(b, truck), 12)
  T.eq(Power.truckLends(b), true)
  T.eq(#Power.order(b), #tun.power.defaultOrder)
  run(b, 1)
  T.eq(Power.satisfaction(b), 1)
end)

T.test("power: a saved order missing a newer tier gets it appended; unknown tiers are dropped", function()
  local a = newWorld(2)
  local state = serialize.decode(serialize.encode(a.state))
  state.power.order = { "freezer", "lights", "ghost" }
  local b = World.new({ registry = reg, tuning = tun }, state)
  local order = Power.order(b)
  T.eq(order[1], "freezer")
  T.eq(order[2], "lights")
  T.eq(#order, #tun.power.defaultOrder)
  for _, id in ipairs(order) do
    T.truthy(id ~= "ghost")
  end
end)

T.test("power: batteries announce when full, once", function()
  local world = newWorld()
  local bank = place(world, "battery_bank")
  local full = collect(world, "power.full")
  Power.add(world, bank, 100)
  setTime(world, SPRING, 12)
  run(world, 1)
  T.eq(#full, 1)
  T.eq(full[1].battery, bank)
  run(world, 1)
  T.eq(#full, 1)
end)
