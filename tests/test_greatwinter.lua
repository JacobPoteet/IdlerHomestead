-- The Great Winter and the Established soft win (GDD D117, #277): the winter of year
-- tuning.progress.greatWinterYear is the hardest the run has faced, announced in full from the start of
-- autumn, and living to its thaw marks the slot once.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Rng = require("src.core.rng")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Established = require("src.sim.systems.established")
local Readiness = require("src.sim.systems.readiness")
local Run = require("src.meta.run")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24
local DPS = tun.time.daysPerSeason
local DPY = DPS * #tun.time.seasons
local GREAT = tun.progress.greatWinterYear

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - tun.time.startHour / 24) * tun.time.dayLength
  world.state.calendar.day = day
end

--- Tick across midnight into `day` (so newDay and newSeason fire), landing at 01:00.
local function arriveOn(world, day)
  setTime(world, day - 1, 23.5)
  for _ = 1, math.floor(HOUR * 1.5 / STEP) do
    world:tick(STEP)
  end
end

local function seasonStart(year, seasonIndex)
  return (year - 1) * DPY + (seasonIndex - 1) * DPS + 1
end

--- Walk season by season to the start of `seasonIndex` in `year`.
local function walkTo(world, year, seasonIndex)
  local last = (year - 1) * #tun.time.seasons + seasonIndex
  local first = math.floor((world.state.calendar.day - 1) / DPS) + 2 -- the next season start
  for n = first, last do
    arriveOn(world, (n - 1) * DPS + 1)
  end
end

local function record(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

-- The winter roll ---------------------------------------------------------------------------------

--- The winter draws as they were before the Great Winter existed: severity, snap start, snap length per year.
local function rawWinters(seed, years)
  local rng = Rng.new(Rng.deriveSeed(seed, "weather"))
  local cfg, grow = tun.weather, tun.threats.winter
  local out = {}
  for year = 1, years do
    local extra = cfg.severityPerYear * (year - 1)
    out[year] = {
      severity = math.floor(rng:range(cfg.severityMin + extra, cfg.severityMax + extra) * 100 + 0.5) / 100,
      snapStart = rng:int(cfg.snapStartMin, cfg.snapStartMax),
      snapDays = rng:int(cfg.snapDaysMin, cfg.snapDaysMax)
        + math.min(grow.maxExtraSnapDays, math.floor(grow.snapDaysPerYear * (year - 1))),
    }
  end
  return out
end

T.test("great winter: only the configured year is the Great Winter", function()
  T.truthy(Weather.isGreatWinterYear(newWorld(), GREAT))
  T.falsy(Weather.isGreatWinterYear(newWorld(), GREAT - 1))
  T.falsy(Weather.isGreatWinterYear(newWorld(), GREAT + 1))
end)

T.test("great winter: severity is at least the run's worst plus the boost, with a guaranteed snap", function()
  for seed = 1, 40 do
    local world = newWorld(seed)
    local worst = 0
    for year = 1, GREAT - 1 do
      worst = math.max(worst, Weather.winter(world, year).severity)
    end
    local great = Weather.winter(world, GREAT)
    T.truthy(
      great.severity >= worst + tun.progress.greatWinterBoost - 0.006,
      "seed " .. seed .. ": " .. great.severity .. " vs worst " .. worst
    )
    T.truthy(great.snapDays >= tun.progress.greatWinterSnapDays, "a snap of at least the minimum")
    T.truthy(great.snapStart >= tun.weather.snapStartMin and great.snapStart <= tun.weather.snapStartMax)
  end
end)

T.test("great winter: every other winter and every draw is unchanged", function()
  for seed = 1, 20 do
    local raw = rawWinters(seed, GREAT + 3)
    local world = newWorld(seed)
    for year = 1, GREAT + 3 do
      local w = Weather.winter(world, year)
      if year == GREAT then
        T.eq(w.snapStart, raw[year].snapStart, "the snap timing is the same draw")
        T.eq(w.severity >= raw[year].severity, true, "never milder than the plain roll")
        T.eq(w.snapDays >= raw[year].snapDays, true)
      else
        T.eq(w.severity, raw[year].severity, "seed " .. seed .. " year " .. year)
        T.eq(w.snapStart, raw[year].snapStart)
        T.eq(w.snapDays, raw[year].snapDays)
      end
    end
  end
end)

T.test("great winter: the forecast bound used for planning covers it", function()
  for seed = 1, 20 do
    local world = newWorld(seed)
    for year = 1, GREAT do
      local bound = Weather.severityBound(world, year)
      T.truthy(Weather.winter(world, year).severity <= bound + 0.006, "seed " .. seed .. " year " .. year)
    end
  end
  T.truthy(Readiness.warmthAhead(newWorld()) > 0)
end)

-- The forecast -------------------------------------------------------------------------------------

T.test("great winter: the full forecast is revealed from the first day of autumn", function()
  local world = newWorld(5)
  local pieces = record(world, "weather.forecast")
  walkTo(world, GREAT - 1, 3) -- autumn of the year before: an ordinary winter ahead
  local f = Weather.forecast(world)
  T.falsy(f.great)
  T.eq(f.severity, nil, "an ordinary winter is revealed in pieces during autumn")
  for _, p in ipairs(pieces) do
    T.truthy(p.year < GREAT - 1, "no piece of that year yet")
  end
  walkTo(world, GREAT, 1)
  walkTo(world, GREAT, 2)
  T.eq(Weather.forecast(world).severity, nil, "nothing yet in summer")
  arriveOn(world, seasonStart(GREAT, 3))
  f = Weather.forecast(world)
  T.truthy(f.great, "named")
  T.truthy(f.severity and f.snapStart and f.snapDays, "severity, snap timing and snap length all known")
  T.eq(f.severity, Weather.winter(world, GREAT).severity)
  local seen = 0
  for _, p in ipairs(pieces) do
    if p.year == GREAT then
      seen = seen + 1
    end
  end
  T.eq(seen, #tun.weather.forecastDays, "every piece is announced that morning")
end)

-- Established --------------------------------------------------------------------------------------

T.test("established: fires once at the first thaw after the Great Winter and marks the slot", function()
  local meta = {}
  local world = newWorld(7, meta)
  local fired = record(world, "progress.established")
  walkTo(world, GREAT, 4) -- the Great Winter begins
  T.eq(#fired, 0)
  T.eq(meta.established, nil)
  setTime(world, seasonStart(GREAT, 4) + DPS - 1, 12) -- winter's last day
  arriveOn(world, seasonStart(GREAT + 1, 1) - 1)
  T.eq(#fired, 0, "the last day of winter is not the thaw")
  arriveOn(world, seasonStart(GREAT + 1, 1))
  T.eq(#fired, 1)
  T.eq(fired[1].year, GREAT)
  T.eq(fired[1].first, true)
  T.eq(meta.established.run, 1)
  T.eq(meta.established.year, GREAT)
  T.eq(Established.cardDue(meta), true)
  walkTo(world, GREAT + 1, 4)
  arriveOn(world, seasonStart(GREAT + 2, 1))
  T.eq(#fired, 1, "later thaws are not the Great Winter's")
end)

T.test("established: an earlier winter's thaw does nothing", function()
  local meta = {}
  local world = newWorld(7, meta)
  local fired = record(world, "progress.established")
  walkTo(world, GREAT - 1, 4)
  arriveOn(world, seasonStart(GREAT, 1))
  T.eq(#fired, 0)
  T.eq(meta.established, nil)
end)

T.test("established: the slot mark and the card are once per slot; later runs still face the Great Winter", function()
  local data = Save.newSlotData("Established")
  local world = newWorld(3, data.meta)
  walkTo(world, GREAT + 1, 1)
  T.truthy(data.meta.established)
  T.eq(Established.cardDue(data.meta), true)
  Established.cardShown(data.meta)
  T.eq(Established.cardDue(data.meta), false)
  -- Run 1 ends, run 2 begins on the same slot and gets its own Great Winter at the same year.
  Run.fail(data, world)
  Run.startNext(data)
  local second = newWorld(4, data.meta)
  local fired = record(second, "progress.established")
  local before = Weather.winter(second, GREAT).severity
  T.truthy(before >= 0)
  walkTo(second, GREAT + 1, 1)
  T.eq(#fired, 1, "the event still fires in a later run")
  T.eq(fired[1].first, false)
  T.eq(fired[1].run, 2)
  T.eq(data.meta.established.run, 1, "the mark keeps the run that got there first")
  T.eq(Established.cardDue(data.meta), false, "no second card")
  local copy = serialize.decode(serialize.encode(data.meta))
  T.eq(copy.established.year, GREAT, "saved in the meta")
  T.eq(copy.established.seen, true)
end)

T.test("established: a run that dies before the thaw leaves the slot unmarked and the summary says so", function()
  local data = Save.newSlotData("Died")
  local world = newWorld(3, data.meta)
  walkTo(world, GREAT, 4)
  local summary = Run.fail(data, world)
  T.eq(summary.greatWinter, false)
  T.eq(data.meta.established, nil)
  Run.startNext(data)
  local second = newWorld(3, data.meta)
  walkTo(second, GREAT + 1, 1)
  local won = Run.fail(data, second)
  T.eq(won.greatWinter, true)
  local table_ = Run.progressTable(tun, data.meta.career, won)
  T.eq(table_.rows[3].cells[1], tun.ui.greatWinter.surviveYes)
  T.eq(table_.rows[3].cells[2], tun.ui.greatWinter.surviveNo, "the previous run did not")
  T.eq(table_.rows[3].cells[3], tun.ui.greatWinter.surviveYes, "the slot's best did")
end)

T.test("great winter: the progress table has no Great Winter row until one is survived", function()
  local data = Save.newSlotData("Row")
  local world = newWorld(2, data.meta)
  local summary = Run.fail(data, world)
  T.eq(#Run.progressTable(tun, data.meta.career, summary).rows, 2)
end)

T.test("great winter: deterministic per seed", function()
  local a, b = newWorld(11), newWorld(11)
  walkTo(a, GREAT + 1, 1)
  walkTo(b, GREAT + 1, 1)
  T.eq(serialize.encode(a.state.weather.winters), serialize.encode(b.state.weather.winters))
  T.eq(serialize.encode(a.state.weather.revealed), serialize.encode(b.state.weather.revealed))
  local c = newWorld(12)
  walkTo(c, GREAT + 1, 1)
  T.truthy(serialize.encode(a.state.weather.winters) ~= serialize.encode(c.state.weather.winters), "another seed differs")
end)
