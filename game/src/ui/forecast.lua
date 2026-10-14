-- Words for the winter forecast (GDD §4.1): the sim knows numbers, the player reads a few words.

local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Threats = require("src.sim.systems.threats")
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
  local word = SEVERITY[Weather.severityLevel(world, f.severity)]
  -- The Great Winter (D117) is named in the warning.
  local parts = { f.great and string.format(world.tuning.ui.greatWinter.summaryHead, word) or (word .. " winter") }
  if f.snapStart then
    local snap = "cold snap " .. timing(world, f.snapStart)
    if f.snapDays then
      snap = snap .. " (" .. plural(f.snapDays, "night") .. ")"
    end
    parts[#parts + 1] = snap
  end
  return table.concat(parts, ", ")
end

local function label(world, kind)
  return world.tuning.weather.kinds[kind].label
end

--- Today's weather and the days ahead the player can see, as a short line:
--- "Rain, then Clear, Cloudy, Cloudy".
function Forecast.weather(world)
  local list = Weather.outlook(world)
  local parts = {}
  for n = 2, #list do
    parts[#parts + 1] = label(world, list[n].kind)
  end
  local line = label(world, list[1].kind)
  if #parts > 0 then
    line = line .. ", then " .. table.concat(parts, ", ")
  end
  return line
end

--- Toast for a new day's weather when it matters to the work, or nil.
function Forecast.weatherNews(world, kind)
  if kind == "rain" then
    return "Rain today: the crops water themselves."
  elseif kind == "storm" then
    return "Storm today. Rain on the crops, wind in the turbines."
  elseif kind == "windy" then
    return "A windy day: good for turbines."
  end
  return nil
end

-- Threats (D67) -----------------------------------------------------------------------------

local function when(days)
  if days <= 0 then
    return "today"
  elseif days == 1 then
    return "tomorrow"
  end
  return "in " .. days .. " days"
end

-- " · Row covers help" when the countermeasure is known but not owned, " · covered" when owned.
local function counterHint(world, id)
  local counter = world.registry:get("threats", id).counter
  if Inventory.hasEquipment(world, counter) then
    return " · covered"
  elseif Journal.isKnown(world, counter) then
    return " · " .. world.registry:get("catalog", counter).name .. " helps"
  end
  return ""
end

--- Forecast pills for threats the player knows about: { { text, active } } soonest first.
--- "Locusts in 2 days · Row covers helps", "Hail season, 2 days left · hail likely tomorrow".
function Forecast.threats(world)
  local lines = {}
  for _, t in ipairs(Threats.outlook(world)) do
    local text
    if not t.active then
      text = t.name .. " " .. when(t.inDays)
    elseif world.registry:get("threats", t.id).drought then
      text = string.format("Drought, %s left: water often", plural(t.daysLeft, "day"))
    elseif t.risk then
      text = string.format("%s season, %s left", t.name, plural(t.daysLeft, "day"))
    else
      text = t.name .. " today"
    end
    if t.risk and t.risk >= world.tuning.threats.likelyAt then
      text = text .. " · " .. t.name:lower() .. " likely " .. when(t.riskIn)
    end
    lines[#lines + 1] = { text .. counterHint(world, t.id), t.active }
  end
  return lines
end

--- Toast when a threat is announced.
function Forecast.threatWarning(world, id, days)
  local def = world.registry:get("threats", id)
  local text = string.format("Warning: %s %s. %s", def.name:lower(), when(days), def.line)
  local counter = world.registry:get("catalog", def.counter)
  if Inventory.hasEquipment(world, def.counter) then
    text = text .. " " .. counter.name .. " is ready."
  elseif Journal.isKnown(world, def.counter) then
    text = text .. " " .. counter.name .. " would help."
  end
  return text
end

--- Toast when a threat with a span begins (hail season, drought), or nil.
function Forecast.threatStarted(world, id)
  local def = world.registry:get("threats", id)
  if def.strike then
    return def.name .. " season: storms may bring " .. def.name:lower()
  elseif def.drought then
    return "Drought: the beds dry out fast. Keep them watered."
  end
  return nil
end

--- The summary toast when a threat is over.
function Forecast.threatSummary(world, e)
  local def = world.registry:get("threats", e.threat)
  if not e.struck then
    return string.format("The %s season passed without %s", def.name:lower(), def.name:lower())
  end
  local parts = {}
  if e.lost > 0 then
    parts[#parts + 1] = plural(e.lost, "crop") .. " lost"
  end
  if e.damaged > 0 then
    parts[#parts + 1] = plural(e.damaged, "crop") .. " knocked back"
  end
  if e.saved > 0 then
    parts[#parts + 1] = e.saved .. " saved by " .. world.registry:get("catalog", def.counter).name:lower()
  end
  local head = e.broken and (def.name .. " broken by rain") or (def.name .. " passed")
  if #parts == 0 then
    return head .. ": no harm done"
  end
  return head .. ": " .. table.concat(parts, ", ")
end

--- The toast for a newly revealed forecast piece (nil when there is none to show: the Great Winter is
--- announced in one toast, D117, and the pill carries the rest).
function Forecast.news(world, piece)
  local f = Weather.forecast(world)
  if f.great then
    return piece == 1 and world.tuning.ui.greatWinter.news or nil
  end
  if piece == 1 then
    return "Forecast: a " .. SEVERITY[Weather.severityLevel(world, f.severity)] .. " winter ahead"
  elseif piece == 2 then
    return "Forecast: a cold snap, " .. timing(world, f.snapStart)
  end
  return "Forecast: the cold snap lasts " .. plural(f.snapDays, "night")
end

return Forecast
