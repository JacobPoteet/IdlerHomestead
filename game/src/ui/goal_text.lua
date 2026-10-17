-- Plain words for the pressing-goal line and the Progress panel (D163, #342, docs/PLAN_DEPTH.md §3). Pure (no
-- drawing, no sim writes): it turns Goal.current, Milestones.list and Goal.gates into the line's segments and the
-- panel's sections, so the wording is tested headless. Levels follow the chips: 0 fine, 1 amber, 2 red.

local GoalText = {}

GoalText.title = "Progress"
GoalText.separator = " · "
GoalText.ellipsis = ".."

local SEASON_NAMES = { spring = "Spring", summer = "Summer", autumn = "Autumn", winter = "Winter" }

-- What a missing Footing test is called in "needs ...".
local NEEDS = { shelter = "a fire", water = "water", fuel = "wood", food = "food" }

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

local function whole(x)
  return string.format("%d", math.floor(x + 1e-9))
end

-- A count with one decimal at most; "plenty" for a need that never comes (math.huge).
local function figure(x)
  if x == math.huge then
    return "plenty"
  end
  local rounded = math.floor(x * 10 + 1e-9) / 10
  if rounded == math.floor(rounded) then
    return string.format("%d", rounded)
  end
  return string.format("%.1f", rounded)
end

local function missing(goal)
  local names = {}
  for _, c in ipairs(goal.footing.checks) do
    if not c.ok then
      names[#names + 1] = NEEDS[c.id]
    end
  end
  return names
end

local function stock(label, part)
  return string.format("%s %s of %s", label, whole(part.have), whole(part.need))
end

local function greatSegment(great)
  if great.state == "now" then
    return "Great Winter now"
  elseif great.state == "survived" then
    return nil
  elseif great.yearsAway == 0 then
    return "Great Winter this year"
  end
  return "Great Winter in year " .. great.year
end

--- The goal line's segments, most important first: { text, level }. The line drops trailing ones to fit.
function GoalText.segments(goal)
  local segs = {}
  local function add(text, level)
    segs[#segs + 1] = { text = text, level = level or 0 }
  end
  if goal.kind == "tonight" then
    local names = {}
    for _, g in ipairs(goal.gaps) do
      names[#names + 1] = g.name
    end
    add("Tonight: " .. table.concat(names, ", ") .. " short", goal.level)
    if goal.slipped then
      add("Footing slipped", 1)
    end
  elseif goal.kind == "footing" or goal.kind == "regain" then
    local f = goal.footing
    if goal.kind == "footing" then
      add(string.format("Footing: %d of %d held", f.okCount, f.total))
      local need = missing(goal)
      if #need > 0 then
        add("needs " .. table.concat(need, ", "))
      end
      add(string.format("night %d of %d", f.streak, f.streakNights))
    else
      add(string.format("Regain Footing: night %d of %d", f.good, f.regainNights), 1)
      local need = missing(goal)
      if #need > 0 then
        add("needs " .. table.concat(need, ", "))
      end
    end
  else
    local w = goal.winter
    local level = (w.verdict and w.verdict ~= "ready") and 1 or 0
    if w.never then
      local s = goal.season
      add(string.format("%s, day %d · year %d", SEASON_NAMES[s.season] or s.season, s.day, s.year))
    elseif w.frozen then
      add("Winter now", level)
    else
      add("Winter in " .. plural(w.daysAway, "day"), level)
    end
    if w.wood then
      add(stock("wood", w.wood), level)
    end
    if w.food then
      add(stock("food", w.food), level)
    end
    local great = greatSegment(goal.great)
    if great then
      add(great)
    end
  end
  return segs
end

--- The worst level among the segments the line shows (the line's colour).
function GoalText.level(goal)
  local level = 0
  for _, s in ipairs(GoalText.segments(goal)) do
    level = math.max(level, s.level)
  end
  return level
end

--- The goal as one string that fits `maxW` pixels by `measure(text)`: segments are dropped from the end until it
--- fits; a first segment that is still too wide is cut and ends in "..". `maxW` nil means no limit.
function GoalText.line(goal, maxW, measure)
  local segs = GoalText.segments(goal)
  local function join(n)
    local parts = {}
    for i = 1, n do
      parts[i] = segs[i].text
    end
    return table.concat(parts, GoalText.separator)
  end
  if not maxW then
    return join(#segs)
  end
  for n = #segs, 1, -1 do
    local text = join(n)
    if measure(text) <= maxW then
      return text
    end
  end
  local text = segs[1].text
  while #text > 1 and measure(text .. GoalText.ellipsis) > maxW do
    text = text:sub(1, #text - 1)
  end
  return text .. GoalText.ellipsis
end

local function checkText(c)
  if c.id == "shelter" then
    return "A shelter with a fire"
  elseif c.id == "water" then
    return string.format("Drinking water: %s of %s", figure(c.have), plural(c.need, "day"))
  elseif c.id == "fuel" then
    return string.format("Wood: %s of %s", figure(c.have), plural(c.need, "night"))
  end
  return string.format("Food: %s of %s", figure(c.have), plural(c.need, "day"))
end

local function sectionOf(title, rows, tag)
  return { title = title, rows = rows, tag = tag }
end

local function seasonName(id)
  return SEASON_NAMES[id] or id
end

--- The panel as sections: { { title, tag (a short word beside the title or nil), rows = { { text, level, mark, dim } } } }.
--- `mark` is "done" | "todo" | "open" | "lock" (a box the scene draws) or nil. `milestones` is Milestones.list,
--- `tally` = { done, total }, `gates` is Goal.gates.
function GoalText.panel(goal, milestones, tally, gates)
  local sections = {}

  -- The pressing goal, whole.
  local now = {}
  for _, s in ipairs(GoalText.segments(goal)) do
    now[#now + 1] = { text = s.text, level = s.level }
  end
  sections[#sections + 1] = sectionOf("Now", now)

  -- The year and the winter ahead.
  local s, w, g = goal.season, goal.winter, goal.great
  local year = {
    { text = string.format("Year %d · %s, day %d of %d", s.year, seasonName(s.season), s.day, s.daysPerSeason) },
  }
  if w.never then
    year[#year + 1] = { text = "No season freezes here.", dim = true }
  elseif w.frozen then
    year[#year + 1] = { text = "Winter is on.", level = 1 }
  else
    year[#year + 1] = { text = "Winter in " .. plural(w.daysAway, "day") }
  end
  if w.wood then
    year[#year + 1] = {
      text = stock("Wood for the cold", w.wood),
      level = (w.verdict == "fuel" or w.verdict == "both") and 1 or 0,
    }
  end
  if w.food then
    year[#year + 1] = {
      text = stock("Food for the cold", w.food),
      level = (w.verdict == "food" or w.verdict == "both") and 1 or 0,
    }
  end
  if g.state == "survived" then
    year[#year + 1] = { text = "Great Winter (year " .. g.year .. "): survived" }
  elseif g.state == "now" then
    year[#year + 1] = { text = "Great Winter (year " .. g.year .. "): now", level = 1 }
  else
    year[#year + 1] = {
      text = "Great Winter (year " .. g.year .. "): " .. (g.yearsAway == 0 and "this year" or plural(
        g.yearsAway,
        "year"
      ) .. " away"),
    }
  end
  if g.slotEstablished then
    year[#year + 1] = { text = "This slot is Established.", dim = true }
  end
  sections[#sections + 1] = sectionOf("Year and season", year)

  -- Footing.
  local f = goal.footing
  local footing = {}
  if f.held and not f.slipped then
    footing[1] = { text = f.gainedDay and ("Held since day " .. f.gainedDay) or "Held" }
  elseif f.held then
    footing[1] = {
      text = string.format("Slipped: good night %d of %d to get it back", f.good, f.regainNights),
      level = 1,
    }
  else
    footing[1] = { text = string.format("Not yet: night %d of %d in a row", f.streak, f.streakNights) }
  end
  for _, c in ipairs(f.checks) do
    footing[#footing + 1] = { text = checkText(c), mark = c.ok and "done" or "todo", level = c.ok and 0 or 1 }
  end
  sections[#sections + 1] = sectionOf("Footing", footing)

  -- The run's milestones.
  local rows = {}
  for _, m in ipairs(milestones) do
    if m.done then
      rows[#rows + 1] = {
        text = string.format("%s · %s, day %d", m.name, seasonName(m.season), m.day)
          .. (m.year > 1 and (" of year " .. m.year) or ""),
        mark = "done",
      }
    else
      local progress = m.need > 1 and string.format(" (%d of %d)", m.have, m.need) or ""
      rows[#rows + 1] = { text = m.name .. progress .. ": " .. m.hint, mark = "todo", dim = true }
    end
  end
  sections[#sections + 1] = sectionOf("Milestones", rows, string.format("%d of %d", tally[1], tally[2]))

  -- Gates that open at Footing.
  local locked = {}
  for _, item in ipairs(gates.items) do
    locked[#locked + 1] = {
      text = gates.open and item.name or (item.name .. " · opens at Footing"),
      mark = gates.open and "open" or "lock",
      dim = not gates.open,
    }
  end
  sections[#sections + 1] = sectionOf(gates.open and "Opened by Footing" or "Opens at Footing", locked)
  return sections
end

return GoalText
