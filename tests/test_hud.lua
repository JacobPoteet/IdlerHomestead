-- The resting HUD's layout (GDD §9.4, D137, #293): at every view size and allowed UI scale the plates
-- stay inside the view, never overlap, keep touch-sized targets, place every vital, and fold to icons
-- when the bottom row does not fit.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Hud = require("src.ui.hud")

local tun = tuningLoader.load()
local H = tun.ui.hud
local CHAR = 6 -- UI pixels per character of the pixel font, near enough for layout

local function words(s)
  return #s * CHAR
end

--- A spec like the scene builds, with `vitals` vitals and `stamps` stamps.
local function spec(vitals, stamps, caption)
  local s = {
    clock = { w = words("Day 12 · Autumn") + 2 * H.textPad, h = H.clockH },
    speed = { w = 3 * H.speedSegment, h = H.clockH, segments = 3 },
    menu = { w = math.max(tun.input.minTouchTarget, H.clockH), h = H.clockH },
    vitals = {},
    vitalH = H.vitalH,
    stamps = {},
    badge = { w = 16 + 3 * H.textPad + words("Routine in 30s"), compactW = H.badgeH, h = H.badgeH },
    tool = { w = 26 + 3 * H.textPad + words("Radish 10"), compactW = 26 + 2 * H.iconPad, h = H.badgeH },
    books = {
      { id = "notebook", w = 12 + 3 * H.textPad + words("Notebook"), compactW = H.badgeH },
      { id = "ledger", w = 12 + 3 * H.textPad + words("Ledger"), compactW = H.badgeH },
    },
  }
  for i = 1, vitals do
    s.vitals[i] = { id = "v" .. i, w = 12 + 3 + words("4 · 2.1n") }
  end
  for i = 1, stamps do
    s.stamps[i] = {
      id = "s" .. i,
      w = H.stampSize + words("Winter: short on wood and food"),
      iconW = H.stampSize,
      h = H.stampSize,
    }
  end
  if caption then
    local w = words("Radish in hand: tap open ground to till and plant") + 2 * H.textPad
    s.caption = { w = w, h = tun.ui.pillHeight }
  end
  return s
end

local function inside(r, view)
  return r.x >= 0 and r.y >= 0 and r.x + r.w <= view.w and r.y + r.h <= view.h
end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local CFG = { pad = H.pad, gap = H.gap, vitalGap = H.vitalGap, vitalPad = H.vitalPad }

local function plates(out)
  local list = {
    { "clock", out.clock },
    { "speed", out.speed },
    { "menu", out.menu },
    { "badge", out.badge },
    { "tool", out.tool },
  }
  for i, r in ipairs(out.vitals) do
    list[#list + 1] = { "vitals" .. i, r }
  end
  for i, r in ipairs(out.books) do
    list[#list + 1] = { "book" .. i, r }
  end
  for _, r in ipairs(out.stamps) do
    list[#list + 1] = { "stamp " .. r.id, r }
  end
  if out.caption then
    list[#list + 1] = { "caption", out.caption }
  end
  return list
end

local function check(view, where, out, s)
  local list = plates(out)
  for i, a in ipairs(list) do
    T.truthy(inside(a[2], view), where .. ": " .. a[1] .. " is off screen")
    for j = i + 1, #list do
      T.falsy(overlaps(a[2], list[j][2]), where .. ": " .. a[1] .. " overlaps " .. list[j][1])
    end
  end
  local min = tun.input.minTouchTarget
  for _, r in ipairs({ out.clock, out.menu, out.badge, out.tool, out.books[1], out.books[2] }) do
    T.truthy(r.w >= min and r.h >= min, where .. ": a plate is under the touch size")
  end
  for _, seg in ipairs(out.segments) do
    T.truthy(seg.w >= min and seg.h >= min, where .. ": a speed button is under the touch size")
  end
  local placed = 0
  for _, row in ipairs(out.vitals) do
    placed = placed + #row.items
  end
  T.eq(placed, #s.vitals, where .. ": every vital is placed")
  T.truthy(out.topH <= out.bottomTop, where .. ": the top and bottom plates leave the world between them")
end

local SIZES = {
  { name = "desktop", w = 640, h = 360 },
  { name = "phone", w = 390, h = 844 },
  { name = "landscape", w = 844, h = 390 },
  { name = "big", w = 1280, h = 720 },
  { name = "narrow", w = 340, h = 600 },
}

T.test("hud: at every size nothing overlaps, sits off screen or misses a vital", function()
  for _, view in ipairs(SIZES) do
    for _, vitals in ipairs({ 6, 11 }) do
      for _, stamps in ipairs({ 0, 2, 4 }) do
        for _, caption in ipairs({ false, true }) do
          local s = spec(vitals, stamps, caption)
          local where = string.format("%s v=%d s=%d caption=%s", view.name, vitals, stamps, tostring(caption))
          check(view, where, Hud.arrange(s, view, CFG), s)
        end
      end
    end
  end
end)

T.test("hud: the vitals sit beside the clock when they fit and wrap to rows on a phone", function()
  local wide = Hud.arrange(spec(6, 0), SIZES[4], CFG)
  T.eq(#wide.vitals, 1)
  T.eq(wide.vitals[1].y < wide.clock.y + wide.clock.h, true, "one row, level with the clock")
  local phone = Hud.arrange(spec(11, 0), SIZES[2], CFG)
  T.truthy(#phone.vitals >= 2, "a phone wraps the vitals to rows")
  T.truthy(phone.vitals[1].y >= phone.clock.y + phone.clock.h, "the rows sit under the clock")
end)

T.test("hud: the bottom row folds to icons when it does not fit, the tool badge clear of both sides", function()
  local desk = Hud.arrange(spec(6, 0), SIZES[1], CFG)
  T.falsy(desk.compact, "640 wide keeps words on the bottom plates")
  local narrow = Hud.arrange(spec(6, 0), SIZES[5], CFG)
  T.truthy(narrow.compact, "340 wide shows icons only")
  for _, out in ipairs({ desk, narrow }) do
    T.truthy(out.tool.x >= out.badge.x + out.badge.w, "the tool badge is right of the homesteader badge")
    T.truthy(out.tool.x + out.tool.w <= out.books[1].x, "the tool badge is left of the books")
  end
end)

T.test("hud: stamps show their words on wide views and stay above the bottom plates", function()
  local out = Hud.arrange(spec(6, 3), SIZES[4], CFG)
  T.eq(#out.stamps, 3)
  T.falsy(out.stamps[1].compact)
  local short = Hud.arrange(spec(6, 12), { w = 640, h = 200 }, CFG)
  for _, r in ipairs(short.stamps) do
    T.truthy(r.y + r.h <= short.bottomTop, "a stamp never reaches the bottom plates")
  end
  T.truthy(#short.stamps < 12, "stamps that do not fit wait")
end)

T.test("hud: fits at every allowed UI scale of every window size", function()
  local UiScale = require("src.core.ui_scale")
  local windows =
    { { 1280, 720 }, { 1920, 1080 }, { 3840, 2160 }, { 390, 844 }, { 844, 390 }, { 640, 360 }, { 340, 600 } }
  for _, win in ipairs(windows) do
    for _, sc in ipairs(UiScale.steps(win[1], win[2], tun.display, tun.settings)) do
      local view = { w = win[1] / sc, h = win[2] / sc }
      local s = spec(8, 2, true)
      check(view, win[1] .. "x" .. win[2] .. "@" .. sc, Hud.arrange(s, view, CFG), s)
    end
  end
end)
