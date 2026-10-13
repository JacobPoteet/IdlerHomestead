-- Journal navigation state and input geometry (GDD D81, #194). No drawing and no world access: the scene
-- feeds it plain data, so the transitions are testable. INTENTIONALLY MINIMAL (a temporary design).
--
--   nav = Nav.new()          { view = "overview" | "focus", cur = chapter index, filter, offset, ... }
--   Nav.layout(nav, data, free, spec, minTouch)   rebuilds the chip rects, the body and the grid / fit
--     data = { chapters, stats, groups, ideaCount }       free = the part of the map rect to use
-- After layout: nav.chips = { { kind, label, x, y, w, h } }, nav.body = rect, and either nav.grid
-- (overview, see Layout.overview) or nav.fit (focus, see Layout.fit).

local Layout = require("src.ui.journal_layout")
local Scroll = require("src.ui.scroll")

local Nav = {}

Nav.FILTERS = { "all", "known", "ideas", "locked" }

function Nav.new()
  return { view = "overview", cur = 1, filter = "all", offset = 0, fits = {}, chips = {}, body = { x = 0, y = 0, w = 0, h = 0 } }
end

-- Transitions ----------------------------------------------------------------------------------

function Nav.openChapter(nav, index)
  nav.cur, nav.view = index, "focus"
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
function Nav.chipDefs(nav, ideaCount, spec)
  local labels, defs = spec.labels, {}
  if nav.view == "focus" then
    defs[#defs + 1] = { kind = "back", label = labels.back }
  end
  defs[#defs + 1] = { kind = "queue", label = labels.queue }
  defs[#defs + 1] = { kind = "study", label = string.format(labels.study, ideaCount) }
  for _, filter in ipairs(Nav.FILTERS) do
    defs[#defs + 1] = { kind = filter, label = labels.filters[filter] }
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
  local defs = Nav.chipDefs(nav, data.ideaCount, spec)
  local rects, used = Layout.flow(#defs, inner, spec.chipMinWidth, math.max(spec.chipHeight, minTouch), spec.gap)
  nav.chips = {}
  for i, def in ipairs(defs) do
    local r = rects[i]
    r.kind, r.label = def.kind, def.label
    nav.chips[i] = r
  end
  local top = inner.y + used + spec.gap
  nav.body = { x = inner.x, y = top, w = inner.w, h = math.max(1, inner.y + inner.h - top) }

  if nav.view == "focus" and data.chapters[nav.cur] then
    nav.grid = nil
    nav.fit = cachedFit(nav, data.chapters[nav.cur], nav.body, spec)
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

--- A drag (or arrow key) of dy pixels scrolls the overview; the focus view never scrolls.
function Nav.drag(nav, dy)
  if nav.grid then
    nav.offset = Scroll.byDrag(nav.offset, dy, nav.grid.height, nav.body.h)
  end
end

function Nav.wheel(nav, steps, step)
  if nav.grid then
    nav.offset = Scroll.byWheel(nav.offset, steps, step, nav.grid.height, nav.body.h)
  end
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
