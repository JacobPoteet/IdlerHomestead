-- The Notebook and the Ledger (GDD §9.4, D140, D143, #296): the pages of each book, the shortcuts that open a
-- page, the page each book remembers within a session, the tab strip's layout, and the book scene hosting every
-- former panel at the checked view sizes.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Books = require("src.ui.books")
local Book = require("src.scenes.book")

local tun = tuningLoader.load()
local cfg = tun.ui.book
local reg = Registry.new():loadAll()
local minTouch = tun.input.minTouchTarget

local SIZES = {
  { name = "widget", w = 640, h = 360 },
  { name = "phone", w = 390, h = 844 },
  { name = "landscape", w = 844, h = 390 },
  { name = "desktop", w = 1280, h = 720 },
}

local function ids(book)
  local out = {}
  for _, page in ipairs(Books.pages(cfg, book)) do
    out[#out + 1] = page.id
  end
  return out
end

T.test("books: the Notebook and the Ledger hold the D140 pages in order", function()
  T.same(ids("notebook"), { "journal", "fish", "diary" })
  T.same(ids("ledger"), { "pantry", "routine", "catalog", "truck" })
  T.errors(function()
    Books.pages(cfg, "almanac")
  end, "unknown book")
end)

T.test("books: every shortcut lands on a real page of a real book", function()
  for name, target in pairs(cfg.shortcuts) do
    local book, page = Books.shortcut(cfg, name)
    T.eq(book, target[1])
    T.truthy(cfg.tabs[book], name .. " names a book")
    local found = false
    for _, p in ipairs(cfg.tabs[book]) do
      found = found or p.id == page
    end
    T.truthy(found, name .. " names a page of " .. book)
  end
  T.errors(function()
    Books.shortcut(cfg, "attic")
  end, "unknown book shortcut")
end)

T.test("books: the world's taps route to their pages (truck, camp, shack)", function()
  local function route(objectId)
    return Books.shortcut(cfg, reg:get("objects", objectId).book)
  end
  local book, page = route("truck")
  T.eq(book, "ledger")
  T.eq(page, "truck")
  for _, id in ipairs({ "camp", "shack" }) do
    book, page = route(id)
    T.eq(book, "ledger", id)
    T.eq(page, "pantry", id)
  end
  book, page = Books.shortcut(cfg, "journal")
  T.eq(book, "notebook")
  T.eq(page, "journal")
  book, page = Books.shortcut(cfg, "buildings")
  T.eq(page, "catalog", "Order more opens the Catalog tab")
  book, page = Books.shortcut(cfg, "log")
  T.eq(page, "diary")
end)

T.test("books: a book opens on its first page, then the one it was last left on", function()
  Books.reset()
  T.eq(Books.page(cfg, "ledger"), "pantry")
  T.eq(Books.page(cfg, "notebook"), "journal")
  Books.remember(cfg, "ledger", "catalog")
  T.eq(Books.page(cfg, "ledger"), "catalog")
  T.eq(Books.page(cfg, "notebook"), "journal", "the other book keeps its own page")
  T.eq(Books.page(cfg, "ledger", "truck"), "truck", "a shortcut's page wins")
  T.eq(Books.page(cfg, "ledger", "diary"), "catalog", "a page of the other book is ignored")
  Books.remember(cfg, "ledger", "truck")
  T.eq(Books.last("ledger"), "truck")
  T.errors(function()
    Books.remember(cfg, "ledger", "diary")
  end, "no page")
  Books.reset()
  T.eq(Books.last("ledger"), nil, "a new session forgets")
  T.eq(Books.page(cfg, "ledger"), "pantry")
end)

T.test("books: the layout keeps the paper, tabs and page inside every view", function()
  for _, size in ipairs(SIZES) do
    for _, book in ipairs({ "notebook", "ledger" }) do
      local r = Books.rects(cfg, size, book, minTouch)
      local where = book .. " " .. size.name
      T.truthy(r.paper.x >= 0 and r.paper.y >= 0, where)
      T.truthy(r.paper.x + r.paper.w <= size.w and r.paper.y + r.paper.h <= size.h, where .. ": paper in view")
      T.truthy(r.strip.h >= minTouch, where .. ": the tab strip is a touch target tall")
      T.truthy(r.body.y >= r.strip.y + r.strip.h, where .. ": the page sits under the tabs")
      T.eq(r.body.y + r.body.h, r.paper.y + r.paper.h, where)
    end
  end
end)

T.test("books: tabs are touch targets that never overlap; narrow strips keep only the open label", function()
  local function measure(label)
    return #label * 6
  end
  for _, size in ipairs(SIZES) do
    for _, book in ipairs({ "notebook", "ledger" }) do
      local pages = Books.pages(cfg, book)
      local rects = Books.rects(cfg, size, book, minTouch)
      for _, page in ipairs(pages) do
        local lay = Books.layoutTabs(cfg, pages, page.id, rects.strip, minTouch, measure, 12)
        local where = book .. " " .. size.name .. " on " .. page.id
        local right = rects.strip.x
        for _, tab in ipairs(lay.tabs) do
          T.truthy(tab.w >= minTouch and tab.h >= minTouch, where .. ": " .. tab.id .. " is a touch target")
          T.truthy(tab.x >= right, where .. ": " .. tab.id .. " overlaps the one before")
          right = tab.x + tab.w
          if tab.id == page.id then
            T.truthy(tab.label, where .. ": the open tab says its name")
          end
        end
        T.truthy(right <= lay.close.x, where .. ": tabs reach into Close")
        T.truthy(lay.close.x + lay.close.w <= rects.strip.x + rects.strip.w, where)
        T.truthy(lay.close.w >= minTouch, where)
      end
    end
  end
  -- Plenty of room: every tab names itself. Tight: only the open one does.
  local pages = Books.pages(cfg, "ledger")
  local wide = Books.layoutTabs(cfg, pages, "pantry", { x = 0, y = 0, w = 600, h = 26 }, minTouch, measure, 12)
  for _, tab in ipairs(wide.tabs) do
    T.truthy(tab.label, tab.id .. " has room for its name")
  end
  local narrow = Books.layoutTabs(cfg, pages, "routine", { x = 0, y = 0, w = 300, h = 26 }, minTouch, measure, 12)
  for _, tab in ipairs(narrow.tabs) do
    T.eq(tab.label, tab.id == "routine", tab.id)
  end
end)

-- The book scene ----------------------------------------------------------------------------------

-- No window means no font to measure with: a fixed-pitch stand-in (6 px a letter, 8 px a line) lays pages out.
local Text = require("src.ui.text")
function Text.measure(str)
  return #str * 6, 8
end
function Text.wrappedHeight(str, _, width)
  return 8 * math.max(1, math.ceil(#str * 6 / math.max(1, width)))
end

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(1))
end

local function inside(r, outer)
  return r.x >= outer.x and r.y >= outer.y and r.x + r.w <= outer.x + outer.w and r.y + r.h <= outer.y + outer.h
end

--- A book scene on a stand-in app; `popped.count` counts closes.
local function mount(world, size, spec)
  local popped = { count = 0 }
  local app = {
    ctx = { tuning = tun, session = { world = world } },
    view = { w = size.w, h = size.h, scale = 1 },
    stack = {},
    pop = function(self)
      popped.count = popped.count + 1
      local scene = table.remove(self.stack)
      if scene and scene.exit then
        scene:exit()
      end
    end,
    push = function() end,
  }
  local scene = Book.new(world, spec)
  scene.app = app
  app.stack[1] = scene
  scene:enter()
  scene:resize(app.view)
  return scene, popped
end

local function tabButton(scene, id)
  for _, b in ipairs(scene.buttons.list) do
    if b.id == id then
      return b
    end
  end
end

T.test("book: every page of both books lays out inside the page body at every size", function()
  for _, size in ipairs(SIZES) do
    for _, book in ipairs({ "notebook", "ledger" }) do
      Books.reset()
      local world = newWorld()
      local log = require("src.ui.message_log").new(40, 60, {})
      local scene = mount(world, size, { book = book, log = log })
      for _, id in ipairs(ids(book)) do
        scene:show(id)
        local where = book .. " " .. id .. " " .. size.name
        local page = scene.page
        T.truthy(page.box, where .. ": the page has a box")
        T.truthy(page.box.hosted, where .. ": its panel is hosted")
        T.truthy(inside(page.box, scene.rects.body), where .. ": the panel sits in the page body")
        T.eq(scene.current, id)
        T.eq(Books.last(book), id, where .. ": the book remembers it")
      end
    end
  end
end)

T.test("book: tapping a tab shows its page; the book reopens where it was left", function()
  Books.reset()
  local world = newWorld()
  local size = SIZES[2]
  local scene, popped = mount(world, size, { book = "ledger" })
  T.eq(scene.current, "pantry", "the first visit opens the first page")
  local catalog = tabButton(scene, "catalog")
  scene:action("press", { x = catalog.x + 2, y = catalog.y + 2 })
  scene:action("select", { x = catalog.x + 2, y = catalog.y + 2 })
  T.eq(scene.current, "catalog")
  scene.app:pop()
  T.eq(popped.count, 1)
  local again = mount(world, size, { book = "ledger" })
  T.eq(again.current, "catalog", "the Ledger remembers its page within the session")
  local other = mount(world, size, { book = "notebook" })
  T.eq(other.current, "journal", "the Notebook has its own page")
  local shortcut = mount(world, size, { book = "ledger", page = "truck" })
  T.eq(shortcut.current, "truck", "a shortcut's page wins over the remembered one")
end)

T.test("book: a page closing itself closes the book; Close is a tab", function()
  Books.reset()
  local world = newWorld()
  local scene, popped = mount(world, SIZES[4], { book = "ledger", page = "pantry" })
  local close
  for _, b in ipairs(scene.buttons.list) do
    if b.label == "Close" then
      close = b
    end
  end
  T.truthy(close, "the book has one Close tab")
  scene:action("cancel", {})
  T.eq(popped.count, 1, "cancel in the Pantry page closes the book")
end)

T.test("book: the Catalog page keeps the Hammer's buildings option", function()
  Books.reset()
  local world = newWorld()
  local scene = mount(world, SIZES[4], { book = "ledger", page = "catalog", catalogOpts = { buildings = true } })
  T.eq(scene.current, "catalog")
  T.eq(scene.page.buildings, nil, "the option was used once on opening")
end)

T.test("book: in town the truck page is the only way home", function()
  Books.reset()
  local world = newWorld()
  world.state.market.inTown = true
  local scene = mount(world, SIZES[4], { book = "ledger", page = "pantry" })
  T.eq(scene.current, "truck", "the book opens on Truck & town")
  for _, b in ipairs(scene.buttons.list) do
    T.falsy(b.label == "Close", "no Close while in town")
    T.eq(b.enabled, b.id == "truck", b.id .. " waits")
  end
end)
