-- Plain words for the recovery scene's run summary of what came at the homestead (D202, #156, #390): the night threats,
-- the growing-season threats and the bad events of the run, and the one that hurt most. Pure (no drawing): it turns the
-- summary's `faced` (Run.faced) into short lines, so the wording is tested headless. Words are tuning.ui.faced.

local FacedText = {}

-- The field that names each kind (definitions are strict: an unknown field errors).
local NAME_FIELD = { night_threats = "name", threats = "name", events = "title" }

local function nameOf(registry, kind, id)
  if not registry:has(kind, id) then
    return nil -- content renamed since the summary was saved: leave it out
  end
  return registry:get(kind, id)[NAME_FIELD[kind]]
end

local function lower(s)
  return s:lower()
end

local function nightItem(cfg, name, n)
  local total = n.landed + n.turned
  if n.turned == 0 then
    return string.format(cfg.nightItem, lower(name), total)
  elseif n.landed == 0 then
    return string.format(cfg.nightNone, lower(name), total)
  end
  return string.format(cfg.nightSome, lower(name), total, n.landed)
end

local function fieldItem(cfg, name, f)
  if f.struck == 0 then
    return string.format(cfg.fieldPassed, lower(name))
  end
  local head = f.struck == 1 and string.format(cfg.fieldStruck, lower(name))
    or string.format(cfg.fieldStruckTimes, lower(name), f.struck)
  local parts = { head }
  if f.lost > 0 then
    parts[#parts + 1] = string.format(cfg.fieldLost, f.lost)
  end
  if f.damaged > 0 then
    parts[#parts + 1] = string.format(cfg.fieldDamaged, f.damaged)
  end
  if f.saved > 0 then
    parts[#parts + 1] = string.format(cfg.fieldSaved, f.saved)
  end
  return table.concat(parts, cfg.detailJoin)
end

--- The summary as lines: { { text, accent? } } (the "hurt most" line is the accent one), or one quiet line when nothing
--- came (empty lists). `cfg` is tuning.ui.faced.
function FacedText.lines(cfg, registry, faced)
  faced = faced or {}
  local lines, worst = {}, nil
  -- The one that hurt most: the most nights a threat got in, strikes that cost crops, or times a misfortune came; ties
  -- go to the night, then the field, then the events, each in content order.
  local function consider(harm, name, detail)
    if harm > 0 and (not worst or harm > worst.harm) then
      worst = { harm = harm, name = name, detail = detail }
    end
  end

  local items = {}
  for _, n in ipairs(faced.night or {}) do
    local name = nameOf(registry, "night_threats", n.id)
    if name then
      items[#items + 1] = nightItem(cfg, name, n)
      consider(n.landed, name, n.landed == 1 and cfg.worstNightOnce or string.format(cfg.worstNight, n.landed))
    end
  end
  if #items > 0 then
    lines[#lines + 1] = { text = string.format(cfg.night, table.concat(items, cfg.join)) }
  end

  items = {}
  for _, f in ipairs(faced.field or {}) do
    local name = nameOf(registry, "threats", f.id)
    if name then
      items[#items + 1] = fieldItem(cfg, name, f)
      local crops = f.lost + f.damaged
      consider(crops > 0 and f.struck or 0, name, string.format(cfg.worstField, crops))
    end
  end
  if #items > 0 then
    lines[#lines + 1] = { text = string.format(cfg.field, table.concat(items, cfg.join)) }
  end

  items = {}
  for _, e in ipairs(faced.events or {}) do
    local name = nameOf(registry, "events", e.id)
    if name then
      items[#items + 1] = e.count > 1 and string.format(cfg.eventItem, lower(name), e.count) or lower(name)
      consider(e.count, name, e.count == 1 and cfg.worstEventOnce or string.format(cfg.worstEvent, e.count))
    end
  end
  if #items > 0 then
    lines[#lines + 1] = { text = string.format(cfg.events, table.concat(items, cfg.join)) }
  end

  if #lines == 0 then
    return { { text = cfg.quiet } }
  end
  if worst then
    lines[#lines + 1] = { text = string.format(cfg.worst, worst.name, worst.detail), accent = true }
  end
  return lines
end

return FacedText
