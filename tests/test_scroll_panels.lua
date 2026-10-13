-- The shared scroll kit and the panels that use it (D87, #8, #184): ScrollList logic, catalog, guide,
-- the town menu and the toolbar palette with many seeds, at the four checked view sizes.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local ScrollList = require("src.ui.scroll_list")
local Toolbar = require("src.ui.toolbar")
local Catalog = require("src.scenes.catalog")
local Guide = require("src.scenes.guide")
local Truck = require("src.scenes.truck")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local SIZES = {
  { name = "widget", w = 640, h = 360 },
  { name = "phone", w = 390, h = 844 },
  { name = "landscape", w = 844, h = 390 },
  { name = "desktop", w = 1280, h = 720 },
  { name = "short", w = 640, h = 200 }, -- shorter than any content, to force every list to scroll
}

local function newWorld()
  return World.new({ registry = reg, tuning = tun }, World.newState(1))
end

-- ScrollList ---------------------------------------------------------------------------------------

T.test("scroll list: fit reserves a hint line only when content overflows", function()
  local list = ScrollList.new()
  local v = list:fit({ x = 10, y = 20, w = 100, h = 100 }, 80, 12, 10)
  T.eq(v.h, 100)
  T.falsy(list.overflow)
  v = list:fit({ x = 10, y = 20, w = 100, h = 100 }, 300, 12, 10)
  T.eq(v.h, 88, "12 px kept for the hint")
  T.truthy(list.overflow)
  v = list:fit({ x = 10, y = 20, w = 100, h = 100 }, 101, 12, 10)
  T.eq(v.h, 88, "one pixel too tall already overflows")
  T.truthy(list.overflow)
end)

T.test("scroll list: drag, wheel and clamping", function()
  local list = ScrollList.new()
  list:fit({ x = 0, y = 0, w = 100, h = 100 }, 300, 12, 10)
  T.falsy(list:action("pan", { dy = 10 }, 22), "already at the top")
  T.truthy(list:action("pan", { dy = -30 }, 22))
  T.eq(list.offset, 30, "dragging up shows later rows")
  T.truthy(list:action("zoom", { steps = -1 }, 22))
  T.eq(list.offset, 52, "wheel down shows later rows")
  list:action("pan", { dy = -10000 }, 22)
  T.eq(list.offset, 300 - 88, "stops at the end")
  T.eq(list:origin(), -(300 - 88))
  list:action("zoom", { steps = 100 }, 22)
  T.eq(list.offset, 0)
  local small = ScrollList.new()
  small:fit({ x = 0, y = 0, w = 100, h = 100 }, 50, 12, 10)
  T.falsy(small:action("pan", { dy = -30 }, 22), "nothing to scroll")
end)

T.test("scroll list: reveal, contains and visible", function()
  local list = ScrollList.new()
  list:fit({ x = 10, y = 20, w = 100, h = 100 }, 400, 12, 10)
  list:reveal(300, 24)
  T.eq(list.offset, 300 + 24 - 88, "scrolled just enough to show the row")
  list:reveal(0, 24)
  T.eq(list.offset, 0)
  T.truthy(list:contains(10, 20))
  T.falsy(list:contains(10, 108), "the hint line is outside the window")
  T.falsy(list:contains(9, 30))
  T.truthy(list:visible(list:origin() + 80, 24), "a row straddling the bottom edge is in view")
  T.falsy(list:visible(list:origin() + 90, 24))
end)

-- Panels ------------------------------------------------------------------------------------------

local function mount(scene, w, h)
  scene.app = { ctx = { tuning = tun }, view = { w = w, h = h, scale = 1 }, pop = function() end, push = function() end }
  scene:enter()
  scene:resize({ w = w, h = h })
  return scene
end

local function inside(r, outer)
  return r.x >= outer.x and r.y >= outer.y and r.x + r.w <= outer.x + outer.w and r.y + r.h <= outer.y + outer.h
end

--- Scroll `list` to the end and check the window sits inside the panel box.
local function checkList(list, box, where)
  T.truthy(inside(list.view, box), where .. ": the list window stays inside the panel")
  list.offset = list.contentH
  list:fit(list.view, list.contentH, 0, 1)
end

T.test("catalog: the list clips inside the panel and scrolls at every size", function()
  for _, size in ipairs(SIZES) do
    local world = newWorld()
    local panel = mount(Catalog.new(world, function() end), size.w, size.h)
    local where = "catalog " .. size.name
    T.truthy(inside(panel.box, { x = 0, y = 0, w = size.w, h = size.h }), where .. ": the panel fits the view")
    T.truthy(inside(panel.list.view, panel.box), where .. ": window inside the panel")
    for _, b in ipairs(panel.rowButtons.list) do
      T.truthy(b.x + b.w <= panel.box.x + panel.box.w, where .. ": a row button leaves the panel")
    end
    if panel.list.overflow then
      local before = panel.list.offset
      panel:action("zoom", { steps = -1 })
      T.truthy(panel.list.offset > before, where .. ": the wheel scrolls")
    end
  end
end)

T.test("guide: every species is reachable by scrolling at every size", function()
  for _, size in ipairs(SIZES) do
    local world = newWorld()
    local panel = mount(Guide.new(world), size.w, size.h)
    local where = "guide " .. size.name
    local count = #reg:all("fish")
    T.truthy(inside(panel.list.view, panel.box), where)
    T.eq(panel.list.contentH, count * 26, where .. ": one row per species")
    if panel.list.overflow then
      T.truthy(panel:action("pan", { dy = -20 }), where)
      T.truthy(panel.list.offset > 0, where .. ": dragging scrolls")
      checkList(panel.list, panel.box, where)
      T.eq(panel.list.offset, panel.list.contentH - panel.list.view.h, where .. ": the last row can be reached")
    else
      T.eq(panel.list.offset, 0)
    end
  end
end)

T.test("town menu: shop and load lists clip and scroll at every size", function()
  for _, size in ipairs(SIZES) do
    local world = newWorld()
    world.state.market.inTown = true
    local panel = mount(Truck.new(world, function() end), size.w, size.h)
    local where = "town " .. size.name
    T.truthy(inside(panel.shop.view, panel.box), where .. ": shop window inside the panel")
    T.truthy(inside(panel.loadList.view, panel.box), where .. ": load window inside the panel")
    -- The shop's buttons stay in the right half, clear of the load list.
    for _, b in ipairs(panel.shopButtons.list) do
      T.truthy(b.x >= panel.box.x + panel.box.w / 2 - 6, where .. ": a shop button strays into the load column")
    end
    if panel.shop.overflow then
      panel.leftFocus = false
      panel:action("zoom", { steps = -1, x = panel.box.x + panel.box.w - 10, y = panel.box.y + 60 })
      T.truthy(panel.shop.offset > 0, where .. ": the wheel scrolls the shop")
    end
  end
end)

-- Toolbar palette ------------------------------------------------------------------------------------

local function seedButtons(n)
  local bw = tun.ui.buttonWidths
  local tools = {}
  for i = 1, n do
    tools[#tools + 1] = { id = "seed:crop" .. i, w = bw.seed }
  end
  tools[#tools + 1] = { id = "rod", w = 62 }
  tools[#tools + 1] = { id = "plan", w = 74 }
  local hand = { id = "hand", w = bw.hand }
  local routine, pantry = { id = "routineList", w = 92 }, { id = "pantry", w = bw.pantry }
  local journal = { id = "journal", w = bw.journal }
  local left = { hand }
  for _, t in ipairs(tools) do
    left[#left + 1] = t
  end
  left[#left + 1] = routine
  return {
    left = left,
    right = { pantry, journal },
    fixedLeft = { hand },
    toolsButton = { id = "tools", w = bw.tools },
    fixedRight = { pantry, journal },
    moreButton = { id = "more", w = bw.more },
    tools = tools,
    more = { routine },
  }
end

local function paletteCfg(view, scroll)
  local compact = view.w < tun.ui.compactWidth
  local h = compact and tun.ui.compactButtonHeight or tun.ui.buttonHeight
  local topRow = compact and tun.ui.compactTopBarHeight or tun.ui.topBarHeight
  local topH = topRow + (compact and tun.ui.statRowHeight or 0)
  return {
    pad = tun.ui.barPadding,
    gap = tun.ui.buttonGap,
    h = h,
    margin = tun.ui.barMargin,
    paletteGap = tun.ui.paletteGap,
    paletteMaxRows = tun.ui.paletteMaxRows,
    paletteTop = topH + tun.ui.buttonGap + 3 * (h + tun.ui.buttonGap),
    scrollBarWidth = tun.ui.scrollBarWidth,
    scroll = scroll,
  }
end

T.test("palette: 8+ seeds stay inside a capped palette and every seed can be reached", function()
  for _, size in ipairs(SIZES) do
    for _, seeds in ipairs({ 8, 14, 40, 120 }) do
      local view = { w = size.w, h = size.h }
      local where = string.format("%s with %d seeds", size.name, seeds)
      local cfg = paletteCfg(view, {})
      local out = Toolbar.arrange(seedButtons(seeds), view, cfg)
      if out.palette then
        local pop = out.popups.tools
        local cap = 2 * cfg.gap + cfg.paletteMaxRows * cfg.h + (cfg.paletteMaxRows - 1) * cfg.gap
        T.truthy(pop.h <= cap + 0.001, where .. ": the palette is capped at " .. cfg.paletteMaxRows .. " rows")
        T.truthy(pop.y >= cfg.paletteTop, where .. ": the palette keeps clear of the control column")
        T.truthy(pop.y + pop.h <= view.h - out.bottomH, where .. ": the palette stays above the bar")
        T.truthy(pop.x >= 0 and pop.x + pop.w <= view.w, where .. ": the palette is on screen")
        -- Scroll through the palette: every item is fully inside the window at some offset.
        local reached, offset, guard = {}, 0, 0
        while guard < 200 do
          cfg.scroll = { tools = offset }
          local o = Toolbar.arrange(seedButtons(seeds), view, cfg).popups.tools
          for _, b in ipairs(o.items) do
            if b.x >= o.view.x and b.x + b.w <= o.view.x + o.view.w and b.y >= o.view.y and b.y + b.h <= o.view.y + o.view.h then
              reached[b.id] = true
            end
          end
          if offset >= o.contentH - o.view.h then
            break
          end
          offset = offset + o.view.h / 2
          guard = guard + 1
        end
        for _, b in ipairs(pop.items) do
          T.truthy(reached[b.id], where .. ": " .. b.id .. " can be scrolled into view")
        end
        if seeds >= 120 then
          T.truthy(pop.scrolls, where .. ": a long palette scrolls")
        end
      end
    end
  end
end)

T.test("palette: scroll offset is clamped and the palette without overflow does not scroll", function()
  local view = SIZES[2]
  local cfg = paletteCfg(view, { tools = 99999 })
  local out = Toolbar.arrange(seedButtons(120), view, cfg)
  local pop = out.popups.tools
  T.truthy(pop.scrolls)
  T.eq(pop.offset, pop.contentH - pop.view.h, "clamped to the end")
  cfg = paletteCfg(view, { tools = 50 })
  local few = Toolbar.arrange(seedButtons(2), view, cfg).popups.tools
  T.falsy(few.scrolls)
  T.eq(few.offset, 0)
end)
