-- The homestead's resting HUD as pure layout (GDD §9.4, D137, #293): no drawing and no fonts, so the
-- placement can be tested at any view size. Each corner has one job: the clock and speed top left, the
-- vitals and Menu top right, decision stamps down the left edge, the homesteader badge bottom left, the
-- tool badge bottom centre, the books bottom right. Trays (the tools, a book's pages) open above the plate
-- that owns them.

local Hud = {}

local function rect(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

--- spec = {
---   clock = { w, h }, speed = { w, h, segments = n }, menu = { w, h },
---   vitals = { { id, w } }, vitalH,                    each vital's content width; the plate height
---   stamps = { { id, w, iconW } },                     a stamp's full width (icon and words) and icon-only width
---   badge = { w, compactW, h }, tool = { w, compactW, h }, books = { { id, w, compactW } },
---   caption = { w, h } or nil,
---   goal = { w, h } or nil }                           the pressing-goal line: a line of its own under the top plates
--- cfg = { pad, gap, vitalGap, vitalPad } (UI pixels); view = { w, h }.
--- Returns { clock, speed, segments = { rect }, menu, vitals = { { x, y, w, h, items = { { id, x, w } } } },
---   topH (y under the top plates), goal = rect or nil (the pressing-goal line), stamps = { { id, x, y, w, h, compact } }, badge, tool, books = { rect },
---   compact (the bottom plates are icon-only), caption, bottomTop (y over the bottom plates and caption) }.
function Hud.arrange(spec, view, cfg)
  local pad, gap = cfg.pad, cfg.gap
  local out = {}

  -- Top left: the clock, the speed plate beside it.
  out.clock = rect(pad, pad, spec.clock.w, spec.clock.h)
  out.speed = rect(pad + spec.clock.w + gap, pad, spec.speed.w, spec.speed.h)
  out.segments = {}
  local n = spec.speed.segments
  for k = 1, n do
    local x0 = out.speed.x + math.floor((k - 1) * spec.speed.w / n)
    local x1 = out.speed.x + math.floor(k * spec.speed.w / n)
    out.segments[k] = rect(x0, out.speed.y, x1 - x0, out.speed.h)
  end
  -- Top right: Menu in the corner.
  out.menu = rect(view.w - pad - spec.menu.w, pad, spec.menu.w, spec.menu.h)
  local topRowBottom = pad + math.max(spec.clock.h, spec.speed.h, spec.menu.h)

  -- Vitals: one plate left of Menu when it fits beside the clock and speed; else rows under them.
  local function widthOf(items)
    local w = 2 * cfg.vitalPad
    for i, it in ipairs(items) do
      w = w + it.w + (i > 1 and cfg.vitalGap or 0)
    end
    return w
  end
  local function place(items, x, y)
    local row = rect(x, y, widthOf(items), spec.vitalH)
    row.items = {}
    local ix = x + cfg.vitalPad
    for _, it in ipairs(items) do
      row.items[#row.items + 1] = { id = it.id, x = ix, w = it.w }
      ix = ix + it.w + cfg.vitalGap
    end
    return row
  end
  out.vitals = {}
  local leftEnd = out.speed.x + out.speed.w + gap
  local bottom = topRowBottom
  if #spec.vitals > 0 then
    local whole = widthOf(spec.vitals)
    if leftEnd + whole <= out.menu.x - gap then
      local row = place(spec.vitals, out.menu.x - gap - whole, pad)
      row.y = pad + math.floor((math.max(spec.clock.h, spec.menu.h) - spec.vitalH) / 2)
      out.vitals[1] = row
    else
      local avail = view.w - 2 * pad
      local y = topRowBottom + gap
      local items = {}
      local function flush()
        if #items > 0 then
          out.vitals[#out.vitals + 1] = place(items, pad, y)
          y = y + spec.vitalH + gap
          items = {}
        end
      end
      for _, it in ipairs(spec.vitals) do
        items[#items + 1] = it
        if widthOf(items) > avail and #items > 1 then
          table.remove(items)
          flush()
          items[1] = it
        end
      end
      flush()
      bottom = y - gap
    end
  end
  out.topH = bottom + gap

  -- The bottom row: the full plates when they fit side by side, else icon-only.
  local function rowWidth(compact)
    local w = (compact and spec.badge.compactW or spec.badge.w) + (compact and spec.tool.compactW or spec.tool.w)
    for _, b in ipairs(spec.books) do
      w = w + (compact and b.compactW or b.w)
    end
    return w + (#spec.books + 1) * gap
  end
  local compact = rowWidth(false) > view.w - 2 * pad
  out.compact = compact
  local rowH = math.max(spec.badge.h, spec.tool.h)
  local by = view.h - pad - rowH
  local bw = compact and spec.badge.compactW or spec.badge.w
  out.badge = rect(pad, by, bw, spec.badge.h)
  out.books = {}
  local x = view.w - pad
  for i = #spec.books, 1, -1 do
    local b = spec.books[i]
    local w = compact and b.compactW or b.w
    x = x - w
    out.books[i] = rect(x, by, w, rowH)
    out.books[i].id = b.id
    x = x - gap
  end
  local booksLeft = x + gap
  local tw = compact and spec.tool.compactW or spec.tool.w
  local tx = math.floor((view.w - tw) / 2)
  -- Centred, unless that would touch the badge or the books: then just right of the badge.
  if tx < out.badge.x + out.badge.w + gap or tx + tw > booksLeft - gap then
    tx = out.badge.x + out.badge.w + gap
  end
  out.tool = rect(tx, by, tw, spec.tool.h)
  out.bottomTop = by - gap
  if spec.caption then
    local cw = math.min(spec.caption.w, view.w - 2 * pad)
    local cx = math.max(pad, math.min(view.w - pad - cw, math.floor(out.tool.x + (out.tool.w - cw) / 2)))
    out.caption = rect(cx, by - gap - spec.caption.h, cw, spec.caption.h)
    out.bottomTop = out.caption.y - gap
  end

  -- Decision stamps down the left edge, under the top plates; words beside the icon while they fit.
  out.stamps = {}
  local sy = out.topH
  -- The pressing-goal line (D163, #342) is its own line first under the top plates, above the stamps; the top plates
  -- are not widened for it.
  if spec.goal and sy + spec.goal.h <= out.bottomTop then
    out.goal = rect(pad, sy, math.min(spec.goal.w, view.w - 2 * pad), spec.goal.h)
    sy = sy + spec.goal.h + gap
  end
  for _, s in ipairs(spec.stamps) do
    local small = s.w > view.w - 2 * pad or compact
    local h = s.h or s.iconW
    if sy + h > out.bottomTop then
      break -- no room left above the bottom plates; the rest wait their turn
    end
    out.stamps[#out.stamps + 1] = { id = s.id, x = pad, y = sy, w = small and s.iconW or s.w, h = h, compact = small }
    sy = sy + h + gap
  end
  out.stampsBottom = sy
  return out
end

--- A tray of buttons opening above `anchor`: `items` (each with `w`) flow into rows of height `h` inside a
--- framed block that stays inside the view. The height is capped at `cfg.maxRows` rows and never above
--- `cfg.top`; a taller tray scrolls: its items sit `cfg.scroll` pixels higher (clamped, returned as
--- `offset`), `view` is the window and the buttons outside it are the scene's to clip (D87).
--- cfg = { pad, gap, h, maxRows, top, scrollBarWidth, scroll }. Items get x, y and h.
function Hud.tray(items, anchor, view, cfg, alignRight)
  local pad, gap, h = cfg.pad, cfg.gap, cfg.h
  local avail = view.w - 2 * pad
  local function wrap(inner)
    local row, rowW, lines = {}, 0, {}
    for _, b in ipairs(items) do
      local need = b.w + (#row > 0 and gap or 0)
      if #row > 0 and rowW + need > inner then
        lines[#lines + 1] = row
        row, rowW, need = {}, 0, b.w
      end
      row[#row + 1] = b
      rowW = rowW + need
    end
    if #row > 0 then
      lines[#lines + 1] = row
    end
    return lines
  end
  local function linesH(n)
    return n * h + (n - 1) * gap
  end
  local inner = avail - 2 * gap
  local lines = wrap(inner)
  local bottom = anchor.y - gap
  local maxH = 2 * gap + linesH(cfg.maxRows or #lines)
  if cfg.top then
    maxH = math.min(maxH, bottom - cfg.top)
  end
  local scrolls = 2 * gap + linesH(#lines) > maxH
  local thumb = scrolls and (cfg.scrollBarWidth or 0) + gap or 0
  if scrolls then
    lines = wrap(inner - thumb) -- room for the scroll thumb beside the buttons
  end
  local widest = 0
  for _, line in ipairs(lines) do
    local w = -gap
    for _, b in ipairs(line) do
      w = w + gap + b.w
    end
    widest = math.max(widest, w)
  end
  local w = widest + 2 * gap + thumb
  local contentH = linesH(#lines)
  local th = scrolls and math.max(2 * gap + h, maxH) or contentH + 2 * gap
  local viewH = th - 2 * gap
  local offset = math.max(0, math.min(cfg.scroll or 0, contentH - viewH))
  local x = alignRight and (anchor.x + anchor.w - w) or anchor.x
  x = math.max(pad, math.min(x, view.w - pad - w))
  local y = bottom - th
  for n, line in ipairs(lines) do
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
    h = th,
    items = items,
    scrolls = scrolls,
    contentH = contentH,
    offset = offset,
    view = { x = x, y = y + gap, w = w - thumb - gap, h = viewH },
  }
end

return Hud
