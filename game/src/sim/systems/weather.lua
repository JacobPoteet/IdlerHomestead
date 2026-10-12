-- Weather & winter (GDD §4.1, §7.9). Each year rolls its own winter: a severity (multiplier on
-- the warmth need, growing year over year) and a cold snap (a few nights of much harder cold).
-- The season before the freeze reveals the forecast in pieces (severity, then snap timing, then
-- snap length); the "forecastLead" stat (weather sense) reveals them earlier.
--
-- In frozen seasons the ground and creek freeze: crops stop growing (see crops.lua) and getting at
-- the water means cutting an ice hole first (holes stay open until the thaw).
--
-- State: world.state.weather = {
--   winters = { [year] = { severity, snapStart, snapDays } },
--   revealed = { [year] = forecast pieces revealed (0..#forecastDays) },
--   holes = { [tile] = true }, snap = bool }
-- Emits "weather.forecast" { year, piece }, "weather.coldSnap" { active }, "weather.froze" {},
--       "weather.thawed" {}.

local Calendar = require("src.sim.systems.calendar")
local Stats = require("src.sim.stats")

local Weather = {}

local function state(world)
  return world.state.weather
end

local function rollWinter(world, year)
  local cfg = world.tuning.weather
  local rng = world:rng("weather")
  local extra = cfg.severityPerYear * (year - 1)
  local winter = {
    severity = math.floor(rng:range(cfg.severityMin + extra, cfg.severityMax + extra) * 100 + 0.5) / 100,
    snapStart = rng:int(cfg.snapStartMin, cfg.snapStartMax),
    snapDays = rng:int(cfg.snapDaysMin, cfg.snapDaysMax),
  }
  state(world).winters[year] = winter
  return winter
end

--- A year's winter (default: this year): { severity, snapStart, snapDays }.
function Weather.winter(world, year)
  year = year or Calendar.now(world).year
  return state(world).winters[year] or rollWinter(world, year)
end

function Weather.isFrozenSeason(world, season)
  for _, s in ipairs(world.tuning.weather.frozenSeasons) do
    if s == season then
      return true
    end
  end
  return false
end

--- Are the ground and creek frozen right now?
function Weather.isFrozen(world)
  return Weather.isFrozenSeason(world, Calendar.now(world).season)
end

function Weather.isColdSnap(world)
  if not Weather.isFrozen(world) then
    return false
  end
  local winter = Weather.winter(world)
  local day = Calendar.now(world).dayOfSeason
  return day >= winter.snapStart and day < winter.snapStart + winter.snapDays
end

--- Multiplier on the season's warmth need: the winter's severity, more during the cold snap.
function Weather.warmthMultiplier(world)
  if not Weather.isFrozen(world) then
    return 1
  end
  local mult = Weather.winter(world).severity
  if Weather.isColdSnap(world) then
    mult = mult * world.tuning.weather.snapMultiplier
  end
  return mult
end

--- 1 (mild), 2 (hard) or 3 (brutal) for a severity multiplier.
function Weather.severityLevel(world, severity)
  local level = 1
  for _, threshold in ipairs(world.tuning.weather.severityLevels) do
    if severity >= threshold then
      level = level + 1
    end
  end
  return level
end

--- What's known about this year's winter: { severity?, snapStart?, snapDays? } (revealed pieces).
function Weather.forecast(world)
  local year = Calendar.now(world).year
  local winter = Weather.winter(world, year)
  local n = state(world).revealed[year] or 0
  return {
    severity = n >= 1 and winter.severity or nil,
    snapStart = n >= 2 and winter.snapStart or nil,
    snapDays = n >= 3 and winter.snapDays or nil,
  }
end

-- Index of the first frozen season (nil if winters never freeze).
local function frozenIndex(world)
  for n, s in ipairs(world.tuning.time.seasons) do
    if Weather.isFrozenSeason(world, s) then
      return n
    end
  end
  return nil
end

local function revealForecast(world)
  local winterIndex = frozenIndex(world)
  if not winterIndex then
    return
  end
  local now = Calendar.now(world)
  local days = world.tuning.weather.forecastDays
  local seasonsPerYear = #world.tuning.time.seasons
  local before = (winterIndex - 2) % seasonsPerYear + 1
  local inWinter = now.seasonIndex == winterIndex
  if now.seasonIndex ~= before and not inWinter then
    return
  end
  local lead = Stats.modifier(world, "forecastLead")
  local revealed = state(world).revealed
  local n = revealed[now.year] or 0
  while n < #days and (inWinter or now.dayOfSeason >= days[n + 1] - lead) do
    n = n + 1
    revealed[now.year] = n
    world.events:emit("weather.forecast", { year = now.year, piece = n })
  end
end

-- Ice holes ---------------------------------------------------------------------------------

function Weather.hasHole(world, i)
  return state(world).holes[i] == true
end

--- Extra work before using water tile i (cutting through the ice), in seconds.
function Weather.iceWork(world, i)
  if Weather.isFrozen(world) and not Weather.hasHole(world, i) then
    return world.tuning.weather.iceCutTime
  end
  return 0
end

function Weather.openHole(world, i)
  if Weather.isFrozen(world) then
    state(world).holes[i] = true
  end
end

--- For idle routines picking a water tile: while frozen, only existing holes (if there are any),
--- so the homesteader doesn't cut a fresh hole every trip.
function Weather.waterTarget(world, i)
  if Weather.isFrozen(world) and next(state(world).holes) then
    return Weather.hasHole(world, i)
  end
  return true
end

function Weather.init(world)
  world.state.weather = world.state.weather or { winters = {}, revealed = {}, holes = {}, snap = false }
  Weather.winter(world)
  world.events:on("calendar.newSeason", function(e)
    Weather.winter(world, e.year)
    if Weather.isFrozenSeason(world, e.season) then
      world.events:emit("weather.froze", {})
    elseif next(state(world).holes) then
      state(world).holes = {}
      world.events:emit("weather.thawed", {})
    end
  end)
  world.events:on("calendar.newDay", function()
    revealForecast(world)
    local snap = Weather.isColdSnap(world)
    if snap ~= state(world).snap then
      state(world).snap = snap
      world.events:emit("weather.coldSnap", { active = snap })
    end
  end)
end

return Weather
