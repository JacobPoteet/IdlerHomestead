-- The homestead's bottom toolbar as pure layout (D72, #17): no drawing, no fonts, so the placement can be
-- tested at any view size. Items are tables with a width `w`; arrange() gives them `x`, `y` and `h`.
--
-- Wide views get the classic bar: the tools on the left and the books on the right, one row. When all of
-- that does not fit in one row the bar becomes a palette bar: Hand, a Tools button, the tool in hand
-- (a shortcut, so the active tool never hides), and on the right the books used most (Pantry, Journal)
-- and a More button. Tools and More open a palette of buttons above the bar; every tool and book is in
-- the bar or in a palette, so none can be unreachable.

local Toolbar = {}

--- spec = {
---   left, right            the classic lists (items in order, `gapBefore` adds space before an item),
---   fixedLeft, toolsButton, active, fixedRight, moreButton   the palette bar: `active` may be nil,
---   tools, more            the items inside each palette }
--- cfg = { pad, gap, h, margin, paletteGap } (virtual pixels), plus the palette cap and scroll state:
---   paletteMaxRows (rows of buttons), paletteTop (y the palette must stay below), scrollBarWidth,
---   scroll = { tools = px, more = px } (how far each palette is scrolled). view = { w, h }.
--- Returns { palette = bool, bottomH, rows = n, bar = { items placed on the bar, in order },
---           popups = { tools = rect, more = rect } } (popups only in palette mode; each rect has x, y, w,
---           h and `items`, which are placed inside it).
function Toolbar.arrange(spec, view, cfg)
  local pad, gap, h = cfg.pad, cfg.gap, cfg.h
  local avail = view.w - 2 * pad

  local function span(items)
    local w = 0
    for i, b in ipairs(items) do
      w = w + b.w + (i > 1 and gap + (b.gapBefore or 0) or 0)
    end
    return w
  end

  local classic = span(spec.left) + gap + span(spec.right) <= avail
  local left, right = spec.left, spec.right
  if not classic then
    left = {}
    for _, b in ipairs(spec.fixedLeft) do
      left[#left + 1] = b
    end
    left[#left + 1] = spec.toolsButton
    if spec.active then
      left[#left + 1] = spec.active
    end
    right = {}
    for _, b in ipairs(spec.fixedRight) do
      right[#right + 1] = b
    end
    right[#right + 1] = spec.moreButton
  end

  -- Rows: the groups sit on one row when they fit, else each flows and wraps (a very narrow view).
  local rows = {}
  local oneRow = span(left) + gap + span(right) <= avail
  local function flow(items)
    local row, rowW = {}, 0
    for _, b in ipairs(items) do
      local need = b.w + (#row > 0 and gap + (b.gapBefore or 0) or 0)
      if #row > 0 and rowW + need > avail then
        rows[#rows + 1] = row
        row, rowW, need = {}, 0, b.w
      end
      row[#row + 1] = b
      rowW = rowW + need
    end
    if #row > 0 then
      rows[#rows + 1] = row
    end
  end
  flow(left)
  if not oneRow then
    flow(right)
  end
  local bottomH = 2 * cfg.margin + #rows * h + (#rows - 1) * gap
  local top = view.h - bottomH + cfg.margin
  local bar = {}
  for r, row in ipairs(rows) do
    local x, y = pad, top + (r - 1) * (h + gap)
    for i, b in ipairs(row) do
      x = x + (i > 1 and gap + (b.gapBefore or 0) or 0)
      b.x, b.y, b.h = x, y, h
      bar[#bar + 1] = b
      x = x + b.w
    end
  end
  if oneRow then
    local x = view.w - pad
    for i = #right, 1, -1 do
      local b = right[i]
      x = x - b.w
      b.x, b.y, b.h = x, top, h
      bar[#bar + 1] = b
      x = x - gap
    end
  end

  local result = { palette = not classic, bottomH = bottomH, rows = #rows, bar = bar }
  if classic then
    return result
  end

  -- Palettes: a framed block of buttons just above the bar, anchored under the button that opens it.
  -- The palette height is capped (D87, #184): at most cfg.paletteMaxRows rows and never above
  -- cfg.paletteTop (the lowest thing the palette must keep clear of). A taller palette scrolls: its
  -- items sit `scroll` pixels higher (cfg.scroll[name], clamped here and returned as `offset`), the
  -- window is `view` and the buttons that fall outside it are the scene's to clip.
  local function popup(name, items, anchor, alignRight)
    local function flow(inner)
      local prow, prowW, plines = {}, 0, {}
      for _, b in ipairs(items) do
        local need = b.w + (#prow > 0 and gap or 0)
        if #prow > 0 and prowW + need > inner then
          plines[#plines + 1] = prow
          prow, prowW, need = {}, 0, b.w
        end
        prow[#prow + 1] = b
        prowW = prowW + need
      end
      if #prow > 0 then
        plines[#plines + 1] = prow
      end
      return plines
    end
    local function linesH(n)
      return n * h + (n - 1) * gap
    end
    local inner = avail - 2 * gap
    local plines = flow(inner)
    local bottom = view.h - bottomH - cfg.paletteGap
    local maxH = 2 * gap + linesH(cfg.paletteMaxRows or #plines)
    if cfg.paletteTop then
      maxH = math.min(maxH, bottom - cfg.paletteTop)
    end
    local scrolls = 2 * gap + linesH(#plines) > maxH
    local bar = scrolls and (cfg.scrollBarWidth or 0) + gap or 0
    if scrolls then
      plines = flow(inner - bar) -- room for the scroll thumb beside the buttons
    end
    local widest = 0
    for _, line in ipairs(plines) do
      local w = -gap
      for _, b in ipairs(line) do
        w = w + gap + b.w
      end
      widest = math.max(widest, w)
    end
    local w = widest + 2 * gap + bar
    local contentH = linesH(#plines)
    local ph = scrolls and math.max(2 * gap + h, maxH) or contentH + 2 * gap
    local viewH = ph - 2 * gap
    local offset = math.max(0, math.min(((cfg.scroll or {})[name]) or 0, contentH - viewH))
    local x = alignRight and (anchor.x + anchor.w - w) or anchor.x
    x = math.max(pad, math.min(x, view.w - pad - w))
    local y = bottom - ph
    for n, line in ipairs(plines) do
      local bx = x + gap
      for _, b in ipairs(line) do
        b.x, b.y, b.h = bx, y + gap + (n - 1) * (h + gap) - offset, h
        bx = bx + b.w + gap
      end
    end
    return {
      x = x,
      y = y,
      w = w,
      h = ph,
      items = items,
      scrolls = scrolls,
      contentH = contentH,
      offset = offset,
      view = { x = x, y = y + gap, w = w - bar - gap, h = viewH },
    }
  end
  result.popups = {
    tools = popup("tools", spec.tools, spec.toolsButton, false),
    more = popup("more", spec.more, spec.moreButton, true),
  }
  return result
end

return Toolbar
