-- Words for the winter forecast (GDD §4.1): the sim knows numbers, the player reads a few words.

local Weather = require("src.sim.systems.weather")

local Forecast = {}

local SEVERITY = { "mild", "hard", "brutal" }
local TIMING = { "early", "mid-winter", "late" }

local function timing(world, day)
  local third = math.max(1, world.tuning.time.daysPerSeason / 3)
  return TIMING[math.min(3, math.floor((day - 1) / third) + 1)]
end

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

--- Short forecast line from whatever has been revealed, or nil if nothing has.
function Forecast.summary(world)
  local f = Weather.forecast(world)
  if not f.severity then
    return nil
  end
  local parts = { SEVERITY[Weather.severityLevel(world, f.severity)] .. " winter" }
  if f.snapStart then
    local snap = "cold snap " .. timing(world, f.snapStart)
    if f.snapDays then
      snap = snap .. " (" .. plural(f.snapDays, "night") .. ")"
    end
    parts[#parts + 1] = snap
  end
  return table.concat(parts, ", ")
end

--- The toast for a newly revealed forecast piece.
function Forecast.news(world, piece)
  local f = Weather.forecast(world)
  if piece == 1 then
    return "Forecast: a " .. SEVERITY[Weather.severityLevel(world, f.severity)] .. " winter ahead"
  elseif piece == 2 then
    return "Forecast: a cold snap, " .. timing(world, f.snapStart)
  end
  return "Forecast: the cold snap lasts " .. plural(f.snapDays, "night")
end

return Forecast
