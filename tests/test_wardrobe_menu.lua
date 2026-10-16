-- The Wardrobe's pure pieces (docs/PLAN_WARDROBE_MENU.md §7.1): the layout at the three views, the tab strip, the
-- draft, the meters' maths and their agreement with the sim, the state line, tag and pills, the hints and the
-- tile names. Nothing here needs a window.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Books = require("src.ui.books")
local PixelFont = require("src.ui.pixel_font")
local ScrollList = require("src.ui.scroll_list")
local Wardrobe = require("src.sim.systems.wardrobe")
local WardrobeLayout = require("src.ui.wardrobe_layout")
local WardrobeState = require("src.ui.wardrobe_state")
local WardrobeText = require("src.ui.wardrobe_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg, bookCfg = tun.ui.wardrobe, tun.ui.book
local MIN = tun.input.minTouchTarget

local VIEWS = {
  desktop = { w = 640, h = 360 },
  phone = { w = 390, h = 844 },
  landscape = { w = 844, h = 390 },
}

local function inside(r, outer, msg)
  T.truthy(
    r.x >= outer.x and r.y >= outer.y and r.x + r.w <= outer.x + outer.w and r.y + r.h <= outer.y + outer.h,
    string.format(
      "%s: (%g,%g %gx%g) is outside (%g,%g %gx%g)",
      msg,
      r.x,
      r.y,
      r.w,
      r.h,
      outer.x,
      outer.y,
      outer.w,
      outer.h
    )
  )
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function noOverlap(list, what)
  for i = 1, #list do
    for j = i + 1, #list do
      T.falsy(overlap(list[i][2], list[j][2]), what .. ": " .. list[i][1] .. " overlaps " .. list[j][1])
    end
  end
end

-- Layout ----------------------------------------------------------------------------------------------------

T.test("wardrobe layout: everything sits inside the paper, buttons never overlap, touch targets hold", function()
  for name, view in pairs(VIEWS) do
    for _, opts in ipairs({ {}, { presets = true, save = true } }) do
      local L = WardrobeLayout.rects(cfg, bookCfg, view, MIN, 7, opts)
      local body = L.body
      inside(L.paper, { x = 0, y = 0, w = view.w, h = view.h }, name .. " paper")
      for _, key in ipairs({ "title", "state", "preview", "ground", "presets", "heading", "grid", "detail", "tag" }) do
        inside(L[key], body, name .. " " .. key)
      end
      for _, key in ipairs({ "work", "heat" }) do
        local m = L.meters[key]
        for _, part in ipairs({ "label", "bar", "num" }) do
          inside(m[part], body, name .. " meter " .. key .. " " .. part)
        end
      end
      local buttons = { { "reset", L.reset }, { "wear", L.wear } }
      if opts.save then
        buttons[#buttons + 1] = { "save", L.save }
      end
      for n, chip in ipairs(L.chips) do
        buttons[#buttons + 1] = { "chip" .. n, chip }
      end
      for _, b in ipairs(buttons) do
        inside(b[2], body, name .. " " .. b[1])
        T.truthy(b[2].w >= MIN and b[2].h >= MIN, name .. " " .. b[1] .. " is at least a touch target")
      end
      noOverlap(buttons, name .. " buttons")
      -- The blocks of a column do not run into each other.
      local blocks = {
        { "title", L.title },
        { "state", L.state },
        { "preview", L.preview },
        { "meter work", L.meters.work },
        { "meter heat", L.meters.heat },
        { "heading", L.heading },
        { "grid", L.grid },
        { "detail", L.detail },
        { "tag", L.tag },
      }
      if opts.presets then
        blocks[#blocks + 1] = { "presets", L.presets }
      end
      for _, b in ipairs(buttons) do
        if not b[1]:match("^chip") then
          blocks[#blocks + 1] = b
        end
      end
      noOverlap(blocks, name .. " blocks")
      T.truthy(L.grid.h > 0, name .. " keeps a grid")
    end
  end
end)

T.test("wardrobe layout: the figure is a whole scale between the limits, the ground whole art pixels", function()
  for name, view in pairs(VIEWS) do
    local L = WardrobeLayout.rects(cfg, bookCfg, view, MIN, 7)
    local s = L.preview.scale
    T.eq(s, math.floor(s), name .. " scale is whole")
    local top = L.wide and cfg.previewMaxScale or cfg.previewMaxScaleTall
    T.truthy(s >= cfg.previewMinScale and s <= top, name .. " scale " .. s)
    T.eq(L.ground.w % s, 0, name .. " ground is whole art pixels")
    inside(L.ground, L.preview, name .. " ground in its inset")
  end
  T.eq(WardrobeLayout.rects(cfg, bookCfg, VIEWS.desktop, MIN, 7).preview.scale, cfg.previewMaxScale)
  T.eq(WardrobeLayout.rects(cfg, bookCfg, VIEWS.phone, MIN, 7).preview.scale, cfg.previewMaxScaleTall)
  T.eq(WardrobeLayout.previewScale(cfg, 10, 10, false), cfg.previewMinScale, "never below the minimum")
end)

T.test("wardrobe layout: two columns from wideMin up, stacked below it", function()
  local wide = WardrobeLayout.rects(cfg, bookCfg, { w = cfg.wideMin, h = 400 }, MIN, 7)
  local stacked = WardrobeLayout.rects(cfg, bookCfg, { w = cfg.wideMin - 1, h = 700 }, MIN, 7)
  T.truthy(wide.wide)
  T.falsy(stacked.wide)
  T.truthy(wide.grid.x > wide.preview.x + wide.preview.w, "wide: the garments are right of the figure")
  T.truthy(stacked.grid.y > stacked.preview.y + stacked.preview.h - 1, "stacked: the garments are under the figure")
  T.truthy(stacked.wear.y > stacked.grid.y + stacked.grid.h, "stacked: the action bar is at the bottom")
end)

T.test("wardrobe layout: a slot's garments fit without scrolling, a long list scrolls", function()
  local most = 0
  for _, slot in ipairs(tun.wardrobe.slots) do
    local n = 0
    for _, def in ipairs(reg:all("garments")) do
      if def.slot == slot then
        n = n + 1
      end
    end
    most = math.max(most, n)
  end
  for name, view in pairs(VIEWS) do
    local L = WardrobeLayout.rects(cfg, bookCfg, view, MIN, most)
    local tiles, contentH, columns = WardrobeLayout.tiles(cfg, L.grid, most)
    T.truthy(contentH <= L.grid.h, name .. ": " .. most .. " tiles fit without scrolling")
    T.eq(#tiles, most)
    for n, r in ipairs(tiles) do
      T.truthy(r.x >= L.grid.x and r.x + r.w <= L.grid.x + L.grid.w, name .. " tile " .. n .. " inside across")
      T.truthy(r.w >= MIN and r.h >= MIN)
    end
    T.truthy(columns >= 4, name .. " shows at least four columns")
    local long = WardrobeLayout.rects(cfg, bookCfg, view, MIN, 40)
    local _, longH = WardrobeLayout.tiles(cfg, long.grid, 40)
    T.truthy(longH > long.grid.h, name .. ": 40 tiles scroll")
  end
end)

T.test("wardrobe layout: focus on a tile in a long list reveals it", function()
  local L = WardrobeLayout.rects(cfg, bookCfg, VIEWS.desktop, MIN, 40)
  local tiles, contentH = WardrobeLayout.tiles(cfg, L.grid, 40)
  local list = ScrollList.new()
  list:fit(L.grid, contentH, tun.ui.scrollHintHeight)
  T.truthy(list.overflow)
  local last = tiles[40]
  T.falsy(list:visible(list:origin() + last.y, last.h), "the last tile starts out of view")
  list:reveal(last.y, last.h)
  T.truthy(list:visible(list:origin() + last.y, last.h), "and is in view after reveal")
  T.truthy(list.offset > 0)
end)

T.test("wardrobe layout: the tabs are the Ledger's strip and fit a phone with labels", function()
  for name, view in pairs(VIEWS) do
    local L = WardrobeLayout.rects(cfg, bookCfg, view, MIN, 7)
    local pages = {}
    for n, slot in ipairs(tun.wardrobe.slots) do
      pages[n] = { id = slot, label = cfg.slots[slot], icon = cfg.slotIcons[slot] }
    end
    local measure = function(label)
      local w = 0
      for ch in label:gmatch(".") do
        w = w + #PixelFont.glyph(ch)[1] + 1
      end
      return w - 1
    end
    local lay = Books.layoutTabs(bookCfg, pages, "head", L.strip, MIN, measure, bookCfg.iconSize)
    T.eq(#lay.tabs, 5)
    for _, tab in ipairs(lay.tabs) do
      T.truthy(tab.label, name .. " every tab keeps its label")
      T.truthy(tab.x + tab.w <= lay.close.x, name .. " tabs end before Close")
      T.truthy(tab.w >= MIN and tab.h >= MIN)
    end
    T.eq(lay.tabs[1].h, L.strip.h)
  end
end)

-- The draft ---------------------------------------------------------------------------------------------------

local function starterOutfit()
  return { head = "bare_head", torso = "flannel_shirt", legs = "work_pants", feet = "work_boots", extra = "no_extra" }
end

T.test("wardrobe draft: preview sets one slot, reset restores, changed tells", function()
  local owns = { bare_head = true, straw_hat = true, flannel_shirt = true }
  local s = WardrobeState.new(starterOutfit(), function(id)
    return owns[id] == true
  end)
  T.falsy(s:changed())
  T.truthy(s:preview("head", "straw_hat"))
  T.eq(s:draft().head, "straw_hat")
  T.eq(s:draft().torso, "flannel_shirt")
  T.truthy(s:changed())
  T.eq(s:committed().head, "bare_head", "the chosen outfit does not move")
  s:reset()
  T.falsy(s:changed())
  T.eq(s:draft().head, "bare_head")
end)

T.test("wardrobe draft: a garment not owned never enters the draft", function()
  local s = WardrobeState.new(starterOutfit(), function(id)
    return id == "bare_head"
  end)
  T.falsy(s:preview("torso", "down_parka"))
  T.eq(s:draft().torso, "flannel_shirt")
  T.falsy(s:changed())
  s:loadPreset({ torso = "down_parka", head = "bare_head" }, "cold")
  T.eq(s:draft().torso, "flannel_shirt", "a preset skips what is not owned too")
  T.eq(s.presetName, "cold")
end)

T.test("wardrobe draft: the session remembers a draft and the slot, and forgets on reset", function()
  WardrobeState.reset()
  T.falsy(WardrobeState.last())
  local s = WardrobeState.new(starterOutfit())
  s:preview("head", "straw_hat")
  s:preview("legs", "shorts")
  WardrobeState.remember(s, "legs")
  T.eq(WardrobeState.last().slot, "legs")
  local again = WardrobeState.new(starterOutfit())
  T.truthy(again:restore())
  T.eq(again:draft().head, "straw_hat")
  T.eq(again:draft().legs, "shorts")
  T.truthy(again:changed())
  -- A draft that was worn leaves nothing to restore.
  local worn = WardrobeState.new(starterOutfit())
  worn:preview("head", "straw_hat")
  worn:setCommitted(worn:draft())
  WardrobeState.remember(worn, "head")
  T.falsy(WardrobeState.new(worn:committed()):restore())
  -- A garment that is no longer owned is dropped when restoring.
  WardrobeState.remember(s, "head")
  local poorer = WardrobeState.new(starterOutfit(), function(id)
    return id ~= "shorts"
  end)
  T.truthy(poorer:restore())
  T.eq(poorer:draft().legs, "work_pants")
  T.eq(poorer:draft().head, "straw_hat")
  WardrobeState.reset()
  T.falsy(WardrobeState.last())
end)

-- The meters ---------------------------------------------------------------------------------------------------

T.test("wardrobe meters: percent reads whole numbers, one decimal, and zero", function()
  T.eq(WardrobeText.percent(0.04), "+4%")
  T.eq(WardrobeText.percent(-0.08), "-8%")
  T.eq(WardrobeText.percent(0.005), "+0.5%")
  T.eq(WardrobeText.percent(-0.0075), "-0.8%")
  T.eq(WardrobeText.percent(0), "0%")
  T.eq(WardrobeText.percent(1e-9), "0%")
  T.eq(WardrobeText.percent(0.06), "+6%")
end)

T.test("wardrobe meters: fill is empty at zero, the full half at the scale, never under a pixel, symmetric", function()
  local n, side = WardrobeText.fill(0, 0.04, 42)
  T.eq(n, 0)
  T.eq(side, 0)
  n, side = WardrobeText.fill(0.04, 0.04, 42)
  T.eq(n, 42)
  T.eq(side, 1)
  n, side = WardrobeText.fill(-0.08, 0.08, 42)
  T.eq(n, 42)
  T.eq(side, -1)
  T.eq((WardrobeText.fill(0.06, 0.08, 42)), 32, "three quarters of the half")
  T.eq((WardrobeText.fill(0.0001, 0.08, 42)), 1, "any value shows a pixel")
  T.eq((WardrobeText.fill(5, 0.04, 42)), 42, "never beyond the half")
  for _, v in ipairs({ 0.005, 0.0225, 0.03, 0.06 }) do
    T.eq((WardrobeText.fill(v, 0.08, 42)), (WardrobeText.fill(-v, 0.08, 42)), "symmetric")
    local _, a = WardrobeText.fill(v, 0.08, 42)
    local _, b = WardrobeText.fill(-v, 0.08, 42)
    T.eq(a, -b)
  end
end)

T.test("wardrobe meters: less work and more heat needed are costs", function()
  T.truthy(WardrobeText.isCost("heat", 0.06))
  T.falsy(WardrobeText.isCost("heat", -0.08))
  T.falsy(WardrobeText.isCost("heat", 0))
  T.truthy(WardrobeText.isCost("work", -0.01))
  T.falsy(WardrobeText.isCost("work", 0.04))
end)

local function newWorld()
  return World.new({ registry = reg, tuning = tun, meta = {} }, World.newState(1))
end

local function classOutfit(class)
  local outfit = {}
  for _, def in ipairs(reg:all("garments")) do
    if def.class == class and not outfit[def.slot] then
      outfit[def.slot] = def.id
    end
  end
  return outfit
end

T.test("wardrobe meters agree with what the sim applies for light, mid, heavy and a mixed outfit", function()
  local mixed = starterOutfit()
  mixed.head, mixed.legs = classOutfit("light").head, classOutfit("heavy").legs
  mixed.torso = classOutfit("heavy").torso
  for name, outfit in pairs({
    light = classOutfit("light"),
    mid = classOutfit("mid"),
    heavy = classOutfit("heavy"),
    mixed = mixed,
  }) do
    local world = newWorld()
    for _, def in ipairs(reg:all("garments")) do
      Wardrobe.grant(world, def.id)
    end
    world.state.calendar.elapsed = 0 -- day 1, morning: a Wear applies now
    T.truthy(Wardrobe.appliesNow(world))
    T.truthy(Wardrobe.wear(world, outfit), name)
    local fx = Wardrobe.effects(world, outfit)
    T.near(1 + fx.work, Wardrobe.workBonus(world), 1e-9, name .. " work")
    T.near(math.max(tun.wardrobe.insulationFloor, 1 + fx.cold), Wardrobe.insulation(world), 1e-9, name .. " heat")
    local scale = Wardrobe.scale(world)
    T.truthy(math.abs(fx.work) <= scale.work + 1e-9 and math.abs(fx.cold) <= scale.cold + 1e-9, name .. " within scale")
  end
end)

-- Words --------------------------------------------------------------------------------------------------------

T.test("wardrobe words: the state line, tag and pills for every combination", function()
  local a, b = starterOutfit(), starterOutfit()
  b.torso = "wool_sweater"
  T.eq(WardrobeText.stateLine(cfg, a, a, a), cfg.stateToday)
  T.eq(WardrobeText.stateLine(cfg, b, a, a), cfg.statePreview, "a draft that is not chosen")
  T.eq(WardrobeText.stateLine(cfg, b, b, a), cfg.stateDawn, "chosen, waiting for dawn")
  T.eq(WardrobeText.stateLine(cfg, a, b, a), cfg.statePreview, "a draft at dawn stays a preview")
  T.eq(WardrobeText.stateLine(cfg, b, b, b), cfg.stateToday)
  T.eq(WardrobeText.tag(cfg, true), cfg.tagNow)
  T.eq(WardrobeText.tag(cfg, false), cfg.tagDawn)
  -- Chosen b waits for dawn while a is worn: Today on the worn tile, Dawn on the chosen one, never both.
  local word, kind = WardrobeText.pill(cfg, "flannel_shirt", b, a, "torso")
  T.eq(word, cfg.pillToday)
  T.eq(kind, "today")
  word, kind = WardrobeText.pill(cfg, "wool_sweater", b, a, "torso")
  T.eq(word, cfg.pillDawn)
  T.eq(kind, "dawn")
  T.eq(WardrobeText.pill(cfg, "denim_jacket", b, a, "torso"), nil)
  word = WardrobeText.pill(cfg, "wool_sweater", b, b, "torso")
  T.eq(word, cfg.pillToday, "once dawn has passed the Dawn pill is gone")
  T.eq(WardrobeText.pill(cfg, "flannel_shirt", b, b, "torso"), nil)
  T.eq(WardrobeText.pill(cfg, "flannel_shirt", a, a, "torso", "recovery"), nil, "no run, no pills")
end)

local function words(s)
  local n = 0
  for _ in s:gmatch("%S+") do
    n = n + 1
  end
  return n
end

T.test("wardrobe words: every garment that is earned has a hint of at most five words", function()
  local world = newWorld()
  for _, def in ipairs(reg:all("garments")) do
    if def.starter then
      T.eq(def.hint, nil, def.id .. " starts owned, so it needs no hint")
    else
      T.truthy(def.hint, def.id .. " needs a hint")
      T.truthy(words(def.hint) <= 5, def.id .. " hint is " .. words(def.hint) .. " words: " .. def.hint)
      T.falsy(def.hint:find("%.$"), def.id .. " hint has no full stop")
      local n = Wardrobe.threshold(world, def.id)
      if def.hint:find("%%d") then
        T.truthy(n, def.id .. " has a %d but no threshold")
      end
      local text = WardrobeText.hint(def, n)
      T.falsy(text:find("%%"), def.id .. " hint is filled in: " .. text)
    end
  end
  T.eq(WardrobeText.hint({ name = "x" }, nil), nil)
end)

T.test("wardrobe words: the detail lines for an owned and a locked garment", function()
  local straw = reg:get("garments", "straw_hat")
  T.eq(WardrobeText.detail(cfg, straw, true), "Straw hat  Light")
  local l1, l2 = WardrobeText.detail(cfg, straw, false, "Harvest 2 kinds of crop", 1, 2)
  T.eq(l1, "Harvest 2 kinds of crop")
  T.eq(l2, "Light  1 of 2")
  local _, heavy = WardrobeText.detail(cfg, reg:get("garments", "wool_toque"), false, "Survive a winter", 0, 1)
  T.eq(heavy, "Heavy", "a yes or no shows no count")
end)

T.test("wardrobe words: every garment's name fits its tile in at most two lines", function()
  local measure = function(s)
    local w = 0
    for ch in s:gmatch(".") do
      w = w + #PixelFont.glyph(ch)[1] + 1
    end
    return w - 1
  end
  local maxW = cfg.tileW - 2 * cfg.namePad
  for _, def in ipairs(reg:all("garments")) do
    local lines = WardrobeText.nameLines(def.name, measure, maxW, cfg.nameLines, cfg.ellipsis)
    T.truthy(#lines >= 1 and #lines <= cfg.nameLines, def.id)
    for _, line in ipairs(lines) do
      T.truthy(measure(line) <= maxW, def.id .. " line too wide: " .. line)
    end
    T.falsy(table.concat(lines, " "):find("%.%.%."), def.id .. " is clipped: " .. table.concat(lines, "|"))
  end
  local clipped = WardrobeText.nameLines("Extraordinarily long garment name here", measure, maxW, 2, "...")
  T.eq(#clipped, 2)
  T.truthy(clipped[2]:find("%.%.%.$"), "the last line ends in the ellipsis")
  T.truthy(measure(clipped[2]) <= maxW)
end)

T.test("wardrobe words: the tuning strings used by the scene exist and the weights have pips", function()
  for _, class in ipairs({ "light", "mid", "heavy" }) do
    T.truthy(cfg.weights[class], class)
    T.truthy(cfg.pips[class] >= 1 and cfg.pips[class] <= 3)
  end
  for _, slot in ipairs(tun.wardrobe.slots) do
    T.truthy(cfg.slots[slot], slot)
    T.truthy(require("assets.manifest").sprites[cfg.slotIcons[slot]], slot .. " has a tab icon")
  end
  T.truthy(cfg.tileW >= MIN and cfg.tileH >= MIN, "tiles are never below the touch target")
  T.eq(cfg.pips.light < cfg.pips.mid and cfg.pips.mid < cfg.pips.heavy, true)
end)
