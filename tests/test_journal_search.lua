-- Journal search by name, the remembered chapter, the text field and the scrolling of a very large chapter
-- (D120, #208). Pure code, so no window is needed.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Layout = require("src.ui.journal_layout")
local Nav = require("src.ui.journal_nav")
local Search = require("src.ui.journal_search")
local TextField = require("src.ui.text_field")

local tun = tuningLoader.load()
local spec = tun.ui.journal

local function names(results)
  local out = {}
  for i, r in ipairs(results) do
    out[i] = r.id
  end
  return table.concat(out, ",")
end

--- Two chapters; every node is "known" except those listed in `hidden` (status "unknown").
local function journal(hiddenName)
  return {
    {
      id = "tools",
      name = "Tools",
      nodes = {
        { id = "axe", name = "Stone Axe" },
        { id = "pick", name = "Iron Pickaxe" },
        { id = "secret", name = hiddenName or "Secret Axe Plans" },
      },
    },
    { id = "farm", name = "Farm", nodes = { { id = "hoe", name = "Hoe" }, { id = "waxed", name = "Waxed Coat" } } },
  }
end

local function statusOf(id)
  return ({ axe = "known", pick = "idea", secret = "unknown", hoe = "queued", waxed = "studying" })[id]
end

T.test("journal search: matches known names, case-insensitive substring, in journal order", function()
  local results = Search.find(journal(), statusOf, "AX")
  T.eq(names(results), "axe,pick,waxed")
  T.eq(results[1].chapter, 1)
  T.eq(results[3].chapter, 2)
  T.eq(results[3].chapterName, "Farm")
  T.eq(results[3].status, "studying")
  T.eq(names(Search.find(journal(), statusOf, "  iron pick ")), "pick")
  T.eq(names(Search.find(journal(), statusOf, "o")), "axe,pick,hoe,waxed")
end)

T.test("journal search: an empty query is no search, no match is an empty list", function()
  T.eq(Search.find(journal(), statusOf, ""), nil)
  T.eq(Search.find(journal(), statusOf, "   "), nil)
  T.eq(#Search.find(journal(), statusOf, "zzz"), 0)
  T.eq(#Search.find(journal(), statusOf, "%"), 0, "patterns are plain text")
end)

T.test("journal search: an unknown node never matches and never changes the answer", function()
  -- "Secret Axe Plans" contains "axe" and "secret" but is still ???: it must not be listed ...
  T.eq(names(Search.find(journal(), statusOf, "secret")), "")
  T.truthy(not names(Search.find(journal(), statusOf, "axe")):find("secret"))
  -- ... and the result for any query is identical whatever the hidden node is called (no count leak).
  for _, q in ipairs({ "axe", "secret", "plans", "a", "e", "zzz" }) do
    local a = Search.find(journal("Secret Axe Plans"), statusOf, q)
    local b = Search.find(journal("Totally Different"), statusOf, q)
    T.eq(names(a), names(b), "query " .. q)
    T.eq(#a, #b)
  end
  -- The name of an unknown node is not even read.
  local trap = journal()
  trap[1].nodes[3].name = nil
  T.eq(names(Search.find(trap, statusOf, "axe")), "axe,pick,waxed")
end)

T.test("journal search: the remembered chapter reopens, or falls back when it is gone", function()
  local chapters = journal()
  T.eq(Search.rememberedIndex(chapters, "farm"), 2)
  T.eq(Search.rememberedIndex(chapters, "tools"), 1)
  T.eq(Search.rememberedIndex(chapters, "deleted"), nil)
  T.eq(Search.rememberedIndex(chapters, nil), nil)
end)

T.test("text field: typing, backspace, limit and UTF-8", function()
  local f = TextField.new(5)
  T.truthy(f:isEmpty())
  f:insert("ab")
  f:insert("c\n\td")
  T.eq(f.text, "abcd")
  f:insert("efgh")
  T.eq(f.text, "abcde", "cut at the limit")
  f:backspace()
  T.eq(f.text, "abcd")
  f:clear()
  T.truthy(f:isEmpty())
  f:backspace()
  T.eq(f.text, "")
  f:insert("h\u{e9}\u{e9}")
  f:backspace()
  T.eq(f.text, "h\u{e9}", "a whole character goes")
end)

--- A chapter with `count` nodes, each needing a note.
local function big(count)
  local nodes = {}
  for n = 1, count do
    nodes[n] = { id = "n" .. n, name = "Node " .. n, needs = { "note" .. (n % 7) } }
  end
  return { id = "big", name = "Big", nodes = nodes }
end

T.test("large chapter: more than scrollNodes nodes keep the readable scale and scroll", function()
  local body = { x = 10, y = 20, w = 700, h = 260 }
  local small = Layout.fit(big(spec.scrollNodes), body, spec)
  T.truthy(small.contentH <= body.h + 0.5, "at the limit it still fits the view")
  local fit = Layout.fit(big(spec.scrollNodes + 30), body, spec)
  T.eq(fit.scale, spec.readScale)
  T.truthy(fit.contentH > body.h, "taller than the view, so it scrolls")
  T.truthy(fit.w <= body.w + 0.5, "never wider than the view")
  T.truthy(fit.ox >= body.x and fit.oy == body.y)
  -- A narrow view uses fewer columns, a wide one more, and the content height follows.
  local narrow = Layout.fit(big(60), { x = 0, y = 0, w = 200, h = 260 }, spec)
  local wide = Layout.fit(big(60), { x = 0, y = 0, w = 900, h = 260 }, spec)
  T.truthy(narrow.columns < wide.columns)
  T.truthy(narrow.contentH > wide.contentH)
  T.eq(narrow.scale, spec.readScale)
end)

T.test("large chapter: reveal centres a node, hits honour the scroll offset", function()
  local nav = Nav.new()
  local chapters = { big(80) }
  local data = { chapters = chapters, stats = Layout.allStats(chapters, function() return "known" end), groups = Layout.groups(chapters, "Other"), ideaCount = 0 }
  Nav.openChapter(nav, 1)
  Nav.layout(nav, data, { x = 0, y = 0, w = 400, h = 300 }, spec, tun.input.minTouchTarget)
  local fit = nav.fit
  T.truthy(fit.contentH > nav.body.h)
  T.eq(nav.focusOffset, 0)

  -- Dragging and the wheel scroll the chapter and clamp at both ends.
  Nav.drag(nav, -100000)
  T.eq(nav.focusOffset, fit.contentH - nav.body.h)
  Nav.drag(nav, 100000)
  T.eq(nav.focusOffset, 0)
  Nav.wheel(nav, -2, spec.wheelStep)
  T.eq(nav.focusOffset, 2 * spec.wheelStep)

  -- Reveal a node far down; a tap at its on-screen centre then hits it.
  local target = fit.map.nodes["n70"]
  Nav.revealNode(nav, "n70")
  local y = nav.body.y + (target.y + target.h / 2) * fit.scale - nav.focusOffset
  T.truthy(y >= nav.body.y and y <= nav.body.y + nav.body.h, "centred into view")
  local x = fit.ox + (target.x + target.w / 2) * fit.scale
  local kind, id = Layout.hit(fit, x, y - nav.body.y + fit.oy, nav.focusOffset)
  T.eq(kind, "node")
  T.eq(id, "n70")

  -- A node already in view is left alone by an "only if hidden" reveal; a hidden one is brought in.
  local before = nav.focusOffset
  Nav.revealNode(nav, "n70", true)
  T.eq(nav.focusOffset, before)
  Nav.revealNode(nav, "n1", true)
  T.truthy(nav.focusOffset < before)

  -- Opening a chapter starts at the top; a chapter that fits never scrolls.
  Nav.openChapter(nav, 1)
  T.eq(nav.focusOffset, 0)
end)

T.test("journal search: result list layout, scrolling and row hits", function()
  local chapters = { big(5) }
  local nav = Nav.new()
  local results = {}
  for i = 1, 200 do
    results[i] = { id = "n" .. i, name = "Node " .. i, chapter = 1, chapterName = "Big", status = "known" }
  end
  local data = { chapters = chapters, stats = Layout.allStats(chapters, function() return "known" end), groups = Layout.groups(chapters, "Other"), ideaCount = 0, results = results }
  Nav.layout(nav, data, { x = 0, y = 0, w = 366, h = 380 }, spec, tun.input.minTouchTarget)
  T.eq(#nav.chips, 0, "no chips while searching")
  T.truthy(nav.field.h >= tun.input.minTouchTarget and nav.clear.h >= tun.input.minTouchTarget and nav.clear.w >= tun.input.minTouchTarget)
  T.truthy(nav.field.x + nav.field.w <= nav.clear.x, "field and clear do not overlap")
  T.truthy(nav.list.rowH >= tun.input.minTouchTarget)
  T.eq(nav.list.height, 200 * nav.list.rowH)
  T.eq(Nav.resultAt(nav, nav.body.x + 5, nav.body.y + 1), 1)
  T.eq(Nav.resultAt(nav, nav.body.x + 5, nav.body.y + nav.list.rowH + 1), 2)
  Nav.wheel(nav, -3, spec.wheelStep)
  T.eq(nav.resultOffset, 3 * spec.wheelStep)
  Nav.drag(nav, -1e6)
  T.eq(nav.resultOffset, nav.list.height - nav.body.h)
  T.eq(Nav.resultAt(nav, nav.body.x + 5, nav.body.y + nav.body.h - 1), 200)
  T.eq(Nav.resultAt(nav, nav.body.x - 5, nav.body.y), nil)
  -- No results at all: no rows to hit.
  data.results = {}
  Nav.layout(nav, data, { x = 0, y = 0, w = 366, h = 380 }, spec, tun.input.minTouchTarget)
  T.eq(nav.resultOffset, 0)
  T.eq(Nav.resultAt(nav, nav.body.x + 5, nav.body.y + 1), nil)
  -- Clearing the search brings the chips back.
  data.results, data.showField = nil, false
  Nav.layout(nav, data, { x = 0, y = 0, w = 366, h = 380 }, spec, tun.input.minTouchTarget)
  T.truthy(#nav.chips > 0 and nav.list == nil and nav.clear == nil and nav.field == nil)
  local hasSearchChip = false
  for _, chip in ipairs(nav.chips) do
    hasSearchChip = hasSearchChip or chip.kind == "search"
  end
  T.truthy(hasSearchChip, "a chip opens the field")
  -- With the field open the chip row stays (nothing typed yet) but the field takes the top row and the chip goes.
  data.showField = true
  Nav.layout(nav, data, { x = 0, y = 0, w = 366, h = 380 }, spec, tun.input.minTouchTarget)
  T.truthy(nav.field and nav.clear and #nav.chips > 0 and nav.chips[1].y > nav.field.y + nav.field.h - 1)
  for _, chip in ipairs(nav.chips) do
    T.truthy(chip.kind ~= "search")
  end
end)
