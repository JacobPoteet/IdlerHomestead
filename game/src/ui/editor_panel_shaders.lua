-- The editor's Shaders panel (GDD D133): scene controls (time, season, weather, freeze) on top, then every
-- dithered effect with its pattern, steps, amount and cell size, each changed live; Compare flips to the
-- values the panel opened with (or the last "Set saved"), Copy Lua puts the values on the clipboard for
-- data/tuning/visuals.lua. The data side is src/ui/editor_shaders.lua.

local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")
local Layout = require("src.ui.settings_layout")
local Model = require("src.ui.editor_shaders")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Panel = {}
Panel.__index = Panel

local TIMES = { { "Dawn", 6 }, { "Noon", 12 }, { "4 pm", 16 }, { "Dusk", 19 }, { "Night", 22 } } -- label, hour
local SKY = { "clear", "cloudy", "rain", "windy", "storm" } -- weather kinds, in the order listed
local HEADING_H = 14 -- virtual pixels: an effect's title
local HINT_H = 12 -- virtual pixels: its one-line note
local EFFECT_GAP = 8 -- virtual pixels between effects
local LABEL_W = 70 -- virtual pixels: a field's name
local STEP_W = 28 -- virtual pixels: a - or + button
local NEAR_HOUR = 1.5 -- hours: a time preset reads as selected this close to it

function Panel.new(editor)
  local tuning = editor.app.ctx.tuning
  return setmetatable({ editor = editor, baseline = Model.snapshot(tuning), compare = false, frozen = false }, Panel)
end

function Panel:tuning()
  return self.editor.app.ctx.tuning
end

function Panel:world()
  local session = self.editor.app.ctx.session
  return session and session.world, session
end

--- Put back what compare mode swapped out and restart the clock if it was frozen (called when the editor closes).
function Panel:close()
  if self.compare then
    self:toggleCompare()
  end
  if self.frozen then
    self:toggleFreeze()
  end
end

function Panel:toggleCompare()
  local tuning = self:tuning()
  if self.compare then
    Model.apply(tuning, self.held)
    self.held, self.compare = nil, false
  else
    self.held = Model.snapshot(tuning)
    Model.apply(tuning, self.baseline)
    self.compare = true
  end
end

function Panel:toggleFreeze()
  local _, session = self:world()
  if not session then
    return
  end
  if self.frozen then
    session:setSpeed(self.resumeSpeed or 1)
    self.frozen = false
  else
    self.resumeSpeed = session:speed()
    session:setSpeed(0)
    self.frozen = true
  end
end

--- One row of equal buttons: `specs` = { { label, onPress, selected, enabled } }. Returns the next y.
function Panel:row(buttons, rect, y, specs)
  local ctrlH = Layout.controlH(self.editor.minSize)
  local rects = Layout.segments(rect.x, y, rect.w, #specs, ctrlH, 40)
  for i, spec in ipairs(specs) do
    local r = rects[i]
    buttons:add({
      x = r.x,
      y = r.y,
      w = r.w,
      h = r.h,
      label = spec[1],
      onPress = spec[2],
      selected = spec[3],
      enabled = spec[4] ~= false,
    })
  end
  return y + ctrlH + Layout.GAP
end

function Panel:layout(rect)
  local editor = self.editor
  local tuning = self:tuning()
  local buttons = editor.buttons
  local world = self:world()
  local relayout = function()
    editor:layout()
  end
  local ctrlH = Layout.controlH(editor.minSize)
  local now = world and Calendar.now(world)
  local live = world ~= nil

  -- Scene controls.
  local y = rect.y
  local specs = {}
  for _, t in ipairs(TIMES) do
    specs[#specs + 1] = {
      t[1],
      function()
        Calendar.skipTo(world, t[2])
        relayout()
      end,
      now and math.abs(now.hour - t[2]) < NEAR_HOUR,
      live,
    }
  end
  y = self:row(buttons, rect, y, specs)
  specs = {}
  for i, season in ipairs(tuning.time.seasons) do
    specs[#specs + 1] = {
      season:sub(1, 1):upper() .. season:sub(2),
      function()
        Calendar.skipTo(world, now.hour, i)
        relayout()
      end,
      now and now.season == season,
      live,
    }
  end
  y = self:row(buttons, rect, y, specs)
  specs = {}
  for _, kind in ipairs(SKY) do
    specs[#specs + 1] = {
      tuning.weather.kinds[kind].label,
      function()
        Weather.force(world, kind)
        relayout()
      end,
      live and Weather.kind(world) == kind,
      live,
    }
  end
  y = self:row(buttons, rect, y, specs)

  -- Footer: freeze and compare, then reset, set saved, copy.
  local footerH = 2 * (ctrlH + Layout.GAP)
  local fy = rect.y + rect.h - footerH - 12
  self:row(buttons, rect, fy, {
    {
      self.frozen and "Frozen" or "Freeze time",
      function()
        self:toggleFreeze()
        relayout()
      end,
      self.frozen,
      live,
    },
    {
      self.compare and "Showing saved" or "Compare saved",
      function()
        self:toggleCompare()
        relayout()
      end,
      self.compare,
    },
  })
  self:row(buttons, rect, fy + ctrlH + Layout.GAP, {
    {
      "Reset",
      function()
        Model.apply(tuning, self.baseline)
        editor:say("Back to the saved values")
        relayout()
      end,
      false,
      not self.compare,
    },
    {
      "Set saved",
      function()
        self.baseline = Model.snapshot(tuning)
        editor:say("Saved: Reset and Compare use these now")
        relayout()
      end,
      false,
      not self.compare,
    },
    {
      "Copy Lua",
      function()
        local text = Model.export(tuning)
        love.system.setClipboardText(text)
        print("-- tuning.visuals.dither, paste into data/tuning/visuals.lua:\n" .. text)
        editor:say("Copied to the clipboard (and the console)")
      end,
    },
  })

  -- The effects, in a scrolling list between the scene controls and the footer.
  local top = y + 2
  local window = { x = rect.x, y = top, w = rect.w, h = fy - top - 4 }
  self.items = {}
  local inner = rect.w - tuning.ui.scrollBarWidth - 6
  local cy = 0
  for _, entry in ipairs(Model.ENTRIES) do
    local cfg = tuning.visuals.dither[entry.id]
    self.items[#self.items + 1] = { entry = entry, y = cy, h = HEADING_H + HINT_H, heading = true }
    cy = cy + HEADING_H + HINT_H
    for _, field in ipairs(Model.fields(cfg)) do
      self.items[#self.items + 1] = { entry = entry, field = field, y = cy, h = ctrlH }
      cy = cy + ctrlH + 2
    end
    cy = cy + EFFECT_GAP
  end
  editor.list:fit(window, cy, tuning.ui.scrollHintHeight, ctrlH)
  local origin = editor.list:origin()
  local rowButtons = editor.rowButtons
  for _, item in ipairs(self.items) do
    item.ay = origin + item.y
    item.visible = editor.list:visible(item.ay, item.h)
    item.x, item.w = rect.x, inner
    if item.field and item.visible then
      local id, field = item.entry.id, item.field
      local f = Model.FIELDS[field]
      local numeric = field ~= "algorithm"
      local function stepper(dir, x)
        rowButtons:add({
          x = x,
          y = item.ay,
          w = STEP_W,
          h = ctrlH,
          label = dir < 0 and "-" or "+",
          enabled = not self.compare,
          onPress = function()
            Model.change(tuning, id, field, dir)
            relayout()
          end,
          onRepeat = numeric and function()
            if Model.change(tuning, id, field, dir) == nil then
              return false
            end
            relayout()
          end or nil,
        })
      end
      item.valueX = rect.x + LABEL_W + STEP_W + 2
      item.valueW = inner - LABEL_W - 2 * STEP_W - 4
      stepper(-1, rect.x + LABEL_W)
      stepper(1, item.valueX + item.valueW + 2)
      item.label = f.label
    end
  end
end

--- The text of a field's value.
local function valueText(cfg, field)
  local v = cfg[field]
  if field == "algorithm" then
    return v
  elseif field == "steps" then
    return v == 0 and "smooth" or tostring(v)
  elseif field == "amount" then
    return string.format("%d%%", math.floor(v * 100 + 0.5))
  end
  return string.format("%d px", v)
end

function Panel:draw()
  local editor = self.editor
  local tuning = self:tuning()
  local scale = editor.app.view.scale
  editor.list:begin(scale)
  for _, item in ipairs(self.items) do
    if item.visible then
      local entry = item.entry
      local cfg = tuning.visuals.dither[entry.id]
      if item.heading then
        local mark = Model.changed(tuning, self.baseline, entry.id) and "  (changed)" or ""
        Text.draw(entry.title .. mark, item.x, item.ay + 1, { size = "body", color = theme.colors.accent })
        Text.draw(
          entry.shader .. ": " .. entry.hint,
          item.x,
          item.ay + HEADING_H,
          { size = "small", color = theme.colors.textDim, width = item.w }
        )
      else
        local _, th = Text.measure(item.label, "body")
        Text.draw(item.label, item.x + 4, item.ay + (item.h - th) / 2, { size = "body" })
        Text.draw(valueText(cfg, item.field), item.valueX, item.ay + (item.h - th) / 2, {
          size = "body",
          width = item.valueW,
          align = "center",
          color = self.compare and theme.colors.textDim or theme.colors.text,
        })
      end
    end
  end
  editor.rowButtons:draw()
  editor.list:finish()
  editor.list:drawCue(editor.app.ctx.tuning.ui)
end

return Panel
