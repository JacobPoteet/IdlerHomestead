-- Winter readiness (D70, #166, GDD §9.3): are the fuel and the food in stock enough for the winter
-- ahead? Pure reads: the stock from Needs, the need from the forecast through
-- Weather.expectedWarmthNeed (so it uses only what the player has been told), the length of winter
-- from the calendar. No state and no numbers of its own beyond tuning.alerts.readinessLeadDays.
--
-- Fuel is judged night by night from tonight to the last night of winter: the stock pays each night's
-- need in turn and `covered` counts the nights it carries. Food is judged against the nights of
-- winter still to come, since nothing grows in the cold; the days before the freeze can still be fed
-- by the harvest.

local Calendar = require("src.sim.systems.calendar")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")
local Weather = require("src.sim.systems.weather")

local Readiness = {}

--- Is the indicator due? From `readinessLeadDays` before the first frozen season to the thaw.
function Readiness.active(world)
  if Weather.isFrozen(world) then
    return true
  end
  return Weather.daysToFreeze(world) <= world.tuning.alerts.readinessLeadDays
end

-- The nights from tonight to the end of winter: { { need, winter }... } and whether every winter
-- night's need is exact. Empty when winters never freeze.
local function nightsAhead(world)
  local time = world.tuning.time
  local now = Calendar.now(world)
  local nights, exact = {}, true
  local insulation = Shelter.insulation(world) -- D82: the shelter you sleep in keeps part of the cold out
  local idx, day, seenFrozen = now.seasonIndex, now.dayOfSeason, false
  for _ = 1, #time.seasons + 1 do
    local season = time.seasons[idx]
    local frozen = Weather.isFrozenSeason(world, season)
    if seenFrozen and not frozen then
      break
    end
    for d = day, time.daysPerSeason do
      local need, sure = Weather.expectedWarmthNeed(world, season, d)
      nights[#nights + 1] = { need = need * insulation, winter = frozen }
      if frozen and not sure then
        exact = false
      end
    end
    seenFrozen = seenFrozen or frozen
    idx, day = idx % #time.seasons + 1, 1
  end
  if not seenFrozen then
    return {}, true
  end
  return nights, exact
end

--- Warmth to hold on to (D75: the automatic keep target for fuel): every night from tonight to the
--- end of the coming winter, and during a winter to the end of the next one as well, so a thaw never
--- turns the woodpile into surplus. Cautious where the forecast is silent: an unrevealed severity counts
--- as the highest that year can roll, and an unrevealed cold snap as the longest one. 0 when winters
--- never freeze.
function Readiness.warmthAhead(world)
  local time, cfg = world.tuning.time, world.tuning.weather
  local now = Calendar.now(world)
  local forecast = Weather.forecast(world)
  local winters = Weather.isFrozen(world) and 2 or 1
  local idx, day, year = now.seasonIndex, now.dayOfSeason, now.year
  local total, inWinter, done = 0, false, 0
  for _ = 1, 2 * #time.seasons + 1 do
    local season = time.seasons[idx]
    local frozen = Weather.isFrozenSeason(world, season)
    if inWinter and not frozen then
      done = done + 1
      if done >= winters then
        break
      end
    end
    inWinter = frozen
    local base = world.tuning.needs.dailyWarmth[season]
    local known = year == now.year
    local severity = cfg.severityMax + cfg.severityPerYear * (year - 1)
    if frozen and known and forecast.severity then
      severity = forecast.severity
    end
    for d = day, time.daysPerSeason do
      local need = base
      if frozen then
        need = base * severity
        if known and forecast.snapStart and forecast.snapDays and d >= forecast.snapStart and d < forecast.snapStart + forecast.snapDays then
          need = need * cfg.snapMultiplier
        end
      end
      total = total + need
    end
    if frozen and not (known and forecast.snapDays) then
      -- The longest snap the year can roll (later years add nights, D67), somewhere in the season.
      local grow = world.tuning.threats.winter
      local snap = cfg.snapDaysMax + math.min(grow.maxExtraSnapDays, math.floor(grow.snapDaysPerYear * (year - 1)))
      total = total + base * severity * snap * (cfg.snapMultiplier - 1)
    end
    if idx == #time.seasons then
      year = year + 1
    end
    idx, day = idx % #time.seasons + 1, 1
  end
  if done == 0 and not inWinter then
    return 0 -- no season ever froze
  end
  return total * Shelter.insulation(world) -- D82: the same accessor as tonight's need
end

--- Winter readiness, or nil when it is not due yet. Returns
---   { frozen, daysAway (days to the freeze, 0 once frozen), verdict = "ready" | "fuel" | "food" | "both",
---     exact (the whole forecast is known), noFire,
---     fuel = { have (warmth in stock), need (warmth through winter's end), covered (nights), nights, ok },
---     food = { days (in stock), need (winter nights still to come), ok } }
function Readiness.winter(world)
  if not Readiness.active(world) then
    return nil
  end
  local nights, exact = nightsAhead(world)
  if #nights == 0 then
    return nil
  end
  local have = Needs.warmthInStock(world)
  local total, covered, left, winterNights = 0, 0, have, 0
  local counting = true
  for _, night in ipairs(nights) do
    total = total + night.need
    if night.winter then
      winterNights = winterNights + 1
    end
    if counting and left >= night.need then
      left = left - night.need
      covered = covered + 1
    else
      counting = false
    end
  end
  local foodDays = Needs.foodDays(world)
  local fuelOk, foodOk = covered == #nights, foodDays >= winterNights
  local verdict = "ready"
  if not fuelOk and not foodOk then
    verdict = "both"
  elseif not fuelOk then
    verdict = "fuel"
  elseif not foodOk then
    verdict = "food"
  end
  return {
    frozen = Weather.isFrozen(world),
    daysAway = Weather.isFrozen(world) and 0 or Weather.daysToFreeze(world),
    verdict = verdict,
    exact = exact,
    noFire = Needs.heatEfficiency(world) == 0,
    fuel = { have = have, need = total, covered = covered, nights = #nights, ok = fuelOk },
    food = { days = foodDays, need = winterNights, ok = foodOk },
  }
end

return Readiness
