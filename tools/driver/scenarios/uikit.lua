-- The interface kit (GDD §9.4, D142, #291): the pixel font at every size, plates (HUD, panel, buttons in
-- each state) over the live world, and every interface icon at 1x and 2x. Shot by day, at night and on a
-- snowy winter day, so the plates' share of the world's light and the frost and snow on them show.
local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")
local Plate = require("src.ui.plate")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local Icons = require("src.ui.icons")
local Buttons = require("src.ui.buttons")
local theme = require("src.ui.theme")

local ICONS = {
  "icon_tool_hand",
  "icon_tool_hoe",
  "icon_tool_pail",
  "icon_tool_pail_big",
  "icon_tool_hatchet",
  "icon_tool_axe",
  "icon_tool_rod",
  "icon_tool_rod_sturdy",
  "icon_tool_hammer",
  "icon_verb_move",
  "icon_verb_pickup",
  "icon_verb_demolish",
  "icon_verb_untill",
  "icon_signal_alert",
  "icon_signal_idea",
  "icon_book_notebook",
  "icon_book_ledger",
  "icon_menu",
  "icon_tab_journal",
  "icon_tab_fish",
  "icon_tab_diary",
  "icon_tab_pantry",
  "icon_tab_routine",
  "icon_tab_catalog",
  "icon_tab_truck",
  "icon_packet",
  "icon_packet_radish",
  "icon_packet_potato",
}

-- A see-through scene over the homestead that draws the kit sheet.
local function kitScene(app)
  local buttons = Buttons.new(0)
  local scene = { opaque = false }
  function scene.draw()
    local view = app.view
    local narrow = view.w < 420
    local x, y = 8, 8
    -- HUD plates of a few sizes.
    Plate.draw(x, y, 120, 22)
    Text.draw("Day 12 · Spring", x + 6, y + 7)
    Plate.draw(x + 126, y, 22, 22)
    Icons.draw("icon_menu", x + 131, y + 5)
    y = y + 30
    -- A panel with every text size.
    local pw = narrow and view.w - 16 or 300
    Draw.panel(x, y, pw, 92)
    Text.draw("Heading", x + 8, y + 6, { size = "heading" })
    Text.draw("Body: the quick brown fox · 0123456789", x + 8, y + 30, { size = "body", width = pw - 16 })
    Text.draw("Small: $12 · 2.1n · Hoe", x + 8, y + 46, { size = "small", color = theme.colors.textDim })
    Text.draw("Amber needs you", x + 8, y + 60, { color = theme.colors.accent })
    Text.draw("Red is danger", x + 8, y + 72, { color = theme.colors.danger })
    y = y + 100
    -- Buttons in each state.
    buttons:clear()
    local bx = x
    for _, b in ipairs({
      { label = "Normal" },
      { label = "Selected", selected = true },
      { label = "Accent", style = "accent" },
      { label = "Danger", style = "danger" },
      { label = "Off", enabled = false },
    }) do
      b.x, b.y, b.w, b.h = bx, y, 56, 24
      buttons:add(b)
      bx = bx + 60
      if bx + 56 > view.w - 8 then
        bx, y = x, y + 28
      end
    end
    buttons:draw()
    y = y + 34
    -- Every interface icon at 1x and 2x on a plate.
    local cols = math.max(4, math.floor((view.w - 24) / 30))
    local rowsN = math.ceil(#ICONS / cols)
    Plate.draw(x, y, math.min(#ICONS, cols) * 30 + 8, rowsN * 44 + 8)
    for n, id in ipairs(ICONS) do
      local c, r = (n - 1) % cols, math.floor((n - 1) / cols)
      local ix, iy = x + 6 + c * 30, y + 6 + r * 44
      Icons.draw(id, ix + 6, iy)
      Icons.draw(id, ix, iy + 16, 2)
    end
  end
  return scene
end

return function(d)
  d:newGame()
  local world = d:world()
  local app = d.game.app
  local dayLength = world.tuning.time.dayLength
  local function at(frac)
    local step = frac - Calendar.now(world).timeOfDay
    if step < 0 then
      step = step + 1
    end
    world.state.calendar.elapsed = world.state.calendar.elapsed + step * dayLength
    d:frames(20, 0.05)
  end
  local kit = kitScene(app)
  app:push(kit)
  at(0.42)
  d:shot("day")
  at(0.93)
  d:shot("night")
  app:pop()
  while not Weather.isFrozen(world) do
    world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  end
  world.state.calendar.elapsed = world.state.calendar.elapsed + dayLength
  for _, label in ipairs({ "Rusty toolbox", "Old axe", "Take it" }) do
    d:tryPress(label)
    d:frames(1, 0.05)
  end
  app:push(kit)
  at(0.5)
  d:shot("winter")
  app:pop()
end
