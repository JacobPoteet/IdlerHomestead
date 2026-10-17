-- The daily drinking-water need (GDD §4.2, D160, #95): the cistern stock first, then a canteen filled by hand
-- at the creek or a well, snow melted by a fire in winter; a dry day builds Thirst slowly.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Alerts = require("src.sim.systems.alerts")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Run = require("src.meta.run")
local Tasks = require("src.sim.systems.tasks")
local ChipText = require("src.ui.chip_text")
local NightText = require("src.ui.night_text")
local AlertText = require("src.ui.alert_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.needs

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
  end
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function dayIn(season)
  for n, s in ipairs(tun.time.seasons) do
    if s == season then
      return (n - 1) * tun.time.daysPerSeason + 2
    end
  end
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

--- Empty the canteen without touching the rest.
local function emptyCanteen(world)
  world.state.needs.canteen = 0
end

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
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

-- The need and the outlook -------------------------------------------------------------------------

T.test("drinking: a new run starts with a full canteen and the saved shape is untouched", function()
  local world = newWorld(1)
  local o = Needs.waterOutlook(world)
  T.eq(o.canteen, cfg.canteenCapacity)
  T.eq(o.perDay, cfg.dailyWater)
  T.eq(Needs.waterNeeded(world), cfg.dailyWater)
  T.near(o.days, cfg.canteenCapacity / cfg.dailyWater, 1e-9)
  T.eq(o.thirstDays, 0)
  T.eq(world.state.needs.canteen, nil, "nothing is saved until the canteen first changes")
  T.eq(world.state.needs.thirstDays, nil)
end)

T.test("drinking: the cistern stock is drunk first, the canteen only for the rest", function()
  local world = newWorld(1)
  Ledger.setCapacity(world, "water", 60)
  Ledger.add(world, "water", 10)
  local drank = collect(world, "needs.drank")
  T.eq(Needs.drink(world), 0)
  T.near(Ledger.get(world, "water"), 10 - cfg.dailyWater, 1e-9)
  T.eq(Needs.canteen(world), cfg.canteenCapacity, "the canteen is untouched while the cistern covers the day")
  T.near(drank[1].water, cfg.dailyWater, 1e-9)
  -- A cistern with only half a day left: the canteen makes up the rest.
  Ledger.remove(world, "water", Ledger.get(world, "water"))
  Ledger.add(world, "water", cfg.dailyWater / 2)
  T.eq(Needs.drink(world), 0)
  T.eq(Ledger.get(world, "water"), 0)
  T.near(Needs.canteen(world), cfg.canteenCapacity - cfg.dailyWater / 2, 1e-9)
end)

T.test("drinking: with no cistern the canteen is the whole supply", function()
  local world = newWorld(1)
  for _ = 1, cfg.canteenCapacity / cfg.dailyWater do
    T.eq(Needs.drink(world), 0)
  end
  T.eq(Needs.canteen(world), 0)
  T.near(Needs.waterOutlook(world).days, 0, 1e-9)
end)

-- Thirst ---------------------------------------------------------------------------------------------

T.test("thirst: a dry day hurts, a run of dry days hurts more, and never all at once", function()
  local world = newWorld(1)
  emptyCanteen(world)
  local start = world.state.needs.condition
  local drank = collect(world, "needs.drank")
  T.eq(Needs.drink(world), 1)
  T.near(start - world.state.needs.condition, cfg.thirstDamage, 1e-9)
  T.eq(Needs.thirstDays(world), 1)
  T.truthy(cfg.thirstDamage < cfg.conditionMax, "one dry day cannot be the end")
  local before = world.state.needs.condition
  Needs.drink(world)
  T.near(before - world.state.needs.condition, cfg.thirstDamage * (1 + cfg.thirstBuild), 1e-9, "day two hurts more")
  for _ = 1, 10 do
    Needs.drink(world)
  end
  -- The build-up stops at thirstBuildDays.
  local capped = cfg.thirstDamage * (1 + cfg.thirstBuild * cfg.thirstBuildDays)
  T.near(drank[#drank].damage, capped, 1e-9, "damage stops growing")
  T.truthy(Needs.thirstDays(world) > cfg.thirstBuildDays)
end)

T.test("thirst: a partial drink scales the damage, and drinking again clears the run", function()
  local world = newWorld(1)
  world.state.needs.canteen = cfg.dailyWater / 2
  local start = world.state.needs.condition
  T.near(Needs.drink(world), 0.5, 1e-9)
  T.near(start - world.state.needs.condition, cfg.thirstDamage * 0.5, 1e-9)
  T.eq(Needs.thirstDays(world), 1)
  Needs.fillCanteen(world, cfg.canteenCapacity)
  T.eq(Needs.drink(world), 0)
  T.eq(Needs.thirstDays(world), 0)
  T.eq(world.state.needs.thirstDays, nil)
end)

T.test("thirst: a thirsty day restores no condition, a watered, fed, warm one does", function()
  local world = newWorld(1)
  setTime(world, dayIn("summer"), 12) -- no warmth needed
  Ledger.add(world, "canned_food", 20)
  world.state.needs.condition = 50
  Needs.daily(world)
  T.near(world.state.needs.condition, 50 + cfg.dailyRecovery, 1e-9, "fed, watered and warm")
  emptyCanteen(world)
  world.state.needs.condition = 50
  Needs.daily(world)
  T.truthy(world.state.needs.condition < 50, "thirst cost condition and recovery was withheld")
end)

T.test("thirst: running out ends the run with a thirst cause, and the rescue says so", function()
  local world = newWorld(1)
  emptyCanteen(world)
  Ledger.add(world, "canned_food", 20)
  setTime(world, dayIn("summer"), 12)
  world.state.needs.condition = 5
  local depleted = collect(world, "needs.depleted")
  Needs.daily(world)
  T.eq(#depleted, 1)
  T.truthy(depleted[1].thirst > 0 and depleted[1].hunger == 0 and depleted[1].cold == 0)
  local cause = Run.cause(tun, depleted[1])
  T.eq(cause.kind, "thirst")
  local text = Run.failureText(reg, tun, cause)
  T.eq(text.line, tun.ui.failure.thirst)
  T.eq(text.icon, "icon_water")
  T.eq(Run.firstChange(reg, tun, cause), tun.ui.failure.firstThirst)
  -- Hunger and cold keep their old causes.
  T.eq(Run.cause(tun, { hunger = 1, cold = 0, thirst = 0 }).kind, "hunger")
  T.eq(Run.cause(tun, { hunger = 0, cold = 1, thirst = 0 }).kind, "cold")
  T.eq(Run.cause(tun, { hunger = 1, cold = 1 }).kind, "both", "an older payload without thirst")
end)

-- Fetching and melting -----------------------------------------------------------------------------

T.test("fetch_drinking: only wanted when the water on hand is low, and fills the canteen at the creek", function()
  local world = newWorld(2)
  local hs = Actors.homesteader(world)
  local task = Tasks.get(world, "fetch_drinking")
  local function offered()
    local n = 0
    task.candidates(world, hs, function()
      n = n + 1
    end)
    return n
  end
  T.eq(offered(), 0, "a full canteen needs nothing")
  emptyCanteen(world)
  T.truthy(offered() > 0, "an empty one sends the homesteader to the creek")
  local filled = collect(world, "water.canteen")
  local bank = Tasks.get(world, "fetch_drinking")
  local tile
  bank.candidates(world, hs, function(i)
    tile = tile or i
  end)
  T.truthy(bank.canDo(world, hs, tile))
  bank.complete(world, hs, tile)
  T.eq(Needs.canteen(world), cfg.canteenCapacity)
  T.eq(filled[1].source, "creek")
  T.falsy(bank.canDo(world, hs, tile), "full again")
end)

T.test("fetch_drinking: the idle routine keeps the canteen filled for days, with no crops to water", function()
  local world = newWorld(4)
  world.control = "idle"
  Ledger.add(world, "canned_food", 60)
  local fetched = 0
  world.events:on("task.completed", function(e)
    if e.task == "fetch_drinking" then
      fetched = fetched + 1
    end
  end)
  run(world, tun.time.dayLength * 8)
  T.truthy(fetched >= 1, "the routine went for water")
  T.eq(Needs.thirstDays(world), 0, "and was never thirsty")
end)

T.test("fetch_drinking: a well is a closer place to fill the canteen", function()
  local world = newWorld(4)
  local hs = Actors.homesteader(world)
  local well = place(world, "well")
  emptyCanteen(world)
  local seen = {}
  Tasks.get(world, "fetch_drinking").candidates(world, hs, function(i)
    seen[i] = true
  end)
  T.truthy(seen[well], "the well is offered")
  local filled = collect(world, "water.canteen")
  Tasks.get(world, "fetch_drinking").complete(world, hs, well)
  T.eq(filled[1].source, "well")
  -- A cistern is the stock itself: nothing to fetch from it.
  local cistern = place(world, "cistern")
  emptyCanteen(world)
  T.falsy(Tasks.get(world, "fetch_drinking").canDo(world, hs, cistern))
end)

T.test("melt_snow: winter only, beside a fire, and it burns wood", function()
  local world = newWorld(2)
  local hs = Actors.homesteader(world)
  local fire = place(world, "campfire")
  emptyCanteen(world)
  local melt = Tasks.get(world, "melt_snow")
  local wood = Ledger.get(world, "wood") + 5
  Ledger.add(world, "wood", 5)
  setTime(world, dayIn("summer"), 12)
  T.falsy(melt.canDo(world, hs, fire), "no snow in summer")
  setTime(world, dayIn("winter"), 12)
  local offered = {}
  melt.candidates(world, hs, function(i)
    offered[i] = true
  end)
  T.truthy(offered[fire], "the fire is offered")
  T.truthy(melt.canDo(world, hs, fire))
  T.near(melt.workTime(world, hs, fire), cfg.meltTime, 1e-9)
  local filled = collect(world, "water.canteen")
  melt.complete(world, hs, fire)
  T.eq(Ledger.get(world, "wood"), wood - cfg.meltWood)
  T.near(Needs.canteen(world), math.min(cfg.meltYield, cfg.canteenCapacity), 1e-9)
  T.eq(filled[1].source, "snow")
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  emptyCanteen(world)
  T.falsy(melt.canDo(world, hs, fire), "no wood, no melt")
end)

T.test("melt_snow: a winter day with the routine on keeps the water coming", function()
  local world = newWorld(3)
  world.control = "idle"
  place(world, "campfire")
  Ledger.add(world, "wood", 40)
  Ledger.add(world, "canned_food", 60)
  setTime(world, dayIn("winter"), 8)
  emptyCanteen(world)
  local sources = {}
  world.events:on("water.canteen", function(e)
    sources[e.source] = true
  end)
  run(world, tun.time.dayLength * 0.4)
  T.truthy(sources.snow or sources.creek, "water was fetched or melted")
  T.truthy(Needs.canteen(world) > 0)
end)

-- Showing it ---------------------------------------------------------------------------------------------

T.test("alerts: the drink alert follows the days of water on hand", function()
  local world = newWorld(1)
  T.eq((Alerts.level(world, "drink")), 0)
  world.state.needs.canteen = cfg.dailyWater * (tun.alerts.drinkAmberDays - 0.1)
  T.eq((Alerts.level(world, "drink")), 1)
  world.state.needs.canteen = cfg.dailyWater * (tun.alerts.drinkRedDays - 0.1)
  T.eq((Alerts.level(world, "drink")), 2)
  local text = AlertText.toast({ kind = "drink", level = 2, value = 0.4 })
  T.truthy(text:find("Drinking water is low", 1, true))
  T.truthy(AlertText.toast({ kind = "drink", level = 2, value = 0 }):find("Out of drinking water", 1, true))
end)

T.test("chip: the drink chip says what lasts and when you are thirsty", function()
  local world = newWorld(1)
  local ok = ChipText.card(world, "drink")
  T.eq(ok.headline, "Water to drink")
  T.eq(ok.level, 0)
  emptyCanteen(world)
  T.eq(ChipText.card(world, "drink").headline, "Almost out of water")
  Needs.drink(world)
  local thirsty = ChipText.card(world, "drink")
  T.eq(thirsty.headline, "You are thirsty")
  T.eq(thirsty.level, 2)
  local hasRun = false
  for _, row in ipairs(thirsty.rows) do
    hasRun = hasRun or row.label == "Dry days in a row"
  end
  T.truthy(hasRun)
end)

T.test("morning report: a thirsty night is reported with the condition it cost", function()
  local world = newWorld(1)
  emptyCanteen(world)
  Needs.drink(world)
  local open = world.state.nightly.open
  T.truthy(open.thirsty > 0)
  T.near(open.thirstLost, cfg.thirstDamage, 1e-9)
  local report = {
    hours = 8,
    calories = 0,
    hungry = 0,
    thirsty = open.thirsty,
    thirstLost = open.thirstLost,
    cold = 0,
    burned = {},
    electric = 0,
    ate = {},
    raided = {},
    caught = 0,
    killed = 0,
    stopped = 0,
    conditionFrom = 100,
    conditionTo = 85,
  }
  local lines = NightText.morning(world, report)
  local found = false
  for _, line in ipairs(lines) do
    found = found or line.text:find("Went thirsty: -15 condition", 1, true) ~= nil
  end
  T.truthy(found)
end)

T.test("sandbox: drinking from the cistern costs nothing there", function()
  local world = World.new({ registry = reg, tuning = tun, meta = { sandbox = true } }, World.newState(1))
  Ledger.setCapacity(world, "water", 60)
  Ledger.add(world, "water", 10)
  Needs.drink(world)
  T.eq(Ledger.get(world, "water"), 10)
end)
