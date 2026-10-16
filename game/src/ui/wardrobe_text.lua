-- The Wardrobe's numbers and words (docs/PLAN_WARDROBE_MENU.md §4 and §5), pure so tests can check them without
-- a window: the signed percent a meter shows and the length of its fill, the state line, the tag beside Wear,
-- the Today and Dawn pills, a locked garment's hint, the detail line and a tile's wrapped name. The words are
-- tuning.ui.wardrobe; garment names and hints are content.

local WardrobeText = {}

local floor = math.floor

--- A fraction as a signed percent: 0.04 -> "+4%", -0.08 -> "-8%", 0.005 -> "+0.5%", 0 -> "0%". A whole number
--- when it is one, else one decimal.
function WardrobeText.percent(v)
  local tenths = floor(math.abs(v) * 1000 + 0.5) -- tenths of a percent
  if tenths == 0 then
    return "0%"
  end
  local sign = v < 0 and "-" or "+"
  if tenths % 10 == 0 then
    return string.format("%s%d%%", sign, tenths / 10)
  end
  return string.format("%s%.1f%%", sign, tenths / 10)
end

--- The length in pixels of a meter's fill for the value `v`: `scale` is the value that fills the half-bar and
--- `halfW` the half-bar's width. Returns the length (never beyond the half, at least 1 for a value that is not
--- zero) and the side it grows on, 1 right (plus) or -1 left (minus); 0, 0 for zero.
function WardrobeText.fill(v, scale, halfW)
  if math.abs(v) < 1e-9 then
    return 0, 0
  end
  local n = floor(math.abs(v) / scale * halfW + 0.5)
  return math.min(halfW, math.max(1, n)), v > 0 and 1 or -1
end

--- Is this value a cost? `axis` is "work" or "heat": less work is a cost, more heat needed is a cost.
function WardrobeText.isCost(axis, v)
  if axis == "work" then
    return v < -1e-9
  end
  return v > 1e-9
end

local function same(a, b)
  for slot, id in pairs(a) do
    if b[slot] ~= id then
      return false
    end
  end
  for slot, id in pairs(b) do
    if a[slot] ~= id then
      return false
    end
  end
  return true
end

WardrobeText.same = same

--- The line under the title: "Preview" while the figure shows a draft that is not chosen, "From dawn" when the
--- chosen outfit waits for the next dawn, else "Wearing today". Outfits are `{ slot = id }`.
function WardrobeText.stateLine(cfg, draft, committed, dressed)
  if not same(draft, committed) then
    return cfg.statePreview
  elseif not same(committed, dressed) then
    return cfg.stateDawn
  end
  return cfg.stateToday
end

--- The words beside Wear: whether a change is today's outfit at once or waits for dawn.
function WardrobeText.tag(cfg, appliesNow)
  return appliesNow and cfg.tagNow or cfg.tagDawn
end

--- A tile's pill: "Today" on the garment worn today, "Dawn" on the chosen garment that waits for dawn (never both
--- on one tile), else nil. The recovery variant has no run, so no pills. Returns the word and "today" | "dawn".
function WardrobeText.pill(cfg, id, committed, dressed, slot, variant)
  if variant == "recovery" then
    return nil
  end
  if dressed[slot] == id then
    return cfg.pillToday, "today"
  elseif committed[slot] == id then
    return cfg.pillDawn, "dawn"
  end
  return nil
end

--- A garment's hint with its threshold filled in (`%d`), or nil for a garment with none (a starter).
function WardrobeText.hint(def, threshold)
  if not def.hint then
    return nil
  end
  return (def.hint:gsub("%%d", tostring(threshold or 1)))
end

--- The two detail lines under the tiles. An owned garment: its name and weight. A locked one: the hint, then its
--- weight and how far along it is (only for a count, not a yes or no). Returns line1, line2 (line2 may be nil).
function WardrobeText.detail(cfg, def, owned, hintText, have, need)
  local weight = cfg.weights[def.class]
  if owned then
    return string.format(cfg.detail, def.name, weight)
  end
  local count = need and need > 1 and string.format(cfg.count, math.min(have or 0, need), need) or nil
  local second = count and string.format(cfg.lockedDetail, weight, count) or weight
  return hintText or cfg.locked, second
end

--- A tile's name wrapped to `maxLines` lines of at most `maxW` pixels (`measure(str)` is a string's width): words
--- stay whole, and what does not fit ends in the ellipsis.
function WardrobeText.nameLines(name, measure, maxW, maxLines, ellipsis)
  local function cut(s)
    while #s > 0 and measure(s .. ellipsis) > maxW do
      s = s:sub(1, -2)
    end
    return s .. ellipsis
  end
  local lines, cur = {}, ""
  for word in name:gmatch("%S+") do
    local try = cur == "" and word or (cur .. " " .. word)
    if measure(try) <= maxW then
      cur = try
    else
      if cur ~= "" then
        lines[#lines + 1] = cur
      end
      cur = word
    end
  end
  lines[#lines + 1] = cur
  if #lines > maxLines then
    local rest = table.concat(lines, " ", maxLines)
    for n = #lines, maxLines, -1 do
      lines[n] = nil
    end
    lines[maxLines] = cut(rest)
  end
  for n, line in ipairs(lines) do
    if measure(line) > maxW then
      lines[n] = cut(line)
    end
  end
  return lines
end

return WardrobeText
