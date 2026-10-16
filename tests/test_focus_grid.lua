-- Keyboard focus (src/ui/focus_grid.lua): spatial moves inside a zone, jumps between zones at an edge, no wrap.
local T = require("harness")
local FocusGrid = require("src.ui.focus_grid")

-- A tab strip, a 3-column tile grid of 7 tiles (the last row has one), then two action buttons.
local function screen()
  local items = {}
  for n = 1, 5 do
    items[#items + 1] = { id = "tab" .. n, zone = "tabs", x = 10 + (n - 1) * 40, y = 0, w = 38, h = 24 }
  end
  items[#items + 1] = { id = "close", zone = "tabs", x = 230, y = 0, w = 50, h = 24 }
  for n = 0, 6 do
    items[#items + 1] = {
      id = "tile" .. n,
      zone = "tiles",
      x = 10 + (n % 3) * 60,
      y = 40 + math.floor(n / 3) * 80,
      w = 56,
      h = 76,
    }
  end
  items[#items + 1] = { id = "reset", zone = "actions", x = 130, y = 230, w = 56, h = 26 }
  items[#items + 1] = { id = "wear", zone = "actions", x = 190, y = 230, w = 72, h = 26 }
  local grid = FocusGrid.new({ "tabs", "tiles", "actions", "presets" })
  grid:set(items)
  return grid
end

T.test("focus: it starts on the first control of the first zone, hidden", function()
  local g = screen()
  T.eq(g:current(), "tab1")
  T.falsy(g:shown())
  g:show(true)
  T.truthy(g:shown())
  g:show(false)
  T.falsy(g:shown())
end)

T.test("focus: left and right move to the neighbour and stop at the ends (no wrap)", function()
  local g = screen()
  T.eq(g:move("right"), "tab2")
  T.eq(g:move("left"), "tab1")
  T.eq(g:move("left"), "tab1")
  g:focus("close")
  T.eq(g:move("right"), "close")
  g:focus("tile0")
  T.eq(g:move("left"), "tile0", "no wrap to the row above")
  g:focus("tile2")
  T.eq(g:move("right"), "tile2", "no wrap to the next row")
end)

T.test("focus: up from the top tile row lands on a tab, down from the last row on the actions", function()
  local g = screen()
  g:focus("tile1")
  T.eq(g:move("up", { tabs = "tab3" }), "tab3", "the slot's own tab when asked for")
  T.eq(g:move("down", { tiles = "tile4" }), "tile4", "the worn tile of the slot when asked for")
  g:focus("tile4")
  T.eq(g:move("down"), "tile6", "the straight neighbour first")
  g:focus("tile6")
  local landed = g:move("down")
  T.eq(g:item(landed).zone, "actions")
  T.eq(g:move("up"), "tile6", "and back up to the last row, nearest across")
  g:focus("tab1")
  T.eq(g:move("up"), "tab1", "up from the tabs stays")
  g:focus("wear")
  T.eq(g:move("down"), "wear", "down from the last zone stays (the empty presets zone is skipped)")
end)

T.test("focus: down from a tile with nothing below goes to the nearest one in the next row", function()
  local g = screen()
  g:focus("tile5") -- column 2 of the middle row; row 3 holds only column 0
  T.eq(g:move("down"), "tile6")
  g:focus("tile3")
  T.eq(g:move("up"), "tile0")
end)

T.test("focus: the zone order is tabs, tiles, actions, presets", function()
  local g = screen()
  g:set({
    { id = "t", zone = "tabs", x = 0, y = 0, w = 10, h = 10 },
    { id = "a", zone = "tiles", x = 0, y = 20, w = 10, h = 10 },
    { id = "b", zone = "actions", x = 0, y = 40, w = 10, h = 10 },
    { id = "p", zone = "presets", x = 0, y = 60, w = 10, h = 10 },
  })
  g:focus("t")
  T.eq(g:move("down"), "a")
  T.eq(g:move("down"), "b")
  T.eq(g:move("down"), "p")
  T.eq(g:move("down"), "p")
  T.eq(g:move("up"), "b")
end)

T.test("focus: set keeps the focus on a control that is still there, else goes to the first", function()
  local g = screen()
  g:focus("tile3")
  g:set({
    { id = "tab1", zone = "tabs", x = 0, y = 0, w = 10, h = 10 },
    { id = "tile3", zone = "tiles", x = 0, y = 20, w = 10, h = 10 },
  })
  T.eq(g:current(), "tile3")
  g:set({ { id = "tab1", zone = "tabs", x = 0, y = 0, w = 10, h = 10 } })
  T.eq(g:current(), "tab1")
  g:focus("nope")
  T.eq(g:current(), "tab1", "an unknown id is ignored")
end)

T.test("focus: a control scrolled out of view is still reachable (the scene reveals it)", function()
  local g = FocusGrid.new({ "tabs", "tiles" })
  local items = { { id = "tab", zone = "tabs", x = 0, y = 0, w = 10, h = 10 } }
  for n = 0, 29 do
    items[#items + 1] =
      { id = "t" .. n, zone = "tiles", x = (n % 3) * 20, y = 20 + math.floor(n / 3) * 20, w = 16, h = 16 }
  end
  g:set(items)
  g:focus("t0")
  for _ = 1, 9 do
    g:move("down")
  end
  T.eq(g:current(), "t27", "nine rows down, far below any window")
end)
