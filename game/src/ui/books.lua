-- The Notebook and the Ledger (GDD §9.4, D140, D143): which pages each paper book holds, which page a
-- shortcut opens, which page each book remembers within a session, and where the tabs and the page body
-- sit. Pure (no love.graphics): the scene (src/scenes/book.lua) draws and hosts the pages; this decides.
-- Knobs: tuning.ui.book.

local Books = {}

local last = {} -- book id -> the page it was last left on; lives for the session and is never saved

--- Forget every remembered page (a new session, and tests).
function Books.reset()
  last = {}
end

--- The pages of `book` in order: { { id, label, icon } }.
function Books.pages(cfg, book)
  local pages = rawget(cfg.tabs, book) -- tuning is strict: a missing key would raise its own error
  if not pages then
    error("unknown book " .. tostring(book))
  end
  return pages
end

local function hasPage(cfg, book, id)
  for _, page in ipairs(Books.pages(cfg, book)) do
    if page.id == id then
      return true
    end
  end
  return false
end

--- True when `name` is a shortcut name (the old panel names and the world's taps).
function Books.hasShortcut(cfg, name)
  return rawget(cfg.shortcuts, name) ~= nil
end

--- The book and page a shortcut name opens. Errors on a name nobody defined.
function Books.shortcut(cfg, name)
  local target = rawget(cfg.shortcuts, name)
  if not target then
    error("unknown book shortcut " .. tostring(name))
  end
  return target[1], target[2]
end

--- The page a book opens on: the one asked for, else the one it was last left on, else its first.
function Books.page(cfg, book, request)
  if request and hasPage(cfg, book, request) then
    return request
  end
  local remembered = last[book]
  if remembered and hasPage(cfg, book, remembered) then
    return remembered
  end
  return Books.pages(cfg, book)[1].id
end

--- Note that `book` is now on `page` (called whenever the page changes and when the book closes).
function Books.remember(cfg, book, page)
  if not hasPage(cfg, book, page) then
    error("book " .. tostring(book) .. " has no page " .. tostring(page))
  end
  last[book] = page
end

--- The page `book` was last left on, or nil when it has not been opened this session.
function Books.last(book)
  return last[book]
end

--- Where everything sits: { paper, strip, body } rectangles in UI pixels for a view and a book. The paper is
--- as wide as the book wants (but inside the margin), the strip is the tab row along its top and the body is
--- the page below it.
function Books.rects(cfg, view, book, minTouch)
  local w = math.min(cfg.width[book], view.w - 2 * cfg.margin)
  local h = view.h - 2 * cfg.margin
  local paper = { x = math.floor((view.w - w) / 2), y = math.floor((view.h - h) / 2), w = w, h = h }
  local tabH = math.max(cfg.tabHeight, minTouch)
  local strip = { x = paper.x, y = paper.y, w = paper.w, h = tabH }
  local top = paper.y + tabH + cfg.bodyGap
  local body = { x = paper.x, y = top, w = paper.w, h = paper.y + paper.h - top }
  return { paper = paper, strip = strip, body = body }
end

--- The tab row inside `strip`: one rect per page, then the Close tab at the right end. When every label fits,
--- every tab shows its label; when not, only the selected tab does and the others shrink to an icon (still at
--- least `minTouch` wide). `measure(label)` is the label's width, `iconW` the stamp's width.
--- Returns { tabs = { { id, x, y, w, h, label = bool } }, close = { x, y, w, h } }.
function Books.layoutTabs(cfg, pages, selected, strip, minTouch, measure, iconW)
  local closeW = math.max(cfg.closeWidth, minTouch)
  local gap = cfg.tabGap
  local avail = strip.w - closeW - gap * (#pages + 1)
  local full, iconOnly, total = {}, math.max(minTouch, iconW + 2 * cfg.tabPad), 0
  for n, page in ipairs(pages) do
    full[n] = iconW + cfg.iconGap + measure(page.label) + 2 * cfg.tabPad
    total = total + full[n]
  end
  local allLabels = total <= avail
  local widths, used = {}, 0
  for n, page in ipairs(pages) do
    widths[n] = (allLabels or page.id == selected) and math.max(full[n], minTouch) or iconOnly
    used = used + widths[n]
  end
  if used > avail then -- too tight even so: share what there is
    local scale = avail / used
    for n = 1, #widths do
      widths[n] = math.max(minTouch, math.floor(widths[n] * scale))
    end
  end
  local out, x = { tabs = {} }, strip.x + gap
  for n, page in ipairs(pages) do
    out.tabs[n] = {
      id = page.id,
      x = x,
      y = strip.y,
      w = widths[n],
      h = strip.h,
      label = allLabels or page.id == selected,
    }
    x = x + widths[n] + gap
  end
  out.close = { x = strip.x + strip.w - closeW - gap, y = strip.y, w = closeW, h = strip.h }
  return out
end

--- The view a hosted page lays itself out in: the real view plus the body rectangle its panel fills
--- (Panel.box returns it for a page asking for a box).
function Books.hostView(view, body)
  return { w = view.w, h = view.h, scale = view.scale, host = body }
end

return Books
