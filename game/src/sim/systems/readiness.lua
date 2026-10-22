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
local Felling = require("src.sim.systems.felling")
local Footing = require("src.sim.systems.footing")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Shelter = require("src.sim.systems.shelter")
local Sleep = require("src.sim.systems.sleep")
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
  local insulation = Shelter.nightInsulation(world) -- D82, D149: the shelter you sleep in and the clothes you wear keep part of the cold out
  local idx, day, seenFrozen = now.seasonIndex, now.dayOfSeason, false
  local front = Weather.frontFactor(world) -- a cold front on tonight (D190) is known; no other night's can be
  for _ = 1, #time.seasons + 1 do
    local season = time.seasons[idx]
    local frozen = Weather.isFrozenSeason(world, season)
    if seenFrozen and not frozen then
      break
    end
    for d = day, time.daysPerSeason do
      local need, sure = Weather.expectedWarmthNeed(world, season, d)
      need = need * insulation * front
      front = 1
      -- D101 (#175): electric heaters pay a night first (never more than the night needs); fuel pays the rest.
      local electric = math.min(need, Power.heatPerNight(world, season))
      nights[#nights + 1] = { need = need - electric, electric = electric, winter = frozen }
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

--- Warmth to hold on to (D75, D104: the automatic keep target for wood): every night from tonight to the
--- end of the winters ahead (tuning.food.keepWinters, one more during a winter), so a thaw never
--- turns the woodpile into surplus. Cautious where the forecast is silent: an unrevealed severity counts
--- as the highest that year can roll, and an unrevealed cold snap as the longest one. 0 when winters
--- never freeze.
---
--- `winters` overrides how many winters are counted (1 = to the end of the winter now on or coming, the wood still needed
--- "to reach the end of winter"); omitted, the automatic keep's horizon above.
function Readiness.warmthAhead(world, winters)
  local time, cfg = world.tuning.time, world.tuning.weather
  local now = Calendar.now(world)
  local forecast = Weather.forecast(world)
  winters = winters or (world.tuning.food.keepWinters + (Weather.isFrozen(world) and 1 or 0))
  local idx, day, year = now.seasonIndex, now.dayOfSeason, now.year
  local total, inWinter, done = 0, false, 0
  for _ = 1, (winters + 1) * #time.seasons + 1 do
    local season = time.seasons[idx]
    local frozen = Weather.isFrozenSeason(world, season)
    if inWinter and not frozen then
      done = done + 1
      if done >= winters then
        break
      end
    end
    inWinter = frozen
    local peak = 0 -- the season's hardest night at severity 1: where an unannounced cold snap could land
    local known = year == now.year
    local severity = Weather.severityBound(world, year) -- the roll's top end (the Great Winter may top it, D117)
    if frozen and known and forecast.severity then
      severity = forecast.severity
    end
    for d = day, time.daysPerSeason do
      local base = Weather.baseWarmth(world, season, d)
      peak = math.max(peak, base)
      local need = base
      if frozen then
        need = base * severity
        if
          known
          and forecast.snapStart
          and forecast.snapDays
          and d >= forecast.snapStart
          and d < forecast.snapStart + forecast.snapDays
        then
          need = need * cfg.snapMultiplier
        end
      end
      total = total + need
    end
    if frozen and not (known and forecast.snapDays) then
      -- The longest snap the year can roll (later years add nights, D67), somewhere in the season.
      local grow = world.tuning.threats.winter
      local snap = cfg.snapDaysMax + math.min(grow.maxExtraSnapDays, math.floor(grow.snapDaysPerYear * (year - 1)))
      total = total + peak * severity * snap * (cfg.snapMultiplier - 1)
    end
    if idx == #time.seasons then
      year = year + 1
    end
    idx, day = idx % #time.seasons + 1, 1
  end
  if done == 0 and not inWinter then
    return 0 -- no season ever froze
  end
  return total * Shelter.nightInsulation(world) -- D82, D149: the same accessor as tonight's need
end

--- Winter readiness, or nil when it is not due yet. Returns
---   { frozen, daysAway (days to the freeze, 0 once frozen), verdict = "ready" | "fuel" | "food" | "both",
---     exact (the whole forecast is known), noFire,
---     fuel = { have (warmth in stock), need (warmth through winter's end that fuel must make, after electric), covered (nights), nights, ok,
---              wood (in stock), perNight (wood an average winter night burns), woodNeed (wood to winter's end),
---              felling (Felling.outlook: the limit on wood from trees, #362; nil when no season is limited) },
---     electric = { total (warmth the heaters should make to winter's end), perNight (a winter night) },
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
  local perWood = Needs.warmthPerWood(world)
  local total, covered, left, winterNights = 0, 0, have, 0
  local electricTotal, winterNeed = 0, 0
  local counting = true
  for _, night in ipairs(nights) do
    total = total + night.need
    electricTotal = electricTotal + night.electric
    if night.winter then
      winterNights = winterNights + 1
      winterNeed = winterNeed + night.need
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
    noFire = Needs.heatEfficiency(world) == 0 and total > 0,
    electric = { total = electricTotal, perNight = nights[#nights].electric }, -- warmth heaters should make on a winter night (D101), already taken off fuel.need
    fuel = {
      have = have,
      need = total,
      covered = covered,
      nights = #nights,
      ok = fuelOk,
      wood = Ledger.get(world, Needs.fuelId(world)), -- wood in stock (D104)
      perNight = perWood > 0 and winterNights > 0 and math.ceil(winterNeed / winterNights / perWood - 1e-9) or 0, -- wood an average winter night burns at the forecast severity
      woodNeed = perWood > 0 and math.ceil(total / perWood - 1e-9) or 0, -- wood the nights ahead burn in all
      felling = Felling.outlook(world), -- the winter's allowance of wood from trees (#362): the rest of the fuel must already be stored
    },
    food = { days = foodDays, need = winterNights, ok = foodOk },
  }
end

-- Tonight (D161, #340): the dusk check ------------------------------------------------------------------------------

-- What the night is given to work with, as the Tonight card says it (D187, C1): the word from Events.exposure (low,
-- medium, high; never the points) and what drives it, as names the card can list: the stores that attract animals, how
-- many animals are kept, and the shelter.
local function tonightExposure(world)
  local Events = require("src.sim.systems.events") -- here, not at load: Events reaches Food, which requires this file
  local e = Events.exposure(world)
  local stores = {}
  for _, id in ipairs(e.parts.stores) do
    stores[#stores + 1] = world.registry:get("resources", id).name:lower()
  end
  local guards = {} -- the guards that lower it (D189: the dog), by catalog name
  for _, id in ipairs(e.parts.guards) do
    if world.registry:has("catalog", id) then
      guards[#guards + 1] = world.registry:get("catalog", id).name:lower()
    end
  end
  return { word = e.word, stores = stores, animals = e.parts.animals, shelter = e.parts.shelter, guards = guards }
end

-- The risks the night ahead carries that the player has been told about: { { id = "snap", days }, { id = "front" }, { id = "storm", kind },
-- { id = "sign", threat, line } }. The sign is the night threat framework's dusk sign (D187): set once the threat is drawn.
local function tonightRisks(world)
  local NightThreats = require("src.sim.systems.nightthreats") -- here, not at load (it reaches Events, and so Food)
  local risks = {}
  if Weather.isFrozen(world) then
    if Weather.isColdSnap(world) then
      risks[#risks + 1] = { id = "snap", days = 0 }
    else
      local f = Weather.forecast(world)
      local ahead = f.snapStart and f.snapDays and f.snapStart - Calendar.now(world).dayOfSeason
      if ahead and ahead >= 1 and ahead <= world.tuning.night.snapLookDays then
        risks[#risks + 1] = { id = "snap", days = ahead }
      end
    end
  end
  if Weather.frontForecast(world, NightThreats.scale(world, world.registry:get("night_threats", "cold_front"))) then
    risks[#risks + 1] = { id = "front" } -- weather sense: tonight's cold front is on the forecast before the dusk sign (D190)
  end
  if Weather.threat(world) > 1 then -- 1 is an ordinary night; storms and wind raise it
    risks[#risks + 1] = { id = "storm", kind = Weather.kind(world) }
  end
  local sign = NightThreats.sign(world)
  if sign then
    risks[#risks + 1] = { id = "sign", threat = sign.id, line = sign.line }
  end
  return risks
end

--- Should the Tonight card open by itself now? Two answers: `due` (it is the evening: from `tuning.night.duskLeadHours`
--- before sunset until bedtime) and `leads` (tonight is the pressing goal: until Footing is earned, and again while
--- it is slipped; D162). Cheap, so the scene can ask every frame.
function Readiness.tonightDue(world)
  local sunrise, sunset = Calendar.daylight(world)
  local hour = Calendar.now(world).hour
  local due = hour >= math.max(sunrise, sunset - world.tuning.night.duskLeadHours) and not Sleep.isBedtime(world)
  return due, Footing.tonightLeads(world)
end

--- The dusk check (D161, #340), the one accessor behind the Tonight card: what tonight needs and what the
--- homestead has, with the same figures the HUD chips, the alerts and the winter readiness read. Pure reads.
---   { hour, sunset (hour), due (the card opens by itself: from `tuning.night.duskLeadHours` before sunset to bedtime),
---     leads (see Readiness.tonightDue),
---     warmth = { need (Needs.warmthNeeded), electric (made by heaters), fireNeed (left for the fire), wood (stock),
---                felling (Felling.outlook, #362: the season's allowance of wood from trees; nil when none),
---                perNight (wood tonight's fire burns), nights (wood stock / that need; math.huge when none is
---                needed), noFire (a fire is needed but none is placed), level (0 fine, 1 amber, 2 red, as the chip) },
---     food = { days (Needs.foodDays), calories, need (a day's), level },
---     water = { perDay, days, stock, cistern, canteen, thirstDays, level },
---     shelter = { id, name, insulation, heat (a heat source is placed) } (id nil with no shelter placed),
---     exposure = { word = "low" | "medium" | "high", stores (names in stock that attract animals), animals (kept),
---                  shelter = id, guards (names of the owned guards that lower it, such as the farm dog) } (the word only: the points stay inside Events.exposure, D187),
---     risks = { { id = "snap", days } | { id = "front" } | { id = "storm", kind } | { id = "sign", threat, line } }, gaps (rows at amber or worse) }
function Readiness.tonight(world)
  local Alerts = require("src.sim.systems.alerts") -- here, not at load: Alerts reaches Food, which requires this file
  local now = Calendar.now(world)
  local _, sunset = Calendar.daylight(world)
  local due, leads = Readiness.tonightDue(world)
  local outlook, water = Needs.woodOutlook(world), Needs.waterOutlook(world)
  local need = Needs.warmthNeeded(world)
  local electric = math.min(need, Power.heatPerNight(world, now.season))
  local shelterId = Shelter.id(world)
  local shelterDef = shelterId and world.registry:get("objects", shelterId)
  local warmth = {
    need = need,
    electric = electric,
    fireNeed = need - electric,
    wood = outlook.stock,
    perNight = outlook.perNight,
    nights = outlook.nights,
    noFire = outlook.noFire,
    level = (Alerts.level(world, "fuel")),
    felling = Felling.outlook(world), -- the limit on wood from trees (#362): nil when no season is limited
  }
  local food = {
    days = Needs.foodDays(world),
    calories = Needs.calories(world),
    need = world.tuning.needs.dailyCalories,
    level = (Alerts.level(world, "food")),
  }
  local drink = {
    perDay = water.perDay,
    days = water.days,
    stock = water.stock,
    cistern = water.cistern,
    canteen = water.canteen,
    thirstDays = water.thirstDays,
    level = (Alerts.level(world, "drink")),
  }
  local gaps = 0
  for _, row in ipairs({ warmth, food, drink }) do
    if row.level > 0 then
      gaps = gaps + 1
    end
  end
  return {
    hour = now.hour,
    sunset = sunset,
    due = due,
    leads = leads,
    warmth = warmth,
    food = food,
    water = drink,
    shelter = {
      id = shelterId,
      name = shelterDef and shelterDef.name,
      insulation = Shelter.nightInsulation(world),
      heat = Needs.heatEfficiency(world) > 0,
    },
    exposure = tonightExposure(world),
    risks = tonightRisks(world),
    gaps = gaps,
  }
end

return Readiness
