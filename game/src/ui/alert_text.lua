-- Plain words for the warnings of D70: low food, fuel and health (#157), a crop that will not ripen
-- before winter (#165), and winter readiness (#166). The sim knows numbers; this file only turns
-- them into sentences and colours. Thresholds are not decided here: they come from Alerts.level.

local Alerts = require("src.sim.systems.alerts")
local Crops = require("src.sim.systems.crops")
local Ledger = require("src.sim.systems.ledger")
local Readiness = require("src.sim.systems.readiness")
local Weather = require("src.sim.systems.weather")
local theme = require("src.ui.theme")

local AlertText = {}

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

--- Chip colour for a level (0 fine = nil so the chip keeps its normal colour, 1 amber, 2 red).
function AlertText.levelColor(level)
  if level >= 2 then
    return theme.colors.danger
  elseif level == 1 then
    return theme.colors.accent
  end
  return nil
end

--- The chip colour for "food", "fuel" or "condition" right now.
function AlertText.chipColor(world, kind)
  return AlertText.levelColor((Alerts.level(world, kind)))
end

--- The toast for an "alert.raised" event.
function AlertText.toast(e)
  if e.kind == "food" then
    if e.value < 0.05 then
      return "Out of food. Harvest, fish or buy canned food"
    end
    return string.format("Food is low: %.1f days left. Harvest, fish or buy canned food", e.value)
  elseif e.kind == "fuel" then
    if e.noFire then
      return "No fire to burn firewood in. Place a campfire or stove"
    elseif e.value < 1 then
      return string.format("Not enough firewood for tonight (%.1f nights). Chop wood or buy firewood", e.value)
    end
    return string.format("Firewood is low: %.1f nights left. Chop wood or buy firewood", e.value)
  elseif e.kind == "animals" then
    if e.value < 0.05 then
      return "The animals are out of feed. Buy chicken feed or hay"
    end
    return string.format("Animal feed is low: %.1f days left. Buy chicken feed or hay", e.value)
  end
  local hp = math.floor(e.value + 0.5)
  if e.level >= 2 then
    return string.format("Health is low (%d). Eat and keep warm to recover", hp)
  end
  return string.format("Health is falling (%d). Eat and keep warm", hp)
end

--- "Won't ripen before winter: Potato needs 5 watered days, 3 left", or nil when the crop will ripen.
function AlertText.frost(world, cropId)
  local risk = Crops.frostRisk(world, cropId)
  if not risk then
    return nil
  end
  local name = world.registry:get("crops", cropId).name
  if risk.level == "late" then
    return string.format("Won't ripen before winter: %s needs %s, %d left", name, plural(risk.growDays, "watered day"), risk.daysLeft)
  end
  return string.format("Cutting it close: %s needs %s, %d left before winter", name, plural(risk.growDays, "watered day"), risk.daysLeft)
end

--- A line for the tile card of a crop in the ground, or nil: how long it has against the freeze.
function AlertText.cropFrostLine(world, crop)
  if Weather.isFrozen(world) then
    return nil
  end
  local left = Weather.daysToFreeze(world)
  if left == math.huge then
    return nil
  end
  if Crops.isMature(crop) then
    return string.format("Frost in %dd: harvest", left)
  end
  local need = math.ceil(Crops.daysToRipe(world, crop) - 1e-9)
  if need > left then
    return string.format("Frost in %dd: too late", left)
  end
  return string.format("Frost in %dd", left)
end

-- Winter readiness (#166) ---------------------------------------------------------------------

local VERDICT_WORDS = {
  ready = "ready",
  fuel = "short on firewood",
  food = "short on food",
  both = "short on firewood and food",
}

--- The pill text and colour for the HUD, or nil when the indicator is not due.
function AlertText.readinessPill(world)
  local r = Readiness.winter(world)
  if not r then
    return nil
  end
  local color = theme.colors.text
  if r.verdict ~= "ready" then
    color = r.frozen and theme.colors.danger or theme.colors.accent
  end
  return "Winter: " .. VERDICT_WORDS[r.verdict], color, r
end

--- The expanded card: a headline and the lines under it.
function AlertText.readinessCard(world)
  local r = Readiness.winter(world)
  if not r then
    return nil
  end
  local lines = {}
  if r.frozen then
    lines[#lines + 1] = "Winter has begun."
  else
    lines[#lines + 1] = string.format("The ground freezes in %s.", plural(r.daysAway, "day"))
  end
  lines[#lines + 1] = string.format(
    "Fuel: your stock carries %d of the next %d nights (warmth %.0f of %.0f).",
    r.fuel.covered,
    r.fuel.nights,
    r.fuel.have,
    r.fuel.need
  )
  if r.noFire then
    lines[#lines + 1] = "No fire is placed, so fuel does nothing yet. Place a campfire or stove."
  end
  lines[#lines + 1] = string.format("Food: %.1f days in stock; winter needs %d.", r.food.days, r.food.need)
  if not r.exact then
    lines[#lines + 1] = "The forecast is still coming in, so the real need may be higher."
  end
  local advice = {}
  if not r.fuel.ok then
    if Ledger.isFull(world, "firewood") or Ledger.isFull(world, "seasoned_firewood") then
      advice[#advice + 1] = "firewood storage is full: a woodshed holds more"
    else
      advice[#advice + 1] = "chop wood or buy firewood"
    end
  end
  if not r.food.ok then
    advice[#advice + 1] = "harvest, fish and keep food for winter in the Pantry"
  end
  if #advice > 0 then
    lines[#lines + 1] = "To do: " .. table.concat(advice, "; ") .. "."
  end
  return "Winter: " .. VERDICT_WORDS[r.verdict], table.concat(lines, "\n"), r
end

--- The toast at the start of autumn (D70), or nil when readiness is not due.
function AlertText.autumnToast(world)
  local r = Readiness.winter(world)
  if not r then
    return nil
  end
  return string.format(
    "Autumn: winter in %s. Fuel carries %d of %d nights, food %.0f days (need %d)",
    plural(r.daysAway, "day"),
    r.fuel.covered,
    r.fuel.nights,
    r.food.days,
    r.food.need
  )
end

return AlertText
