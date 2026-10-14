-- Journal navigation state and input geometry (GDD D81, #194). No drawing and no world access: the scene
-- feeds it plain data, so the transitions are testable. INTENTIONALLY MINIMAL (a temporary design).
--
--   nav = Nav.new()          { view = "overview" | "focus", cur = chapter index, filter, offset, ... }
--   Nav.layout(nav, data, free, spec, minTouch)   rebuilds the chip rects, the body and the grid / fit
--     data = { chapters, stats, groups, ideaCount }       free = the part of the map rect to use
-- Search (D120, #208): data.results is nil for no search, else the list of matches; then the chips and the
-- view are replaced by nav.list (the result rows) under the search field (nav.field, nav.clear). The field and
-- its Clear button exist (data.showField) only while in use; until then a "search" chip opens it.
-- After layout: nav.chips = { { kind, label, x, y, w, h } }, nav.body = rect, and either nav.grid
-- (overview, see Layout.overview) or nav.fit (focus, see Layout.fit).

local Layout = require("src.ui.journal_layout")
local Scroll = require("src.ui.scroll")

local Nav = {}

Nav.FILTERS = { "all", "known", "ideas", "locked" }

function Nav.new()
  return {
    view = "overview",
    cur = 1,
    filter = "all",
    offset = 0, -- overview scroll
    focusOffset = 0, -- scroll of a very large chapter (D120)
    resultOffset = 0, -- scroll of the search results
    fits = {},
    chips = {},
    body = { x = 0, y = 0, w = 0, h = 0 },
  }
end

-- Transitions ----------------------------------------------------------------------------------

function Nav.openChapter(nav, index)
  nav.cur, nav.view = index, "focus"
  nav.focusOffset = 0
end

function Nav.backToOverview(nav)
  nav.view = "overview"
end

function Nav.setFilter(nav, filter)
  nav.filter, nav.offset = filter, 0
end

--- Forget cached fits (the view size changed).
function Nav.resized(nav)
  nav.fits = {}
end

-- Layout ---------------------------------------------------------------------------------------

--- The chips for the current view, in order: Chapters (focus only), Queue, To study (n), then the filters.
function Nav.chipDefs(nav, ideaCount, spec, showField)
  local labels, defs = spec.labels, {}
  if nav.view == "focus" then
    defs[#defs + 1] = { kind = "back", label = labels.back }
  end
  defs[#defs + 1] = { kind = "queue", label = labels.queue }
  defs[#defs + 1] = { kind = "study", label = string.format(labels.study, ideaCount) }
  for _, filter in ipairs(Nav.FILTERS) do
    defs[#defs + 1] = { kind = filter, label = labels.filters[filter] }
  end
  if not showField then
    defs[#defs + 1] = { kind = "search", label = labels.search }
  end
  return defs
end

local function cachedFit(nav, chapter, body, spec)
  local key = chapter.id .. ":" .. math.floor(body.w) .. "x" .. math.floor(body.h)
  local fit = nav.fits[key]
  if not fit then
    fit = Layout.fit(chapter, body, spec)
    nav.fits[key] = fit
  end
  return fit
end

function Nav.layout(nav, data, free, spec, minTouch)
  local inner = { x = free.x + spec.pad, y = free.y + spec.pad, w = free.w - 2 * spec.pad, h = free.h - 2 * spec.pad }
  local search = spec.search
  -- The search field takes a row only while it is in use (focused, or holding a query); otherwise a chip opens it.
  local showField = data.showField or data.results ~= nil
  local belowField = inner.y
  nav.field, nav.clear = nil, nil
  if showField then
    local fieldH = math.max(search.height, minTouch)
    local clearW = math.max(search.clearWidth, minTouch)
    nav.field = { x = inner.x, y = inner.y, w = inner.w - clearW - spec.gap, h = fieldH }
    nav.clear = { x = inner.x + inner.w - clearW, y = inner.y, w = clearW, h = fieldH }
    belowField = inner.y + fieldH + spec.gap
  end

  if data.results then
    -- Searching: the result rows fill the body, no chips.
    nav.chips = {}
    nav.body = { x = inner.x, y = belowField, w = inner.w, h = math.max(1, inner.y + inner.h - belowField) }
    local rowH = math.max(search.rowHeight, minTouch)
    nav.list = { rowH = rowH, count = #data.results, height = #data.results * rowH }
    nav.resultOffset = Scroll.clamp(nav.resultOffset, nav.list.height, nav.body.h)
    nav.grid, nav.fit = nil, nil
    return
  end
  nav.list = nil

  local defs = Nav.chipDefs(nav, data.ideaCount, spec, showField)
  local rects, used = Layout.flow(
    #defs,
    { x = inner.x, y = belowField, w = inner.w, h = inner.h },
    spec.chipMinWidth,
    math.max(spec.chipHeight, minTouch),
    spec.gap
  )
  nav.chips = {}
  for i, def in ipairs(defs) do
    local r = rects[i]
    r.kind, r.label = def.kind, def.label
    nav.chips[i] = r
  end
  local top = belowField + used + spec.gap
  nav.body = { x = inner.x, y = top, w = inner.w, h = math.max(1, inner.y + inner.h - top) }

  if nav.view == "focus" and data.chapters[nav.cur] then
    nav.grid = nil
    nav.fit = cachedFit(nav, data.chapters[nav.cur], nav.body, spec)
    nav.focusOffset = Scroll.clamp(nav.focusOffset, nav.fit.contentH, nav.body.h)
  else
    nav.view, nav.fit = "overview", nil
    nav.visible = Layout.visible(data.stats, nav.filter)
    nav.grid = Layout.overview(data.groups, nav.visible, nav.body.w, spec)
    nav.offset = Scroll.clamp(nav.offset, nav.grid.height, nav.body.h)
  end
end

--- Scroll the overview so the tile of chapter `index` sits at the top, under its area heading (after a
--- layout). Near the end of the grid it stops where the grid does.
function Nav.revealTile(nav, index, spec)
  local tile = nav.grid and nav.grid.tileOf[index]
  if tile then
    nav.offset = Scroll.clamp(tile.y - spec.headingHeight, nav.grid.height, nav.body.h)
  end
end

-- Input ----------------------------------------------------------------------------------------

--- Show node `id` in the middle of a scrolling chapter (after a layout, since the card changes the body).
--- With `onlyIfHidden` it leaves the scroll alone while the node is fully in view (a tap inside the chapter).
function Nav.revealNode(nav, id, onlyIfHidden)
  local fit = nav.fit
  local node = fit and fit.map.nodes[id]
  if not node then
    return
  end
  if onlyIfHidden then
    local top, bottom = node.y * fit.scale, (node.y + node.h) * fit.scale
    if top >= nav.focusOffset and bottom <= nav.focusOffset + nav.body.h then
      return
    end
  end
  nav.focusOffset = Layout.offsetForNode(fit, id, nav.body.h)
end

--- A drag (or arrow key) of dy pixels scrolls what is showing: the search results, the overview, or a very
--- large chapter (a chapter that fits does not scroll).
function Nav.drag(nav, dy)
  if nav.list then
    nav.resultOffset = Scroll.byDrag(nav.resultOffset, dy, nav.list.height, nav.body.h)
  elseif nav.grid then
    nav.offset = Scroll.byDrag(nav.offset, dy, nav.grid.height, nav.body.h)
  elseif nav.fit then
    nav.focusOffset = Scroll.byDrag(nav.focusOffset, dy, nav.fit.contentH, nav.body.h)
  end
end

function Nav.wheel(nav, steps, step)
  if nav.list then
    nav.resultOffset = Scroll.byWheel(nav.resultOffset, steps, step, nav.list.height, nav.body.h)
  elseif nav.grid then
    nav.offset = Scroll.byWheel(nav.offset, steps, step, nav.grid.height, nav.body.h)
  elseif nav.fit then
    nav.focusOffset = Scroll.byWheel(nav.focusOffset, steps, step, nav.fit.contentH, nav.body.h)
  end
end

--- The index of the search result row under (x, y), or nil.
function Nav.resultAt(nav, x, y)
  local b, list = nav.body, nav.list
  if not list or x < b.x or x >= b.x + b.w or y < b.y or y >= b.y + b.h then
    return nil
  end
  local index = math.floor((y - b.y + nav.resultOffset) / list.rowH) + 1
  return index <= list.count and index or nil
end

--- The chapter index of the tile under (x, y), or nil (overview only; tiles scrolled out of the body
--- cannot be hit).
function Nav.tileAt(nav, x, y)
  local b = nav.body
  if not nav.grid or x < b.x or x >= b.x + b.w or y < b.y or y >= b.y + b.h then
    return nil
  end
  local cx, cy = x - b.x, y - b.y + nav.offset
  for _, item in ipairs(nav.grid.items) do
    if item.kind == "tile" and cx >= item.x and cx < item.x + item.w and cy >= item.y and cy < item.y + item.h then
      return item.index
    end
  end
  return nil
end

return Nav
