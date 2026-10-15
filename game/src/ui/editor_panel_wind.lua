-- The editor's Wind panel (GDD D133): hold the wind at a strength whatever the weather says, and change
-- every number that moves with it (sway, cloud and mist drift, dust, rain lean) live. Reset puts the
-- values the panel opened with back; Copy Lua lists the changed numbers to paste into visuals.lua.

local Weather = require("src.sim.systems.weather")
local Knobs = require("src.ui.editor_knobs")
local Layout = require("src.ui.settings_layout")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Panel = {}
Panel.__index = Panel

local STRENGTHS = { { "Auto" }, { "Still", 0 }, { "Breeze", 0.5 }, { "Normal", 1 }, { "Windy", 1.5 }, { "Gale", 2.5 } }
local HEADING_H = 14 -- virtual pixels: a group's title
local HINT_H = 12 -- virtual pixels: its one-line note
local GROUP_GAP = 8 -- virtual pixels between groups
local LABEL_W = 100 -- virtual pixels: a knob's name
local STEP_W = 28 -- virtual pixels: a - or + button
local STATUS_H = 14 -- virtual pixels: the "wind now" line

function Panel.new(editor)
  local tuning = editor.app.ctx.tuning
  return setmetatable({ editor = editor, baseline = Knobs.snapshot(tuning, Knobs.WIND) }, Panel)
end

function Panel:world()
  local session = self.editor.app.ctx.session
  return session and session.world
end

--- Give the wind back to the weather when the editor closes.
function Panel:close()
  local world = self:world()
  if world then
    Weather.setWindOverride(world, nil)
  end
end

function Panel:layout(rect)
  local editor = self.editor
  local tuning = editor.app.ctx.tuning
  local buttons, rowButtons = editor.buttons, editor.rowButtons
  local world = self:world()
  local ctrlH = Layout.controlH(editor.minSize)
  local relayout = function()
    editor:layout()
  end

  -- The wind strength to hold, then what it is now.
  local y = rect.y
  local held = world and world.debugWind
  local rects = Layout.segments(rect.x, y, rect.w, #STRENGTHS, ctrlH, 40)
  for i, s in ipairs(STRENGTHS) do
    local r = rects[i]
    buttons:add({
      x = r.x,
      y = r.y,
      w = r.w,
      h = r.h,
      label = s[1],
      enabled = world ~= nil,
      selected = (s[2] == nil and held == nil) or (s[2] ~= nil and held == s[2]),
      onPress = function()
        Weather.setWindOverride(world, s[2])
        relayout()
      end,
    })
  end
  y = y + ctrlH + Layout.GAP
  self.statusY = y
  y = y + STATUS_H

  -- Footer.
  local fy = rect.y + rect.h - ctrlH - 12
  local half = (rect.w - Layout.GAP) / 2
  buttons:add({
    x = rect.x,
    y = fy,
    w = half,
    h = ctrlH,
    label = "Reset",
    onPress = function()
      Knobs.apply(tuning, Knobs.WIND, self.baseline)
      editor:say("Back to the values this panel opened with")
      relayout()
    end,
  })
  buttons:add({
    x = rect.x + half + Layout.GAP,
    y = fy,
    w = half,
    h = ctrlH,
    label = "Copy Lua",
    onPress = function()
      local text = Knobs.export(tuning, Knobs.WIND)
      love.system.setClipboardText(text)
      print("-- tuning.visuals, find these in data/tuning/visuals.lua:\n" .. text)
      editor:say("Copied to the clipboard (and the console)")
    end,
  })

  -- The knobs.
  local window = { x = rect.x, y = y, w = rect.w, h = fy - y - 4 }
  self.items = {}
  local inner = rect.w - tuning.ui.scrollBarWidth - 6
  local cy = 0
  for _, group in ipairs(Knobs.WIND) do
    self.items[#self.items + 1] = { group = group, y = cy, h = HEADING_H + HINT_H, heading = true }
    cy = cy + HEADING_H + HINT_H
    for _, k in ipairs(group.knobs) do
      self.items[#self.items + 1] = { knob = k, y = cy, h = ctrlH }
      cy = cy + ctrlH + 2
    end
    cy = cy + GROUP_GAP
  end
  editor.list:fit(window, cy, tuning.ui.scrollHintHeight, ctrlH)
  local origin = editor.list:origin()
  for _, item in ipairs(self.items) do
    item.ay = origin + item.y
    item.visible = editor.list:visible(item.ay, item.h)
    item.x, item.w = rect.x, inner
    if item.knob and item.visible then
      local k = item.knob
      item.valueX = rect.x + LABEL_W + STEP_W + 2
      item.valueW = inner - LABEL_W - 2 * STEP_W - 4
      for _, dir in ipairs({ -1, 1 }) do
        rowButtons:add({
          x = dir < 0 and rect.x + LABEL_W or item.valueX + item.valueW + 2,
          y = item.ay,
          w = STEP_W,
          h = ctrlH,
          label = dir < 0 and "-" or "+",
          onPress = function()
            Knobs.change(tuning, k, dir)
            relayout()
          end,
          onRepeat = function()
            if Knobs.change(tuning, k, dir) == nil then
              return false
            end
            relayout()
          end,
        })
      end
    end
  end
end

function Panel:draw()
  local editor = self.editor
  local tuning = editor.app.ctx.tuning
  local world = self:world()
  if world then
    local text = string.format("Wind now %.1f", Weather.windStrength(world))
    text = text .. (world.debugWind and " (held)" or " (the weather's)")
    Text.draw(text, editor.box.x + 8, self.statusY + 1, { size = "small", color = theme.colors.textDim })
  end
  editor.list:begin(editor.app.view.scale)
  for _, item in ipairs(self.items) do
    if item.visible then
      if item.heading then
        Text.draw(item.group.title, item.x, item.ay + 1, { size = "body", color = theme.colors.accent })
        Text.draw(
          item.group.hint,
          item.x,
          item.ay + HEADING_H,
          { size = "small", color = theme.colors.textDim, width = item.w }
        )
      else
        local k = item.knob
        local _, th = Text.measure(k.label, "body")
        Text.draw(k.label, item.x + 4, item.ay + (item.h - th) / 2, { size = "body" })
        Text.draw(Knobs.format(k, Knobs.get(tuning, k)), item.valueX, item.ay + (item.h - th) / 2, {
          size = "body",
          width = item.valueW,
          align = "center",
        })
      end
    end
  end
  editor.rowButtons:draw()
  editor.list:finish()
  editor.list:drawCue(tuning.ui)
end

return Panel
