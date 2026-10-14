-- Tip-card highlight (GDD D89, #171): a pulsing outline and arrow on the thing a first-time card talks
-- about. Presentation only: it reads layout, never changes the sim. Targets are strings in the step's
-- `highlight` field (data/content/ftue.lua):
--   "button:<id>"  a bottom-bar button (pantry, catalog, journal, place ...)
--   "seeds"        the first seed button, else the Tools button that opens the palette
--   "chip:<id>"    a top-bar stat chip (food, condition, ...)
--   "tile:truck"   the truck's footprint in the world
-- A target that is not on screen right now resolves to nil, and then nothing is drawn.

local Highlight = {}

-- Where a button target falls back to when it is not itself on the bar (a narrow screen keeps tools in a palette).
local FALLBACK = { place = "tools", plan = "tools", rod = "tools", untill = "tools" }

--- Screen rectangle { x, y, w, h } for a target, or nil. `find` = { button = fn(id), chip = fn(id),
--- tile = fn(name), seed = fn() } each returning a rect or nil.
function Highlight.resolve(target, find)
  if type(target) ~= "string" or not find then
    return nil
  end
  if target == "seeds" then
    return (find.seed and find.seed()) or (find.button and find.button("tools")) or nil
  end
  local kind, id = target:match("^(%a+):(.+)$")
  if not kind then
    return nil
  end
  if kind == "button" and find.button then
    return find.button(id) or (FALLBACK[id] and find.button(FALLBACK[id])) or nil
  elseif kind == "chip" and find.chip then
    return find.chip(id)
  elseif kind == "tile" and find.tile then
    return find.tile(id)
  end
  return nil
end

--- The rect kept only if it overlaps the view (so a target scrolled away draws nothing).
function Highlight.visible(rect, view)
  if not rect or rect.w <= 0 or rect.h <= 0 then
    return nil
  end
  if rect.x + rect.w <= 0 or rect.y + rect.h <= 0 or rect.x >= view.w or rect.y >= view.h then
    return nil
  end
  return rect
end

--- Pulse phase 0..1 at render time `t` (seconds).
function Highlight.phase(t, seconds)
  return (t % seconds) / seconds
end

--- Draw the outline and an arrow head; `cfg` = tuning.ftue, `color` the accent, `t` render seconds,
--- `view` the virtual view (the arrow sits above the target, or below when there is no room above).
function Highlight.draw(rect, cfg, color, t, view)
  local p = Highlight.phase(t, cfg.highlightPulseSeconds)
  local grow = cfg.highlightGrow * p
  local pad = cfg.highlightPad
  love.graphics.push("all")
  love.graphics.setLineWidth(cfg.highlightThickness)
  -- A steady ring plus a ring that grows outward and fades, so it reads as a pulse without any hover.
  love.graphics.setColor(color[1], color[2], color[3], 1)
  love.graphics.rectangle("line", rect.x - pad, rect.y - pad, rect.w + 2 * pad, rect.h + 2 * pad, 4, 4)
  love.graphics.setColor(color[1], color[2], color[3], 1 - p)
  love.graphics.rectangle(
    "line",
    rect.x - pad - grow,
    rect.y - pad - grow,
    rect.w + 2 * (pad + grow),
    rect.h + 2 * (pad + grow),
    5,
    5
  )
  local s = cfg.highlightArrow
  local cx = math.max(s, math.min(view.w - s, rect.x + rect.w / 2))
  love.graphics.setColor(color[1], color[2], color[3], 1)
  if rect.y - pad - grow - 2 * s > 0 then
    local tipY = rect.y - pad - grow - 1
    love.graphics.polygon("fill", cx, tipY, cx - s, tipY - s, cx + s, tipY - s)
  else
    local tipY = rect.y + rect.h + pad + grow + 1
    love.graphics.polygon("fill", cx, tipY, cx - s, tipY + s, cx + s, tipY + s)
  end
  love.graphics.pop()
end

return Highlight
