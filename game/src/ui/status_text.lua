-- The words of the status chips and their detail card (D167, #346; docs/PLAN_DEPTH.md §7): pure functions over the
-- views Status.active returns and tuning.ui.status, so the chip, the card and the recovery scene say the same thing and
-- a test can check them without a window. Colour is never the only signal: every chip is an icon and words.

local StatusText = {}

--- The sprite id of a status's icon: its family's own, or the plain one.
function StatusText.icon(has, status)
  local id = "icon_status_" .. status.family
  return has(id) and id or "icon_status"
end

--- A chip's days: "3d", or "until cured" for a status with no end date.
function StatusText.days(cfg, left)
  if left == nil then
    return cfg.openShort
  end
  return string.format(cfg.daysShort, left)
end

--- A chip's words, fitted to `maxW` (a measure function gives a string's width): the effect and the days left, or, when
--- that is too wide, the status's name and the days left. Never empty.
function StatusText.chip(cfg, status, maxW, measure)
  local days = StatusText.days(cfg, status.left)
  local full = string.format(cfg.chipFormat, status.line, days)
  if measure(full) <= maxW then
    return full
  end
  return string.format(cfg.chipShortFormat, status.name, days)
end

--- One modifier in words ("Work 20% slower"), or nil when it changes nothing.
function StatusText.effect(cfg, name, value)
  local words = cfg.effects[name]
  if not words then
    return nil
  end
  if name == "conditionDrain" then
    return value > 0 and string.format(words.more, value) or nil
  end
  local pct = math.floor(math.abs(value - 1) * 100 + 0.5)
  if pct == 0 then
    return nil
  end
  return string.format(value < 1 and words.less or words.more, pct)
end

--- A status's effects in words, in the card's order.
function StatusText.effects(cfg, modifiers)
  local out = {}
  for _, name in ipairs(cfg.effectOrder) do
    local value = modifiers[name]
    local text = value and StatusText.effect(cfg, name, value)
    if text then
      out[#out + 1] = text
    end
  end
  return out
end

--- The detail card for one active status: { title, effects = { string }, time (when it ends), how (what clears it),
--- worse (what happens if it is hurt again), footer }. `registry` names the next step of the family, `count` and `most`
--- are how many statuses are active and the most at once.
function StatusText.detail(cfg, registry, status, count, most)
  local time
  if status.left == nil then
    time = cfg.daysLeft.open
  elseif status.left <= 1 then
    time = cfg.daysLeft.one
  else
    time = string.format(cfg.daysLeft.many, status.left)
  end
  local def = registry:get("statuses", status.id)
  local worse = def.escalatesTo and string.format(cfg.escalates, registry:get("statuses", def.escalatesTo).name:lower())
    or cfg.capped
  return {
    title = status.name,
    line = status.line,
    effects = StatusText.effects(cfg, status.modifiers),
    time = time,
    how = cfg.clearedBy[status.clearedBy] or "",
    worse = worse,
    footer = string.format(cfg.overall, count, most),
  }
end

--- The recovery scene's line for the run's history ({ { id, count } }): "Hurt this run: Hobbling, Fever x2", or nil when
--- nothing hurt the homesteader. A status the content no longer has is left out.
function StatusText.hurtLine(cfg, registry, hurt)
  local names = {}
  for _, h in ipairs(hurt or {}) do
    if registry:has("statuses", h.id) then
      local name = registry:get("statuses", h.id).name
      names[#names + 1] = h.count > 1 and string.format(cfg.hurtCount, name, h.count) or name
    end
  end
  if #names == 0 then
    return nil
  end
  return string.format(cfg.hurtLine, table.concat(names, cfg.hurtJoin))
end

return StatusText
