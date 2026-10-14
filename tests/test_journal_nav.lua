-- Journal navigation logic (D81, #194): grouping, the overview grid, jump targets, the chapter fit and
-- the nav state. Pure code, so no window is needed.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Journal = require("src.sim.systems.journal")
local Layout = require("src.ui.journal_layout")
local Nav = require("src.ui.journal_nav")

local tun = tuningLoader.load()
local spec = tun.ui.journal
local reg = Registry.new():loadAll()

--- A synthetic journal: `count` chapters of `size` nodes each, areas of `perArea` chapters (nil = none).
local function fake(count, size, perArea)
  local chapters = {}
  for c = 1, count do
    local nodes = {}
    for n = 1, size do
      nodes[n] = { id = "c" .. c .. "n" .. n, needs = { "note" .. ((c + n) % 5) } }
    end
    chapters[c] = {
      id = "c" .. c,
      name = "Chapter " .. c,
      nodes = nodes,
      area = perArea and ("Area " .. math.ceil(c / perArea)) or nil,
    }
  end
  return chapters
end

--- Status by node number: n1 known, n2 idea, n3 queued, the rest unknown.
local function statusOf(id)
  local n = tonumber(id:match("n(%d+)$"))
  return ({ "known", "idea", "queued" })[n] or "unknown"
end

T.test("journal nav: chapters carry their area, default for the rest", function()
  local chapters = Journal.chapters({ registry = reg })
  for _, chapter in ipairs(chapters) do
    T.truthy(chapter.area, chapter.id .. " has an area in content")
  end
  local groups = Layout.groups(fake(3, 2), "Other")
  T.eq(#groups, 1)
  T.eq(groups[1].name, "Other")
  T.eq(#groups[1].indices, 3)
end)

T.test("journal nav: groups keep first-appearance order and chapter order inside", function()
  local chapters = { { area = "B" }, { area = "A" }, { area = "B" }, { area = "A" }, {} }
  local groups = Layout.groups(chapters, "Other")
  T.eq(#groups, 3)
  T.eq(groups[1].name, "B")
  T.eq(groups[1].indices[2], 3)
  T.eq(groups[2].name, "A")
  T.eq(groups[3].name, "Other")
end)

T.test("journal nav: stats count known, ideas, locked and to-study", function()
  local s = Layout.stats(fake(1, 6)[1], statusOf)
  T.eq(s.total, 6)
  T.eq(s.known, 1)
  T.eq(s.ideas, 2) -- idea + queued
  T.eq(s.locked, 3)
  T.eq(s.toStudy, 1) -- the queued one is already handled
  T.truthy(Layout.matches("ideas", "studying"))
  T.falsy(Layout.matches("known", "idea"))
  T.truthy(Layout.matches("all", "unknown"))
end)

T.test("journal nav: filters hide chapters with nothing to show", function()
  local chapters = fake(2, 6)
  chapters[2].nodes = { chapters[2].nodes[1] } -- only a known node
  local stats = Layout.allStats(chapters, statusOf)
  local ideas = Layout.visible(stats, "ideas")
  T.eq(ideas[1], true)
  T.eq(ideas[2], false)
  T.eq(Layout.visible(stats, "all")[2], true)
end)

T.test("journal nav: overview grid fits the width, tiles are touch sized, nothing overlaps", function()
  local minTouch = tun.input.minTouchTarget
  for _, width in ipairs({ 358, 590, 1200 }) do
    local chapters = fake(40, 4, 7)
    local groups = Layout.groups(chapters, "Other")
    local grid = Layout.overview(groups, Layout.visible(Layout.allStats(chapters, statusOf), "all"), width, spec)
    local tiles = {}
    for _, item in ipairs(grid.items) do
      T.truthy(item.x >= 0 and item.x + item.w <= width, "item inside the width")
      if item.kind == "tile" then
        T.truthy(item.w >= minTouch and item.h >= minTouch, "tile at least the touch size")
        tiles[#tiles + 1] = item
      end
    end
    T.eq(#tiles, 40)
    for i = 1, #tiles do
      for j = i + 1, #tiles do
        local a, b = tiles[i], tiles[j]
        T.falsy(a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h, "tiles overlap")
      end
    end
    T.truthy(grid.height > 0)
  end
end)

T.test("journal nav: 120 chapters stay one scrolling column set, never wider than the view", function()
  local chapters = fake(120, 5, 8)
  local groups = Layout.groups(chapters, "Other")
  T.eq(#groups, 15)
  local grid = Layout.overview(groups, Layout.visible(Layout.allStats(chapters, statusOf), "all"), 358, spec)
  T.eq(grid.cols, 3)
  local headings, tiles = 0, 0
  for _, item in ipairs(grid.items) do
    headings = headings + (item.kind == "heading" and 1 or 0)
    tiles = tiles + (item.kind == "tile" and 1 or 0)
    T.truthy(item.x + item.w <= 358)
  end
  T.eq(headings, 15)
  T.eq(tiles, 120)
  T.truthy(grid.height > 1000, "content is tall and scrolls")
end)

T.test("journal nav: a filter that hides every chapter leaves an empty grid", function()
  local chapters = fake(3, 1) -- one known node each
  local stats = Layout.allStats(chapters, statusOf)
  local grid = Layout.overview(Layout.groups(chapters, "Other"), Layout.visible(stats, "ideas"), 358, spec)
  T.eq(#grid.items, 0)
  T.eq(grid.height, 0)
end)

T.test("journal nav: jump targets", function()
  T.eq(Layout.queueTarget({ "a", "b" }), "a")
  T.eq(Layout.queueTarget({}), nil)
  T.eq(Layout.nextIdea({ "a", "b", "c" }, nil), "a")
  T.eq(Layout.nextIdea({ "a", "b", "c" }, "a"), "b")
  T.eq(Layout.nextIdea({ "a", "b", "c" }, "c"), "a")
  T.eq(Layout.nextIdea({ "a", "b" }, "zzz"), "a")
  T.eq(Layout.nextIdea({}, "a"), nil)
  T.eq(Layout.startTarget({ "q" }, { "i" }), "q")
  T.eq(Layout.startTarget({}, { "i" }), "i")
  local chapters = fake(120, 4)
  T.eq(Layout.chapterIndexOf(chapters, "c77n3"), 77)
  T.eq(Layout.chapterIndexOf(chapters, "nope"), nil)
end)

T.test("journal nav: scrollTo moves the least amount", function()
  local item = { y = 300, h = 60 }
  T.eq(Layout.scrollTo(0, item, 200), 160)
  T.eq(Layout.scrollTo(250, item, 200), 250)
  T.eq(Layout.scrollTo(400, item, 200), 300)
end)

T.test("journal nav: every real chapter fits every supported view without panning", function()
  local chapters = Journal.chapters({ registry = reg })
  local bodies = { { 1200, 420 }, { 340, 300 }, { 560, 120 }, { 300, 150 } }
  for _, size in ipairs(bodies) do
    local body = { x = 10, y = 20, w = size[1], h = size[2] }
    for _, chapter in ipairs(chapters) do
      local fit = Layout.fit(chapter, body, spec)
      T.truthy(fit.w <= body.w + 0.5 and fit.h <= body.h + 0.5, chapter.id .. " fits " .. size[1] .. "x" .. size[2])
      T.truthy(fit.ox >= body.x and fit.oy >= body.y)
      T.truthy(fit.scale <= spec.fitMaxScale)
    end
  end
end)

T.test("journal nav: a short wide view splits a chapter into columns for a bigger scale", function()
  local chapter = Journal.chapters({ registry = reg })[1]
  local tall = Layout.fit(chapter, { x = 0, y = 0, w = 800, h = 600 }, spec)
  local short = Layout.fit(chapter, { x = 0, y = 0, w = 800, h = 140 }, spec)
  T.truthy(short.columns > tall.columns)
  T.truthy(short.scale > 0.4)
end)

T.test("journal nav: taps in a fitted chapter hit its nodes and stamps", function()
  local chapter = Journal.chapters({ registry = reg })[1]
  local fit = Layout.fit(chapter, { x = 50, y = 40, w = 600, h = 400 }, spec)
  local node = fit.map.regions[1].nodes[1]
  local x, y = fit.ox + (node.x + node.w / 2) * fit.scale, fit.oy + (node.y + node.h / 2) * fit.scale
  local kind, id = Layout.hit(fit, x, y)
  T.eq(kind, "node")
  T.eq(id, node.id)
  local stamp = fit.map.regions[1].stamps[1]
  if stamp then
    local kind2, id2 = Layout.hit(fit, fit.ox + (stamp.x + 2) * fit.scale, fit.oy + (stamp.y + 2) * fit.scale)
    T.eq(kind2, "note")
    T.eq(id2, stamp.note)
  end
  T.eq(Layout.hit(fit, 0, 0), nil)
end)

T.test("journal nav: card slot goes beside the chapter on wide short views only", function()
  local _, _, side = Layout.cardSlot({ x = 0, y = 0, w = 800, h = 200 }, 64, spec)
  T.eq(side, true)
  local card, h, below = Layout.cardSlot({ x = 0, y = 0, w = 366, h = 500 }, 64, spec)
  T.eq(below, false)
  T.eq(h, 64)
  local free = Layout.freeRect({ x = 0, y = 0, w = 366, h = 500 }, card, false, spec)
  T.truthy(free.y + free.h <= card.y)
  local sideCard = Layout.cardSlot({ x = 0, y = 0, w = 800, h = 200 }, 64, spec)
  local freeSide = Layout.freeRect({ x = 0, y = 0, w = 800, h = 200 }, sideCard, true, spec)
  T.truthy(freeSide.x + freeSide.w <= sideCard.x)
end)

T.test("journal nav: nav state lays out chips and the overview, opens and leaves a chapter", function()
  local chapters = fake(60, 5, 6)
  local nav = Nav.new()
  local data = {
    chapters = chapters,
    stats = Layout.allStats(chapters, statusOf),
    groups = Layout.groups(chapters, "Other"),
    ideaCount = 60,
  }
  local free = { x = 0, y = 0, w = 366, h = 300 }
  Nav.layout(nav, data, free, spec, tun.input.minTouchTarget)
  T.eq(nav.view, "overview")
  T.truthy(nav.grid)
  for _, chip in ipairs(nav.chips) do
    T.truthy(chip.h >= tun.input.minTouchTarget and chip.w >= tun.input.minTouchTarget, "chip touch size")
    T.truthy(chip.x >= free.x and chip.x + chip.w <= free.x + free.w, "chip inside")
  end
  T.truthy(nav.body.y > free.y)

  -- Scrolling clamps; tiles scrolled out of the body cannot be tapped.
  Nav.drag(nav, -100000)
  T.eq(nav.offset, nav.grid.height - nav.body.h)
  Nav.drag(nav, 100000)
  T.eq(nav.offset, 0)
  Nav.wheel(nav, -3, spec.wheelStep)
  T.eq(nav.offset, 3 * spec.wheelStep)
  local first = nav.grid.tileOf[1]
  T.eq(Nav.tileAt(nav, nav.body.x + first.x + 2, nav.body.y + first.y - nav.offset + 2), nil)
  Nav.revealTile(nav, 60, spec)
  local tile = nav.grid.tileOf[60]
  T.eq(Nav.tileAt(nav, nav.body.x + tile.x + 2, nav.body.y + tile.y - nav.offset + 2), 60)

  -- Focus: no scrolling, a back chip appears.
  Nav.openChapter(nav, 60)
  Nav.layout(nav, data, free, spec, tun.input.minTouchTarget)
  T.eq(nav.view, "focus")
  T.eq(nav.chips[1].kind, "back")
  T.truthy(nav.fit and not nav.grid)
  local before = nav.offset
  Nav.drag(nav, 50)
  T.eq(nav.offset, before)
  Nav.backToOverview(nav)
  Nav.layout(nav, data, free, spec, tun.input.minTouchTarget)
  T.eq(nav.view, "overview")

  -- A filter resets the scroll and hides chapters with no match.
  Nav.setFilter(nav, "locked")
  T.eq(nav.offset, 0)
  Nav.layout(nav, data, free, spec, tun.input.minTouchTarget)
  T.truthy(nav.grid.tileOf[1])
end)

T.test("journal nav: phone, landscape and desktop chip rows fit and leave room for the body", function()
  local chapters = fake(10, 5, 5)
  local data = {
    chapters = chapters,
    stats = Layout.allStats(chapters, statusOf),
    groups = Layout.groups(chapters, "Other"),
    ideaCount = 3,
  }
  for _, size in ipairs({ { 366, 380 }, { 820, 150 }, { 700, 300 } }) do
    local nav = Nav.new()
    Nav.openChapter(nav, 1)
    Nav.layout(nav, data, { x = 0, y = 0, w = size[1], h = size[2] }, spec, tun.input.minTouchTarget)
    T.truthy(nav.body.h >= size[2] / 2, "chips leave at least half the height at " .. size[1] .. "x" .. size[2])
    T.truthy(nav.fit.scale > 0.3)
  end
end)
