-- Calendar (GDD §4.1, §7.1): time of day, day, season, year.
-- State: world.state.calendar = { elapsed = game seconds since the run began, day = last day seen }.
-- Emits "calendar.newDay" { day, season, year } and "calendar.newSeason" { season, year }.

local Calendar = {}

function Calendar.init(world)
  world.state.calendar = world.state.calendar or { elapsed = 0, day = 1 }
end

--- Days elapsed as a float, counting from midnight of day 1.
local function dayFloat(world)
  local time = world.tuning.time
  return world.state.calendar.elapsed / time.dayLength + time.startHour / 24
end

--- Snapshot of the date: { day, dayOfSeason, season, seasonIndex, year, hour, timeOfDay }.
function Calendar.now(world)
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
