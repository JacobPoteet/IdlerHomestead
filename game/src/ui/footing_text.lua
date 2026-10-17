-- Plain words for the one-time "Footing gained" card (D162, #341, docs/PLAN_DEPTH.md §3.2). Pure: it turns
-- Footing.checks and the tuning into the same card model the Tonight card draws (src/ui/tonight_card.lua), so the
-- card is a panel in the Tonight card's place that never blocks input. The levels are all 0 ("Held"): the card says
-- what earned Footing and what would slip it.

local FootingText = {}

FootingText.title = "Footing"
FootingText.subtitle = "Gained"
FootingText.stamp = "Footing gained"
FootingText.logLine = "Footing: warm, fed and watered. The season is the goal now."
FootingText.slippedLine = "Footing slipped: build the reserves back up."
FootingText.regainedLine = "Footing is back."

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

-- A whole count, or one decimal at most; "plenty" for a need that never comes (math.huge).
local function figure(x)
  if x == math.huge then
    return nil
  end
  local rounded = math.floor(x * 10) / 10
  if rounded == math.floor(rounded) then
    return string.format("%d", rounded)
  end
  return string.format("%.1f", rounded)
end

local LABELS = { shelter = "Shelter", water = "Water", fuel = "Fuel", food = "Food" }

local function rowText(check)
  local n = figure(check.have)
  if check.id == "shelter" then
    return "A shelter with a fire to keep it warm."
  elseif check.id == "water" then
    return string.format("%s of drinking water in hand.", plural(tonumber(n) or 0, "day"))
  elseif check.id == "fuel" then
    return n and string.format("%s of wood in stock.", plural(tonumber(n), "night")) or "No fire needed these nights."
  end
  return string.format("%s of food in stock.", plural(tonumber(n) or 0, "day"))
end

--- The card as data (TonightText.build's shape): { title, subtitle, summary, summaryLevel, rows, notes }.
--- `checks` is Footing.checks(world), `cfg` is tuning.night.footing.
function FootingText.build(checks, cfg)
  local rows = {}
  for _, c in ipairs(checks) do
    rows[#rows + 1] = { id = c.id, label = LABELS[c.id], level = 0, word = "Held", text = rowText(c) }
  end
  return {
    title = FootingText.title,
    subtitle = FootingText.subtitle,
    summary = FootingText.stamp,
    summaryLevel = 0,
    rows = rows,
    notes = {
      {
        text = "You held all four for "
          .. plural(cfg.streakNights, "night")
          .. " running. Tonight is no longer the whole goal: the season is.",
      },
      {
        text = string.format(
          "If wood falls under %s or food under %s, Footing slips and the Tonight card comes back. Keep the reserves up for %s to get it back.",
          plural(cfg.slipFuelNights, "night"),
          plural(cfg.slipFoodDays, "day"),
          plural(cfg.regainNights, "night")
        ),
        dim = true,
      },
    },
  }
end

return FootingText
