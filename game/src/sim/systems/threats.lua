-- Growing-season threats and yearly escalation (GDD §4.1, §7.9, D3, D67).
--
-- Each year gets a schedule, rolled once from its own seeded stream ("threats", so no other stream
-- or seed changes): how many threats (tuning.threats.count by year), which ones (content weight,
-- `minYear`, never before `firstSeason`), when (a day in the threat's season) and for how long. The
-- strength curve scales every threat's damage share and drying rate, so year 1 is gentle and later
-- years bite harder; winters grow too (longer cold snaps, see Weather.winter).
--
-- A threat is announced `warnDays` (plus the weather-sense stat) before it starts ("threat.warned"),
-- is shown on the forecast while warned or active (Threats.outlook), and ends with a summary
-- ("threat.ended"). Effects (content):
--   damage   once, at the threat's hour: each crop in the ground rolls; a share is killed or knocked
--            back. A weather-driven threat (`strike`, hail) instead rolls each day of its span at its
--            hour with chance x Weather.threat ^ weatherPower (#97), so storms bring it, and strikes
--            at most once; a span without a strike passes harmlessly.
--   spread   (blight, #154) a disease: on a day at the threat's hour (far likelier when it rains) one crop is
--            infected, then each day every infected crop is knocked back, dies after `killDays`, and may pass
--            it to a crop on each of the four neighbouring tiles (likelier on tiles with pest pressure, D179).
--            Pulling or harvesting an infected crop ends its infection; the span's end clears the rest.
--   drought  for its span the beds dry `dryRate` times faster and a crop left dry for `witherHours`
--            withers; rain breaks the drought early.
-- Countermeasures are catalog equipment whose modifiers name the threat's `guard` stat; the guard
-- turns that share of the threat aside (crops it saved are counted). The first strike of each
-- threat writes its Field Journal note (event "threat.struck"), which makes the countermeasure an
-- idea. With nothing in the ground a threat still comes and goes, and changes nothing.
--
-- State: world.state.threats = {
--   years = { [year] = { { id, start (calendar day), days, status = "waiting"|"active"|"done",
--                          warned, rollDay, struck, lost, damaged, saved, broken } ... } },
--   dry = { [tile] = in-game hours a crop has sat dry during a drought },
--   blight = { [tile] = days the crop there has been infected },
--   history = { { year, id, struck, lost, damaged, saved } ... } (last `historyLimit`) }
-- Emits "threat.warned" { threat, days }, "threat.started" { threat, days },
--   "threat.struck" { threat, hit, lost, damaged, saved }, "threat.ended" { threat, struck, lost,
--   damaged, saved, broken }; crops report "crop.lost" / "crop.damaged" with cause = threat id.

local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Soil = require("src.sim.systems.soil")
local Stats = require("src.sim.stats")
local Weather = require("src.sim.systems.weather")

local Threats = {}

local function state(world)
  return world.state.threats
end

local function def(world, id)
  return world.registry:get("threats", id)
end

-- Value of a by-year curve: the list entry, or past its end the last entry plus `perYear` a year.
local function curve(list, year, perYear)
  if year <= #list then
    return list[year]
  end
  return list[#list] + (perYear or 0) * (year - #list)
end

local function seasonIndex(world, season)
  for n, s in ipairs(world.tuning.time.seasons) do
    if s == season then
      return n
    end
  end
  error("threat season '" .. tostring(season) .. "' is not a season id")
end

--- Strength multiplier for a year (default: this year).
function Threats.strength(world, year)
  local cfg = world.tuning.threats
  year = year or Calendar.now(world).year
  return math.min(cfg.maxStrength, curve(cfg.strength, year, cfg.strengthPerYear))
end

--- Threats scheduled in a year (before overlaps drop any).
function Threats.count(world, year)
  local cfg = world.tuning.threats
  return math.floor(curve(cfg.count, year, cfg.countPerYear))
end

--- Share (0..1) of a threat the owned countermeasures turn aside.
function Threats.guard(world, id)
  return math.min(world.tuning.threats.maxGuard, Stats.modifier(world, def(world, id).guard))
end

--- Days of warning before a threat starts: the base plus weather sense (forecastLead).
function Threats.warnLead(world)
  return world.tuning.threats.warnDays + math.floor(Stats.modifier(world, "forecastLead"))
end

--- Chance a weather-driven threat strikes on the day `offset` days ahead (0 = today), or nil for a
--- threat that is not weather-driven.
function Threats.strikeChance(world, id, offset)
  local strike = def(world, id).strike
  if not strike then
    return nil
  end
  return math.min(1, strike.chance * Weather.threatAhead(world, offset or 0) ^ strike.weatherPower)
end

-- Scheduling --------------------------------------------------------------------------------------

local function rollYear(world, year)
  local cfg, time = world.tuning.threats, world.tuning.time
  local rng = world:rng("threats")
  local dps, perYear = time.daysPerSeason, #time.seasons
  local yearStart = (year - 1) * perYear * dps -- calendar day before the year's first day
  local firstSeason = curve(cfg.firstSeason, year)
  local pool = {}
  for _, d in ipairs(world.registry:all("threats")) do
    if d.minYear <= year and seasonIndex(world, d.season) >= firstSeason then
      pool[#pool + 1] = d
    end
  end
  local list = {}
  for _ = 1, Threats.count(world, year) do
    if #pool == 0 then
      break
    end
    local total = 0
    for _, d in ipairs(pool) do
      total = total + d.weight
    end
    local pick, chosen = rng:float() * total, #pool
    for n, d in ipairs(pool) do
      if pick < d.weight then
        chosen = n
        break
      end
      pick = pick - d.weight
    end
    local d = table.remove(pool, chosen)
    local s = seasonIndex(world, d.season)
    local start = yearStart + (s - 1) * dps + rng:int(d.startDays[1], d.startDays[2])
    local days = rng:int(d.span[1], d.span[2])
    -- Keep threats apart: push this one past any it overlaps (with a gap), drop it if its season runs out.
    local moved = true
    while moved do
      moved = false
      for _, other in ipairs(list) do
        local otherEnd = other.start + other.days - 1
        if start <= otherEnd + cfg.gapDays and start + days - 1 + cfg.gapDays >= other.start then
          start = otherEnd + cfg.gapDays + 1
          moved = true
        end
      end
    end
    if start + days - 1 <= yearStart + s * dps then
      list[#list + 1] = {
        id = d.id,
        start = start,
        days = days,
        status = "waiting",
        warned = false,
        rollDay = 0,
        struck = false,
        lost = 0,
        damaged = 0,
        saved = 0,
        broken = false,
      }
    end
  end
  table.sort(list, function(a, b)
    return a.start < b.start
  end)
  -- A schedule rolled late (an older save loaded mid-year) skips what is already past, silently.
  local today = Calendar.now(world).day
  for _, e in ipairs(list) do
    if e.start + e.days - 1 < today then
      e.status, e.warned = "done", true
    end
  end
  state(world).years[year] = list
  return list
end

--- The year's schedule (default: this year), rolled the first time it is asked for. Read-only.
function Threats.schedule(world, year)
  year = year or Calendar.now(world).year
  return state(world).years[year] or rollYear(world, year)
end

--- Finished threats, oldest first: { year, id, struck, lost, damaged, saved }. Read-only.
function Threats.history(world)
  return state(world).history
end

--- Threats the player knows about right now (warned or active, not finished), soonest first:
--- { id, name, active, inDays (until it starts; 0 once active), daysLeft (of its span),
---   guard (0..1 from owned countermeasures), risk, riskIn } where risk is the highest strike
--- chance on a visible forecast day of a weather-driven threat and riskIn that day's offset.
function Threats.outlook(world)
  local today = Calendar.now(world).day
  local horizon = Weather.forecastHorizon(world)
  local list = {}
  for _, e in ipairs(Threats.schedule(world)) do
    if e.status ~= "done" and (e.warned or e.status == "active") then
      local d = def(world, e.id)
      local last = e.start + e.days - 1
      local item = {
        id = e.id,
        name = d.name,
        active = e.status == "active",
        inDays = math.max(0, e.start - today),
        daysLeft = last - today + 1,
        guard = Threats.guard(world, e.id),
      }
      if d.strike then
        local from = math.max(0, e.start - today)
        -- Today's roll is spent once its hour has passed.
        if from == 0 and e.rollDay == today then
          from = 1
        end
        for offset = from, math.min(horizon, last - today) do
          local chance = Threats.strikeChance(world, e.id, offset)
          if not item.risk or chance > item.risk then
            item.risk, item.riskIn = chance, offset
          end
        end
      end
      list[#list + 1] = item
    end
  end
  return list
end

-- Effects -----------------------------------------------------------------------------------------

-- Hit the crops once. Every crop in the ground draws one roll (in tile order), whether or not the
-- threat can touch it and whatever the guard, so the stream does not depend on the defences.
local function applyDamage(world, e, d)
  local cfg = world.tuning.threats
  local dmg = d.damage
  local share = math.min(cfg.maxShare, dmg.share * Threats.strength(world))
  local guarded = share * (1 - Threats.guard(world, e.id))
  local rng = world:rng("threats")
  local hit = 0
  for _, i in ipairs(Crops.plantedTiles(world)) do
    local ripe = Crops.isRipeAt(world, i)
    local roll = rng:float()
    if (ripe and dmg.ripe) or (not ripe and dmg.unripe) then
      if roll < guarded then
        hit = hit + 1
        if dmg.kill then
          Crops.destroy(world, i, e.id)
          e.lost = e.lost + 1
        else
          Crops.setBack(world, i, dmg.setback, e.id)
          e.damaged = e.damaged + 1
        end
      elseif roll < share then
        e.saved = e.saved + 1
      end
    end
  end
  e.struck = true
  world.events:emit("threat.struck", { threat = e.id, hit = hit, lost = e.lost, damaged = e.damaged, saved = e.saved })
end

local ORTHO = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

--- Is the crop on tile i infected with blight?
function Threats.blightAt(world, i)
  return state(world).blight[i] ~= nil and Crops.hasCropAt(world, i)
end

--- Tiles with an infected crop, ascending.
function Threats.blightTiles(world)
  local tiles = {}
  for i in pairs(state(world).blight) do
    if Crops.hasCropAt(world, i) then
      tiles[#tiles + 1] = i
    end
  end
  table.sort(tiles)
  return tiles
end

-- One day of a spreading disease (at the threat's hour). The stream draws the same rolls whatever the guard.
local function spreadDay(world, e, d)
  local s, cfg, rng = state(world), d.spread, world:rng("threats")
  local wet = Weather.isRaining(world)
  local weather = wet and 1 or cfg.dryFactor
  local strength = Threats.strength(world)
  local guard = Threats.guard(world, e.id)
  local infected = Threats.blightTiles(world)
  local fresh = {}
  for _, i in ipairs(infected) do
    local age = s.blight[i] + 1
    if age >= cfg.killDays then
      s.blight[i] = nil
      Crops.destroy(world, i, e.id)
      e.lost = e.lost + 1
    else
      s.blight[i] = age
      if not Crops.isRipeAt(world, i) then
        Crops.setBack(world, i, cfg.setback, e.id)
      end
    end
  end
  for i in pairs(s.blight) do
    if not Crops.hasCropAt(world, i) then
      s.blight[i] = nil -- pulled, harvested or lost to something else
    end
  end
  local grid = world.state.grid
  for _, i in ipairs(infected) do
    if s.blight[i] then
      local x, y = Grid.coords(grid, i)
      for _, dir in ipairs(ORTHO) do
        local nx, ny = x + dir[1], y + dir[2]
        if Grid.inBounds(grid, nx, ny) then
          local j = Grid.index(grid, nx, ny)
          if Crops.hasCropAt(world, j) and s.blight[j] == nil and not fresh[j] then
            local chance =
              math.min(1, cfg.spreadChance * weather * strength * (1 + cfg.pressureWeight * Soil.pressure(world, j)))
            local roll = rng:float()
            if roll < chance * (1 - guard) then
              fresh[j] = true
              e.damaged = e.damaged + 1
            elseif roll < chance then
              e.saved = e.saved + 1
            end
          end
        end
      end
    end
  end
  for j in pairs(fresh) do
    s.blight[j] = 0
  end
  -- The first infection: a roll a day until it breaks out, then the crop it lands on is chosen.
  local broke = false
  if not e.struck then
    local chance = math.min(1, cfg.seedChance * weather * strength)
    local roll, pick = rng:float(), rng:float()
    local planted = Crops.plantedTiles(world)
    if roll < chance and #planted > 0 then
      local j = planted[math.min(#planted, math.floor(pick * #planted) + 1)]
      s.blight[j] = 0
      e.damaged = e.damaged + 1
      e.struck = true
      broke = true
    end
  end
  if broke then
    world.events:emit("threat.struck", { threat = e.id, hit = 1, lost = e.lost, damaged = e.damaged, saved = e.saved })
  end
end

-- One tick of drought: extra drying, and crops left dry too long wither.
local function droughtTick(world, e, d, dt)
  local s = state(world)
  local rate = d.drought.dryRate * Threats.strength(world) * (1 - Threats.guard(world, e.id))
  Crops.evaporate(world, rate * dt / world.tuning.time.dayLength)
  local hours = dt / Calendar.hourLength(world)
  local dry = {}
  for _, i in ipairs(Crops.plantedTiles(world)) do
    if Crops.needsWaterAt(world, i) then
      local t = (s.dry[i] or 0) + hours
      if t >= d.drought.witherHours then
        Crops.destroy(world, i, e.id)
        e.lost = e.lost + 1
      else
        dry[i] = t
      end
    end
  end
  s.dry = dry
end

local function finish(world, e)
  local s, cfg = state(world), world.tuning.threats
  e.status = "done"
  s.dry = {}
  if def(world, e.id).spread then
    s.blight = {} -- the wet spell ends and the infection with it
  end
  local history = s.history
  history[#history + 1] = {
    year = Calendar.now(world).year,
    id = e.id,
    struck = e.struck,
    lost = e.lost,
    damaged = e.damaged,
    saved = e.saved,
  }
  while #history > cfg.historyLimit do
    table.remove(history, 1)
  end
  world.events:emit("threat.ended", {
    threat = e.id,
    struck = e.struck,
    lost = e.lost,
    damaged = e.damaged,
    saved = e.saved,
    broken = e.broken,
  })
end

local function start(world, e, d)
  e.status, e.warned = "active", true
  world.events:emit("threat.started", { threat = e.id, days = e.days })
  if d.drought then
    -- A drought strikes as it starts (that is what writes its note).
    e.struck = true
    world.events:emit("threat.struck", { threat = e.id, hit = 0, lost = 0, damaged = 0, saved = 0 })
  end
end

local function step(world, e, now, dt)
  local d = def(world, e.id)
  local last = e.start + e.days - 1
  if e.status == "waiting" then
    if not e.warned and now.day >= e.start - Threats.warnLead(world) and now.day < e.start then
      e.warned = true
      world.events:emit("threat.warned", { threat = e.id, days = e.start - now.day })
    end
    -- A drought sets in at its hour; the others are "on" (forecast: today) from the start of the day.
    if now.day > e.start or (now.day == e.start and (not d.drought or now.hour >= d.hour)) then
      start(world, e, d)
    else
      return
    end
  end
  if now.day > last then
    finish(world, e)
    return
  end
  if d.drought then
    if Weather.isRaining(world) then
      e.broken = true
      finish(world, e)
      return
    end
    droughtTick(world, e, d, dt)
  elseif d.spread then
    if now.hour >= d.hour and e.rollDay < now.day then
      e.rollDay = now.day
      spreadDay(world, e, d)
    end
  elseif now.hour >= d.hour and e.rollDay < now.day then
    e.rollDay = now.day
    local strikes = true
    if d.strike then
      local roll = world:rng("threats"):float()
      strikes = roll < Threats.strikeChance(world, e.id, 0)
    end
    if strikes then
      applyDamage(world, e, d)
      finish(world, e)
    end
  end
end

function Threats.init(world)
  local s = world.state.threats or {}
  world.state.threats = s
  -- A fresh run starts empty; this year's schedule is rolled now.
  s.years = s.years or {}
  s.dry = s.dry or {}
  s.blight = s.blight or {}
  s.history = s.history or {}
  Threats.schedule(world)
end

function Threats.tick(world, dt)
  local now = Calendar.now(world)
  for _, e in ipairs(Threats.schedule(world, now.year)) do
    if e.status ~= "done" then
      step(world, e, now, dt)
    end
  end
end

return Threats
