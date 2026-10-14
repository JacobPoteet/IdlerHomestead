-- Progress metrics (GDD D117, #275): sales income per game year, years survived and best year's income
-- in the run summary and the slot best, the recovery table, and the slot screen's journal line.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Income = require("src.sim.systems.income")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Food = require("src.sim.systems.food")
local Run = require("src.meta.run")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local DAYS_PER_YEAR = tun.time.daysPerSeason * #tun.time.seasons

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

--- Put the clock on `day` at noon.
local function setDay(world, day)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + 0.5) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function yearStart(year)
  return (year - 1) * DAYS_PER_YEAR + 1
end

-- Income tracking ------------------------------------------------------------------------------------

T.test("income: truck sales and stand sales count, other money does not", function()
  local world = newWorld()
  world.state.market.prices = {}
  Ledger.add(world, "wood", 60)
  Food.setKeep(world, "wood", 0)
  Market.setLoad(world, "wood", tun.economy.cargoCapacity, true)
  world.state.power.charge[world.state.land.truck] = tun.economy.tripCost
  T.truthy(Market.startTrip(world))
  local earned = Market.sellLoad(world)
  T.truthy(earned > 0)
  T.eq(Income.thisYear(world), earned, "the truck trip is income")
  world.events:emit("stand.sold", { day = 1, units = 3, earned = 7, cap = 5 })
  T.eq(Income.thisYear(world), earned + 7, "so is the stand")
  Ledger.add(world, "money", 50, "refund")
  Ledger.add(world, "money", 50, "find")
  Ledger.remove(world, "money", 20, "bought")
  T.eq(Income.thisYear(world), earned + 7, "refunds, finds and spending are ignored")
  T.eq(Income.total(world), earned + 7)
  T.eq((Income.best(world)), earned + 7)
end)

T.test("income: tracked per game year, best year kept", function()
  local world = newWorld()
  setDay(world, 10)
  world.events:emit("market.sold", { earnings = 100, units = 5 })
  world.events:emit("stand.sold", { earned = 20 })
  T.eq(Income.thisYear(world), 120)
  setDay(world, yearStart(2) + 3)
  T.eq(Income.thisYear(world), 0, "a new year starts from zero")
  world.events:emit("market.sold", { earnings = 80 })
  T.eq(Income.thisYear(world), 80)
  local best, year = Income.best(world)
  T.eq(best, 120, "year 1 is still the best")
  T.eq(year, 1)
  world.events:emit("market.sold", { earnings = 60 })
  best, year = Income.best(world)
  T.eq(best, 140, "year 2 passes it")
  T.eq(year, 2)
  setDay(world, yearStart(3))
  world.events:emit("market.sold", { earnings = 10 })
  T.eq((Income.best(world)), 140, "a poorer year never lowers the best")
  T.eq(Income.total(world), 270)
end)

T.test("income: empty or negative sales change nothing, and the state survives a save", function()
  local world = newWorld()
  world.events:emit("market.sold", { earnings = 0 })
  world.events:emit("market.sold", { earnings = -5 })
  world.events:emit("market.sold", {})
  T.eq(Income.total(world), 0)
  world.events:emit("market.sold", { earnings = 45 })
  local copy = serialize.decode(serialize.encode(world.state.income))
  T.eq(copy.best, 45)
  T.eq(copy.current, 45)
end)

-- Summary and slot best -----------------------------------------------------------------------------------

local function endRun(data, dayReached, income)
  local world = newWorld(1, data.meta)
  setDay(world, dayReached)
  if income and income > 0 then
    world.events:emit("market.sold", { earnings = income })
  end
  return Run.fail(data, world), world
end

T.test("summary: years survived are the full years completed", function()
  local data = Save.newSlotData("Years")
  T.eq(endRun(data, 5).yearsSurvived, 0, "dying in year 1 survived no full year")
  Run.startNext(data)
  T.eq(endRun(data, yearStart(3) + 10).yearsSurvived, 2, "dying in year 3 survived two")
  Run.startNext(data)
  T.eq(endRun(data, yearStart(2) - 1).yearsSurvived, 0, "the last day of year 1")
  Run.startNext(data)
  T.eq(endRun(data, yearStart(2)).yearsSurvived, 1, "the first day of year 2")
end)

T.test("summary: best year's income and the slot best, with a new-best marker from the second run", function()
  local data = Save.newSlotData("Best")
  local first = endRun(data, yearStart(2) + 4, 90)
  T.eq(first.bestYearIncome, 90)
  T.eq(first.newBest, nil, "the first run has nothing to beat")
  T.eq(data.meta.career.best.years, 1)
  T.eq(data.meta.career.best.yearIncome, 90)
  Run.startNext(data)
  local second = endRun(data, yearStart(2) + 1, 40)
  T.eq(second.newBest.years, false, "equal is not a new best")
  T.eq(second.newBest.yearIncome, false)
  T.eq(data.meta.career.best.yearIncome, 90, "a worse run leaves the best alone")
  Run.startNext(data)
  local third = endRun(data, yearStart(4), 200)
  T.eq(third.newBest.years, true)
  T.eq(third.newBest.yearIncome, true)
  T.eq(data.meta.career.best.years, 3)
  T.eq(data.meta.career.best.yearIncome, 200)
  T.eq(data.meta.recovery.summary.bestYearIncome, 200, "the recovery screen reads the same summary")
  local copy = serialize.decode(serialize.encode(data.meta))
  T.eq(copy.career.best.years, 3, "the slot best is saved in the meta")
  T.eq(#copy.career.history, 3)
end)

T.test("recovery table: first run shows one column, later runs show previous and slot best", function()
  local data = Save.newSlotData("Table")
  endRun(data, yearStart(2) + 2, 50)
  local t = Run.progressTable(tun, data.meta.career, data.meta.recovery.summary)
  T.truthy(t.first)
  T.eq(#t.columns, 1)
  T.eq(t.rows[1].cells[1], "1")
  T.eq(t.rows[2].cells[1], "$50")
  T.falsy(t.rows[1].newBest or t.rows[2].newBest, "no marker on a first run")
  Run.startNext(data)
  endRun(data, yearStart(3) + 2, 30)
  t = Run.progressTable(tun, data.meta.career, data.meta.recovery.summary)
  T.falsy(t.first)
  T.eq(#t.columns, 3)
  T.eq(t.rows[1].cells[1], "2")
  T.eq(t.rows[1].cells[2], "1", "previous run")
  T.eq(t.rows[1].cells[3], "2", "slot best")
  T.truthy(t.rows[1].newBest, "more years than ever")
  T.eq(t.rows[2].cells[1], "$30")
  T.eq(t.rows[2].cells[2], "$50")
  T.eq(t.rows[2].cells[3], "$50")
  T.falsy(t.rows[2].newBest, "less income than the best")
end)

-- Journal completion --------------------------------------------------------------------------------------

T.test("journal: completion counts known nodes over every node, starters included", function()
  local world = newWorld()
  local known, total = Journal.completion(world)
  T.eq(total, #Journal.nodes(world))
  local starters = 0
  for _, def in ipairs(reg:all("catalog")) do
    if def.starter then
      starters = starters + 1
    end
  end
  T.eq(known, starters, "a new slot knows its starters only")
  local target
  for _, def in ipairs(Journal.nodes(world)) do
    if not Journal.isKnown(world, def.id) then
      target = def.id
      break
    end
  end
  world.meta.journal.known[target] = true
  T.eq((Journal.completion(world)), starters + 1)
end)

T.test("journal: the slot header carries counts only, and the slot line is a rounded-down percentage", function()
  local out = newWorld():summarize()
  T.eq(type(out.journalKnown), "number")
  T.eq(type(out.journalTotal), "number")
  for key, value in pairs(out) do
    T.falsy(type(value) == "string" and reg:has("catalog", value), key .. " must not name a node")
  end
  local fmt = tun.ui.progress.journalLine
  T.eq(Run.journalLine(tun, { journalKnown = 1, journalTotal = 3 }), string.format(fmt, 33))
  T.eq(Run.journalLine(tun, { journalKnown = 3, journalTotal = 3 }), string.format(fmt, 100))
  T.eq(Run.journalLine(tun, { journalKnown = 299, journalTotal = 300 }), string.format(fmt, 99), "never rounds up to 100")
  T.eq(Run.journalLine(tun, {}), nil, "a header without figures shows no line")
  T.eq(Run.journalLine(tun, nil), nil)
end)

T.test("journal: the header follows a run's end and the free study, and the slot list reads it", function()
  local data = Save.newSlotData("Header")
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local world = newWorld(1, data.meta)
  setDay(world, 3)
  Run.fail(data, world)
  local before = data.header.journalKnown
  T.truthy(before and data.header.journalTotal)
  local metaWorld = Run.metaWorld({ registry = reg, tuning = tun }, data.meta)
  local idea
  for _, def in ipairs(Journal.nodes(metaWorld)) do
    if not Journal.isKnown(metaWorld, def.id) then
      idea = def.id
      break
    end
  end
  for _, def in ipairs(reg:all("notes")) do
    data.meta.journal.notes[def.id] = { day = 1, run = 1 }
  end
  T.truthy(Run.freeStudy(data, metaWorld, idea))
  T.eq(data.header.journalKnown, before + 1)
  store:write(1, data)
  T.eq(store:list()[1].header.journalKnown, before + 1, "the slot list reads it from the header sidecar")
end)
