-- Journal navigation layout (GDD D81, #194). Pure geometry and bookkeeping, no drawing and no world:
-- everything takes plain lists and a `spec` (tuning.ui.journal), so it is unit-tested headless
-- (tests/test_journal_nav.lua). INTENTIONALLY MINIMAL: a temporary design that will be revisited.
--
--   chapters = Journal.chapters(world): { { id, name, area?, nodes = { def } } }
--   statusOf(id) -> "known" | "idea" | "queued" | "studying" | "unknown"
--
-- Overview: chapters grouped under area headings (content field `area`), tiles in a scrolling grid.
-- Focus: one chapter fitted to the view (JournalMap regions, split into side-by-side columns when
-- that gives a bigger scale), plus where the node card goes and the hit test for taps.

local JournalMap = require("src.ui.journal_map")

local Layout = {}

-- Status ---------------------------------------------------------------------------------------

--- The filter bucket a node status falls in: "known", "ideas" (idea, queued, studying) or "locked".
function Layout.kindOf(status)
  if status == "known" then
    return "known"
  elseif status == "unknown" then
    return "locked"
  end
  return "ideas"
end

--- Does a node of this status pass the filter ("all", "known", "ideas", "locked")?
function Layout.matches(filter, status)
  return filter == nil or filter == "all" or Layout.kindOf(status) == filter
end

--- Counts for one chapter: { total, known, ideas, locked, toStudy }. toStudy is the ideas nobody has
--- queued yet (what the player can act on).
function Layout.stats(chapter, statusOf)
  local s = { total = #chapter.nodes, known = 0, ideas = 0, locked = 0, toStudy = 0 }
  for _, def in ipairs(chapter.nodes) do
    local status = statusOf(def.id)
    local kind = Layout.kindOf(status)
    s[kind] = s[kind] + 1
    if status == "idea" then
      s.toStudy = s.toStudy + 1
    end
  end
  return s
end

--- Stats for every chapter, by chapter index.
function Layout.allStats(chapters, statusOf)
  local out = {}
  for i, chapter in ipairs(chapters) do
    out[i] = Layout.stats(chapter, statusOf)
  end
  return out
end

--- Chapters shown under a filter: all of them, or those holding a node that passes it.
function Layout.visible(stats, filter)
  local out = {}
  for i, s in ipairs(stats) do
    out[i] = filter == nil or filter == "all" or s[filter] > 0
  end
  return out
end

-- Grouping -------------------------------------------------------------------------------------

--- Area groups in order of first appearance: { { name, indices = { chapterIndex, ... } } }. A chapter
--- with no `area` goes under `defaultArea`.
function Layout.groups(chapters, defaultArea)
  local groups, byName = {}, {}
  for i, chapter in ipairs(chapters) do
    local name = chapter.area or defaultArea
    local group = byName[name]
    if not group then
      group = { name = name, indices = {} }
      byName[name] = group
      groups[#groups + 1] = group
    end
    group.indices[#group.indices + 1] = i
  end
  return groups
end

-- Overview grid --------------------------------------------------------------------------------

--- Lay the visible chapters out as a scrolling grid of tiles under area headings, `width` wide.
--- Returns { items, height, cols, tileOf } with items = { { kind = "heading", name, x, y, w, h } or
--- { kind = "tile", index, x, y, w, h } } in content coordinates (y from 0).
function Layout.overview(groups, visible, width, spec)
  local gap = spec.gap
  local cols = math.max(1, math.floor((width + gap) / (spec.tileMinWidth + gap)))
  local tileW = math.floor((width - (cols - 1) * gap) / cols)
  local items, tileOf, y = {}, {}, 0
  for _, group in ipairs(groups) do
    local shown = {}
    for _, index in ipairs(group.indices) do
      if visible[index] then
        shown[#shown + 1] = index
      end
    end
    if #shown > 0 then
      items[#items + 1] = { kind = "heading", name = group.name, x = 0, y = y, w = width, h = spec.headingHeight }
      y = y + spec.headingHeight
      for n, index in ipairs(shown) do
        local col, row = (n - 1) % cols, math.floor((n - 1) / cols)
        local tile = { kind = "tile", index = index, x = col * (tileW + gap), y = y + row * (spec.tileHeight + gap), w = tileW, h = spec.tileHeight }
        items[#items + 1] = tile
        tileOf[index] = tile
      end
      y = y + math.ceil(#shown / cols) * (spec.tileHeight + gap) + spec.groupGap
    end
  end
  return { items = items, height = math.max(0, y - spec.groupGap), cols = cols, tileOf = tileOf }
end

--- The scroll offset that brings a content rectangle fully into a view of height `viewH`, moving as
--- little as possible from `offset`.
function Layout.scrollTo(offset, item, viewH)
  if item.y < offset then
    return item.y
  elseif item.y + item.h > offset + viewH then
    return item.y + item.h - viewH
  end
  return offset
end

-- Chips ----------------------------------------------------------------------------------------

--- Lay `count` equal cells in rows inside `rect` (at least `minW` wide, `h` tall). Returns the rects and
--- the total height used.
function Layout.flow(count, rect, minW, h, gap)
  if count == 0 then
    return {}, 0
  end
  local cols = math.max(1, math.min(count, math.floor((rect.w + gap) / (minW + gap))))
  local rows = math.ceil(count / cols)
  local cellW = math.floor((rect.w - (cols - 1) * gap) / cols)
  local out = {}
  for i = 1, count do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    out[i] = { x = rect.x + col * (cellW + gap), y = rect.y + row * (h + gap), w = cellW, h = h }
  end
  return out, rows * (h + gap) - gap
end

-- Jump targets ---------------------------------------------------------------------------------

--- Index of the chapter holding node `id`, or nil.
function Layout.chapterIndexOf(chapters, id)
  for i, chapter in ipairs(chapters) do
    for _, def in ipairs(chapter.nodes) do
      if def.id == id then
        return i
      end
    end
  end
  return nil
end

--- The node the "Queue" chip jumps to: the head of the study queue.
function Layout.queueTarget(queue)
  return queue[1]
end

--- The node the "To study" chip jumps to: the idea after `current` in `ideas` (a list of ids), wrapping;
--- the first idea when `current` is not one.
function Layout.nextIdea(ideas, current)
  if #ideas == 0 then
    return nil
  end
  for i, id in ipairs(ideas) do
    if id == current then
      return ideas[i % #ideas + 1]
    end
  end
  return ideas[1]
end

--- The node the Journal opens on: the head of the queue, else the first idea.
function Layout.startTarget(queue, ideas)
  return queue[1] or ideas[1]
end

-- Focus: one chapter fitted to the view ----------------------------------------------------------

--- The best arrangement of `chapter` inside `body` ({ x, y, w, h }): its nodes split over k side-by-side
--- sub-regions, keeping the k with the biggest scale (capped at spec.fitMaxScale). Returns
--- { map, scale, w, h, ox, oy, columns } with (ox, oy) the map's top-left in the same space as `body`.
function Layout.fit(chapter, body, spec)
  local nodes = chapter.nodes
  if #nodes > spec.scrollNodes then
    return Layout.fitScrolling(chapter, body, spec)
  end
  local best
  for k = 1, math.min(#nodes, spec.fitMaxColumns) do
    local per = math.ceil(#nodes / k)
    local parts, i = {}, 1
    while i <= #nodes do
      local slice = {}
      for j = i, math.min(i + per - 1, #nodes) do
        slice[#slice + 1] = nodes[j]
      end
      local name = #parts == 0 and chapter.name or (chapter.name .. spec.labels.continued)
      parts[#parts + 1] = { id = chapter.id .. "#" .. #parts, name = name, nodes = slice }
      i = i + per
    end
    local map = JournalMap.build(parts, 0)
    local scale = math.min(body.w / map.w, body.h / map.h, spec.fitMaxScale)
    if not best or scale > best.scale + spec.fitTolerance then
      best = { map = map, scale = scale, columns = #parts }
    end
  end
  best.w, best.h = best.map.w * best.scale, best.map.h * best.scale
  best.ox = body.x + math.floor((body.w - best.w) / 2)
  best.oy = body.y + math.floor((body.h - best.h) / 2)
  best.contentH = best.h
  return best
end

--- A very large chapter (more than spec.scrollNodes nodes) is not shrunk: it is drawn at spec.readScale and
--- scrolls up and down (D120, #208). The nodes are split over as many side-by-side columns as fit the body's
--- width at that scale (up to spec.fitMaxColumns), which keeps the scroll as short as it can be. Same result
--- shape as the fitted layout, with `contentH` the full height (taller than `body.h` when it scrolls); (ox, oy)
--- is the map's top-left at scroll offset 0.
function Layout.fitScrolling(chapter, body, spec)
  local nodes, scale = chapter.nodes, spec.readScale
  local best
  for k = 1, math.min(#nodes, spec.fitMaxColumns) do
    local per = math.ceil(#nodes / k)
    local parts, i = {}, 1
    while i <= #nodes do
      local slice = {}
      for j = i, math.min(i + per - 1, #nodes) do
        slice[#slice + 1] = nodes[j]
      end
      local name = #parts == 0 and chapter.name or (chapter.name .. spec.labels.continued)
      parts[#parts + 1] = { id = chapter.id .. "#" .. #parts, name = name, nodes = slice }
      i = i + per
    end
    local map = JournalMap.build(parts, 0)
    -- Keep the most columns that still fit the width (the first column count always counts).
    if k == 1 or map.w * scale <= body.w then
      best = { map = map, scale = scale, columns = #parts }
    end
  end
  best.w, best.h = best.map.w * scale, best.map.h * scale
  best.ox = body.x + math.floor((body.w - best.w) / 2)
  best.contentH = best.h
  best.oy = best.h < body.h and body.y + math.floor((body.h - best.h) / 2) or body.y
  return best
end

--- The scroll offset that puts node `id` in the middle of a body of height `viewH` showing `fit` (clamped
--- to the content). 0 when the chapter does not scroll or the node is not in it.
function Layout.offsetForNode(fit, id, viewH)
  local node = fit.map.nodes[id]
  if not node or fit.contentH <= viewH then
    return 0
  end
  local middle = (node.y + node.h / 2) * fit.scale
  return math.max(0, math.min(middle - viewH / 2, fit.contentH - viewH))
end

local function inside(r, x, y)
  return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--- What a tap at (x, y) hits in a fitted chapter: "node", id or "note", id, else nil.
function Layout.hit(fit, x, y, offset)
  local mx, my = (x - fit.ox) / fit.scale, (y - fit.oy + (offset or 0)) / fit.scale
  for _, region in ipairs(fit.map.regions) do
    for _, node in ipairs(region.nodes) do
      if inside(node, mx, my) then
        return "node", node.id
      end
    end
    for _, stamp in ipairs(region.stamps) do
      if inside(stamp, mx, my) then
        return "note", stamp.note
      end
    end
  end
  return nil
end

-- The node card's slot ---------------------------------------------------------------------------

--- Where the node card sits inside the map rect `r`: along the bottom normally, down the right side on
--- wide, short views so the chapter stays visible. Returns the card rect, its height and `side`.
function Layout.cardSlot(r, cardH, spec)
  if r.w > spec.sideCardMinViewWidth and r.h < spec.sideCardMaxViewHeight then
    local h = r.h - 2 * spec.pad
    return { x = r.x + r.w - spec.sideCardWidth - spec.pad, y = r.y + spec.pad, w = spec.sideCardWidth, h = h }, h, true
  end
  return { x = r.x + spec.pad, y = r.y + r.h - cardH - spec.pad, w = r.w - 2 * spec.pad, h = cardH }, cardH, false
end

--- What is left of the map rect `r` once the open card (rect `card`) has its share.
function Layout.freeRect(r, card, side, spec)
  if not card then
    return { x = r.x, y = r.y, w = r.w, h = r.h }
  elseif side then
    return { x = r.x, y = r.y, w = card.x - r.x - spec.pad, h = r.h }
  end
  return { x = r.x, y = r.y, w = r.w, h = card.y - r.y - spec.pad }
end

return Layout
