-- Plain words for the Tonight card (D161, #340, docs/PLAN_DEPTH.md §3.1). Pure: it turns Readiness.tonight and
-- Dusk.fixes into the card's rows, so tests can check the numbers without a window. A level is a word as well as a
-- colour (Fine, Low, Short), so the card does not lean on colour alone.

local theme = require("src.ui.theme")

local TonightText = {}

TonightText.title = "Tonight"
TonightText.close = "Close"
TonightText.stamp = "Tonight"
TonightText.ready = "Ready for the night"

local LEVEL_WORD = { [0] = "Fine", "Low", "Short" }

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

-- "3" for a whole number, "2.5" for a part, one decimal at most.
local function figure(x)
  local rounded = math.floor(x * 10 + 0.5) / 10
  if rounded == math.floor(rounded) then
    return string.format("%d", rounded)
  end
  return string.format("%.1f", rounded)
end

--- The colour a level is drawn in.
function TonightText.color(level)
  if level >= 2 then
    return theme.colors.danger
  elseif level == 1 then
    return theme.colors.accent
  end
  return theme.colors.text
end

--- The fix button's label.
function TonightText.fixLabel(fix)
  if fix.id == "chop" then
    if fix.queued then
      return string.format("Marked to chop: %s", plural(fix.count, "tree"))
    end
    return string.format("Chop %s (about %s wood)", plural(fix.count, "tree"), figure(fix.wood))
  elseif fix.id == "place_fire" then
    return "Place a campfire"
  elseif fix.id == "buy_wood" then
    return "Buy wood in town"
  elseif fix.id == "fish" then
    return "Ask the routine to fish"
  elseif fix.id == "open_pantry" then
    return "Open the Pantry"
  elseif fix.id == "fill" then
    return "Fill the canteen"
  elseif fix.id == "find_water" then
    return "Find water: wells in the Catalog"
  end
  return fix.id
end

--- The toast after a fix was tapped; `result` is what Dusk.apply returned after its success flag.
function TonightText.fixToast(fix, ok, result)
  if not ok then
    return "Nothing to do there just now"
  elseif fix.id == "chop" then
    return string.format("Marked %s to chop", plural(result, "tree"))
  elseif fix.id == "fish" then
    return "The routine will fish first"
  elseif fix.id == "fill" then
    return result
  end
  return nil
end

local function warmthRow(w)
  local text
  if w.need <= 0 then
    text = "No fire needed tonight."
  elseif w.noFire then
    text = string.format("Tonight needs %s warmth and no fire is placed.", figure(w.need))
  else
    if w.fireNeed <= 0 then
      text = string.format("Tonight needs %s warmth; the heaters make it all.", figure(w.need))
    else
      text = string.format(
        "Tonight needs %s warmth: %s wood. You have %s wood, %s.",
        figure(w.need),
        figure(w.perNight),
        figure(w.wood),
        w.nights == math.huge and "enough"
          or string.format("%s covered", plural(math.floor(w.nights * 10) / 10, "night"))
      )
    end
  end
  return text
end

local function foodRow(f)
  if f.days >= 1 then
    return string.format("Tomorrow is fed. %s of food in stock.", plural(math.floor(f.days * 10) / 10, "day"))
  end
  return string.format("Not enough for tomorrow: %s of food in stock.", plural(math.floor(f.days * 10) / 10, "day"))
end

local function waterRow(w)
  local text = string.format(
    "%s of drinking water: %s in the cistern, %s in the canteen.",
    plural(math.floor(w.days * 10) / 10, "day"),
    figure(w.cistern),
    figure(w.canteen)
  )
  if w.thirstDays > 0 then
    text = "Thirsty. " .. text
  end
  return text
end

local function exposureLine(e)
  if not e.level then
    return "Exposure: no shelter placed."
  end
  return string.format("Exposure: %s (a rough guess for now).", e.level)
end

local function riskLines(risks)
  if #risks == 0 then
    return { "Nothing on the forecast beyond the cold." }
  end
  local lines = {}
  for _, r in ipairs(risks) do
    if r.id == "snap" then
      lines[#lines + 1] = r.days == 0 and "A cold snap tonight: the fire burns more."
        or string.format("A cold snap in %s.", plural(r.days, "day"))
    else
      lines[#lines + 1] =
        string.format("%s tonight: more risk to the animals and the fields.", (r.kind:gsub("^%l", string.upper)))
    end
  end
  return lines
end

--- The card as data: { title, subtitle, summary, summaryLevel, rows = { { id, label, level, word, text, fix } },
--- notes = { { text, dim } } }. `fixes` is Dusk.fixes for the same `tonight`; each row takes the fix of its gap
--- ({ ... , label }).
function TonightText.build(tonight, fixes)
  local byGap = {}
  for _, fix in ipairs(fixes or {}) do
    fix.label = TonightText.fixLabel(fix)
    byGap[fix.gap] = fix
  end
  local function row(id, label, source, text)
    return {
      id = id,
      label = label,
      level = source.level,
      word = LEVEL_WORD[source.level],
      text = text,
      fix = byGap[id],
    }
  end
  local rows = {
    row("warmth", "Warmth", tonight.warmth, warmthRow(tonight.warmth)),
    row("food", "Food", tonight.food, foodRow(tonight.food)),
    row("water", "Water", tonight.water, waterRow(tonight.water)),
  }
  local shelter = tonight.shelter
  local shelterText = "Shelter: none placed."
  if shelter.id then
    local kept = math.floor((1 - shelter.insulation) * 100 + 0.5) -- the share of the night's cold the bed and the clothes keep out
    shelterText = kept > 0 and string.format("Shelter: %s, %d%% less cold.", shelter.name, kept)
      or string.format("Shelter: %s, no help against the cold.", shelter.name)
  end
  local notes = { { text = shelterText }, { text = exposureLine(tonight.exposure) } }
  for _, line in ipairs(riskLines(tonight.risks)) do
    notes[#notes + 1] = { text = line, dim = #tonight.risks == 0 }
  end
  local worst = 0
  for _, r in ipairs(rows) do
    worst = math.max(worst, r.level)
  end
  local subtitle
  if tonight.hour < tonight.sunset then
    local hours = math.ceil(tonight.sunset - tonight.hour - 1e-9)
    subtitle = string.format("Sunset in %s", plural(hours, "hour"))
  else
    subtitle = "After sunset"
  end
  return {
    title = TonightText.title,
    subtitle = subtitle,
    summary = tonight.gaps == 0 and TonightText.ready or string.format("%d to fix", tonight.gaps),
    summaryLevel = worst,
    rows = rows,
    notes = notes,
  }
end

return TonightText
