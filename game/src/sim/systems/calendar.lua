-- Calendar (GDD §4.1, §7.1): time of day, day, season, year.
-- State: world.state.calendar = { elapsed = game seconds since the run began, day = last day seen }.
-- Emits "calendar.newDay" { day, season, year } and "calendar.newSeason" { season, year }.

local Calendar = {}

function Calendar.init(world)
  local time = world.tuning.time
  local cal = world.state.calendar
  if not cal then
    world.state.calendar = { elapsed = 0, day = 1, dayLength = time.dayLength }
    return
  end
  -- A save written with another day length keeps its date and time of day (D56).
  local written = cal.dayLength
  if written ~= time.dayLength then
    cal.elapsed = cal.elapsed * time.dayLength / written
  end
  cal.dayLength = time.dayLength
end

--- Days elapsed as a float, counting from midnight of day 1.
local function dayFloat(world)
  local time = world.tuning.time
  return world.state.calendar.elapsed / time.dayLength + time.startHour / 24
end

--- Game seconds since the run began (a clock for other systems' timers).
function Calendar.elapsed(world)
  return world.state.calendar.elapsed
end

-- The last snapshot per calendar state table, reused while nothing it depends on has changed (#132):
-- several systems ask for the date on every tick. Weak-keyed, runtime only, never saved.
local nowCache = setmetatable({}, { __mode = "k" })

--- Snapshot of the date: { day, dayOfSeason, season, seasonIndex, year, hour, timeOfDay }.
--- The table is shared by every caller until the clock moves: read it, never write to it.
function Calendar.now(world)
  local time = world.tuning.time
  local cal = world.state.calendar
  local hit = nowCache[cal]
  if
    hit
    and hit.elapsed == cal.elapsed
    and hit.time == time
    and hit.dayLength == time.dayLength
    and hit.startHour == time.startHour
    and hit.daysPerSeason == time.daysPerSeason
  then
    return hit.now
  end
  if not hit then
    hit = {}
    nowCache[cal] = hit
  end
  hit.elapsed, hit.time, hit.dayLength, hit.startHour, hit.daysPerSeason =
    cal.elapsed, time, time.dayLength, time.startHour, time.daysPerSeason
  hit.now = Calendar.compute(world)
  return hit.now
end

--- Calendar.now without the cache: a fresh table.
function Calendar.compute(world)
  local time = world.tuning.time
  local d = dayFloat(world)
  local dayIndex = math.floor(d) -- 0-based
  local seasonsPerYear = #time.seasons
  local seasonCount = math.floor(dayIndex / time.daysPerSeason)
  local seasonIndex = seasonCount % seasonsPerYear + 1
  local timeOfDay = d - dayIndex
  return {
    day = dayIndex + 1,
    dayOfSeason = dayIndex % time.daysPerSeason + 1,
    season = time.seasons[seasonIndex],
    seasonIndex = seasonIndex,
    year = math.floor(seasonCount / seasonsPerYear) + 1,
    hour = timeOfDay * 24,
    timeOfDay = timeOfDay,
  }
end

--- Sunrise and sunset hours for the current season (tuning.time.daylight).
function Calendar.daylight(world)
  local hours = world.tuning.time.daylight[Calendar.now(world).season]
  return hours[1], hours[2]
end

--- Is it dark out? Nights are when the Field Journal studies (GDD §7.1, §8.1).
function Calendar.isNight(world)
  local sunrise, sunset = Calendar.daylight(world)
  local hour = Calendar.now(world).hour
  return hour < sunrise or hour >= sunset
end

--- Game seconds per in-game hour.
function Calendar.hourLength(world)
  return world.tuning.time.dayLength / 24
end

function Calendar.tick(world, dt)
  local cal = world.state.calendar
  cal.elapsed = cal.elapsed + dt
  local now = Calendar.now(world)
  if now.day ~= cal.day then
    local previousSeason = Calendar.seasonOfDay(world, cal.day)
    cal.day = now.day
    world.events:emit("calendar.newDay", { day = now.day, season = now.season, year = now.year })
    if now.seasonIndex ~= previousSeason then
      world.events:emit("calendar.newSeason", { season = now.season, year = now.year })
    end
  end
end

function Calendar.seasonOfDay(world, day)
  local time = world.tuning.time
  return math.floor((day - 1) / time.daysPerSeason) % #time.seasons + 1
end

function Calendar.summarize(world, out)
  local now = Calendar.now(world)
  out.year = now.year
  out.season = now.season
  out.day = now.dayOfSeason
end

return Calendar
