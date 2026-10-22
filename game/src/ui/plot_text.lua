-- The plot preview's words (D200, #384): pure, no drawing. A plot summary is from src/sim/plots.lua.

local PlotText = {}

local TRAITS = { "soil", "water", "wood", "sun" }

--- "Plot A" for the n-th offered plot.
function PlotText.name(tuning, n)
  return tuning.plots.words.plotNames[n] or ("Plot " .. n)
end

--- "Soil Rich · Water Close · Wood Some · Sun Bright".
function PlotText.traits(tuning, plot)
  local words, parts = tuning.plots.words, {}
  for _, id in ipairs(TRAITS) do
    local w = words[id]
    parts[#parts + 1] = w.label .. " " .. w.levels[plot[id]]
  end
  return table.concat(parts, " · ")
end

--- "$4" for money, "6 stone" for anything else, joined with "and" when there are several.
function PlotText.bonus(registry, bonus)
  local ids = {}
  for id in pairs(bonus or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local parts = {}
  for _, id in ipairs(ids) do
    if id == "money" then
      parts[#parts + 1] = string.format("$%d", bonus[id])
    else
      parts[#parts + 1] = string.format("%d %s", bonus[id], registry:get("resources", id).name:lower())
    end
  end
  return table.concat(parts, " and ")
end

--- The risk and reward line: the easy plot says so; a hazard plot names its hazard and the bonus it carries.
function PlotText.tag(registry, tuning, plot)
  local words = tuning.plots.words
  if not plot.hazard then
    return words.easy
  end
  for _, h in ipairs(tuning.plots.hazards) do
    if h.id == plot.hazard then
      return string.format(words.hazard, h.name, h.line, PlotText.bonus(registry, plot.bonus))
    end
  end
  return words.easy
end

return PlotText
