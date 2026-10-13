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
--   holes = { [tile] = true }, snap = bool,
--   sky = { first = calendar day of days[1], days = { kind, ... } today first, last/spell/left =
--           the spell being laid out } }
-- Day-to-day weather (D51): clear, cloudy, rain, windy and storm spells, rolled ahead from the
-- "sky" RNG stream (so winters are unchanged) and weighted by season. Rain waters crops and fills a
-- cistern (crops.lua, water.lua), clouds and wind scale power (powerInputs), fish activity scales
-- fishing, and Weather.threat is the hook for future threats. The outlook is exact.
-- Emits "weather.forecast" { year, piece }, "weather.coldSnap" { active }, "weather.froze" {},
--       "weather.thawed" {}, "weather.changed" { kind, previous } (each morning the kind differs).

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
  -- Later years also get longer cold snaps (D67); added after the roll, so the draws are unchanged.
  local grow = world.tuning.threats.winter
  local extraSnap = math.min(grow.maxExtraSnapDays, math.floor(grow.snapDaysPerYear * (year - 1)))
  local winter = {
    severity = math.floor(rng:range(cfg.severityMin + extra, cfg.severityMax + extra) * 100 + 0.5) / 100,
    snapStart = rng:int(cfg.snapStartMin, cfg.snapStartMax),
    snapDays = rng:int(cfg.snapDaysMin, cfg.snapDaysMax) + extraSnap,
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

--- Days until the ground freezes, counting today (0 when already frozen; math.huge if never).
function Weather.daysToFreeze(world)
  local time = world.tuning.time
  local now = Calendar.now(world)
  if Weather.isFrozenSeason(world, now.season) then
    return 0
  end
  for n, s in ipairs(time.seasons) do
    if Weather.isFrozenSeason(world, s) then
      return (n - now.seasonIndex) * time.daysPerSeason - now.dayOfSeason + 1
    end
  end
  return math.huge
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

--- Warmth needed tonight: the season's base, scaled by the winter's severity and any cold snap.
function Weather.warmthNeed(world)
  return world.tuning.needs.dailyWarmth[Calendar.now(world).season] * Weather.warmthMultiplier(world)
end

--- Warmth the night of `dayOfSeason` in `season` should need, going only on what the forecast has
--- revealed so far (D70, #166). Returns the need and whether it is exact. In a frozen season an
--- unrevealed severity counts as the lowest this year can roll and an unrevealed cold snap as none, so
--- the figure is a floor until the forecast is complete.
function Weather.expectedWarmthNeed(world, season, dayOfSeason)
  local base = world.tuning.needs.dailyWarmth[season]
  if not Weather.isFrozenSeason(world, season) then
    return base, true
  end
  local cfg = world.tuning.weather
  local f = Weather.forecast(world)
  local year = Calendar.now(world).year
  local mult = f.severity or (cfg.severityMin + cfg.severityPerYear * (year - 1))
  local exact = f.severity ~= nil and f.snapDays ~= nil
  if f.snapStart and f.snapDays and dayOfSeason >= f.snapStart and dayOfSeason < f.snapStart + f.snapDays then
    mult = mult * cfg.snapMultiplier
  end
  return base * mult, exact
end

-- The sky (D51) -----------------------------------------------------------------------------

-- Roll the kind and length of the next spell, for the day `day` (its season sets the weights).
local function rollSpell(world, sky, day)
  local cfg = world.tuning.weather
  local season = world.tuning.time.seasons[Calendar.seasonOfDay(world, day)]
  local weights, from, rng = cfg.seasonWeights[season], cfg.transitions[sky.last], world:rng("sky")
  local total = 0
  for _, kind in ipairs(cfg.order) do
    total = total + weights[kind] * from[kind]
  end
  local pick = rng:float() * total
  local chosen = cfg.order[1]
  for _, kind in ipairs(cfg.order) do
    local w = weights[kind] * from[kind]
    if w > 0 then
      chosen = kind
      if pick < w then
        break
      end
      pick = pick - w
    end
  end
  local days = cfg.kinds[chosen].days
  sky.spell, sky.left, sky.last = chosen, rng:int(days[1], days[2]), chosen
end

-- Keep the queue of upcoming days full.
local function fillSky(world, sky)
  local cfg = world.tuning.weather
  while #sky.days < cfg.queueDays do
    if sky.left <= 0 then
      rollSpell(world, sky, sky.first + #sky.days)
    end
    local kind = sky.spell
    local day = sky.first + #sky.days
    -- A spell of rain that runs into a frozen season falls as snow, which is the winter look: cloudy.
    if cfg.kinds[kind].rainfall > 0 and Weather.isFrozenSeason(world, world.tuning.time.seasons[Calendar.seasonOfDay(world, day)]) then
      kind = cfg.frozenRainKind
    end
    sky.days[#sky.days + 1] = kind
    sky.left = sky.left - 1
  end
end

-- Move the sky to today (more than one day may have passed), rolling more days as needed.
local function syncSky(world)
  local sky = state(world).sky
  local today = Calendar.now(world).day
  local before = sky.days[1]
  while sky.first < today do
    table.remove(sky.days, 1)
    sky.first = sky.first + 1
    fillSky(world, sky)
  end
  if before and sky.days[1] ~= before then
    world.events:emit("weather.changed", { kind = sky.days[1], previous = before })
  end
end

local function newSky(world)
  local cfg = world.tuning.weather
  return {
    first = Calendar.now(world).day, -- calendar day of days[1]
    days = { cfg.startKind }, -- upcoming kinds by day, today first
    last = cfg.startKind, -- kind of the most recent spell rolled
    spell = cfg.startKind, -- kind of the spell being laid out
    left = cfg.kinds[cfg.startKind].days[1] - 1, -- days of that spell still to lay out
  }
end

--- Today's weather kind id ("clear", "cloudy", "rain", "windy", "storm").
function Weather.kind(world)
  return state(world).sky.days[1]
end

--- Today's kind definition (tuning.weather.kinds[kind]); read-only.
function Weather.current(world)
  return world.tuning.weather.kinds[Weather.kind(world)]
end

--- Is it raining? Not while the ground is frozen: that precipitation is the winter look.
function Weather.isRaining(world)
  return Weather.current(world).rainfall > 0 and not Weather.isFrozen(world)
end

--- Multiplier on rain water gathered (0 when dry).
function Weather.rainfall(world)
  return Weather.isRaining(world) and Weather.current(world).rainfall or 0
end

--- Fish activity multiplier right now (1 = normal): scales idle catch odds and bite speed.
function Weather.fishActivity(world)
  return Weather.current(world).fish
end

--- Multiplier for threats (GDD §7.9): storms and wind raise it. Read by mice (D54), predators (D64)
--- and the weather-driven growing-season threats (hail, D67).
function Weather.threat(world)
  return Weather.current(world).threat
end

--- The threat multiplier of the day `offset` days ahead (0 = today), from the rolled sky. Past the
--- rolled queue it is 1 (unknown weather counts as ordinary).
function Weather.threatAhead(world, offset)
  local kind = state(world).sky.days[offset + 1]
  return kind and world.tuning.weather.kinds[kind].threat or 1
end

--- Wind multiplier of today's weather (1 = ordinary, above 1 = gusty). The hook for wind sway and
--- drifting cloud shadows (#49); the turbines use it through powerInputs.
function Weather.windStrength(world)
  return Weather.current(world).wind
end

--- Days of forecast the player can see past today: the base horizon plus weather sense.
function Weather.forecastHorizon(world)
  local cfg = world.tuning.weather
  return math.min(cfg.queueDays - 1, cfg.forecastHorizon + math.floor(Stats.modifier(world, "forecastLead")))
end

--- Upcoming weather as a list of { offset (0 = today), kind } for today and the visible days ahead.
function Weather.outlook(world)
  local sky, list = state(world).sky, {}
  for offset = 0, Weather.forecastHorizon(world) do
    list[#list + 1] = { offset = offset, kind = sky.days[offset + 1] }
  end
  return list
end

--- What the weather does to power generation right now: { cloud (0..1 of sunlight blocked),
--- wind (turbine multiplier), flow (micro-hydro multiplier) }. The power network reads this every
--- tick (GDD §7.5). Read-only.
function Weather.powerInputs(world)
  return Weather.current(world)
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
  -- A fresh run rolls its sky from today.
  if not state(world).sky then
    state(world).sky = newSky(world)
  end
  fillSky(world, state(world).sky)
  syncSky(world)
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
    syncSky(world)
    revealForecast(world)
    local snap = Weather.isColdSnap(world)
    if snap ~= state(world).snap then
      state(world).snap = snap
      world.events:emit("weather.coldSnap", { active = snap })
    end
  end)
end

return Weather
