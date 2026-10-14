-- Settings screen (GDD D96, #50). Draws the options declared in src/core/settings_options.lua and
-- routes input; the values, validation and storage live in src/core/settings.lua. Reachable from the
-- title screen and from the in-game Menu. Changes apply at once and are saved at once.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Layout = require("src.ui.settings_layout")
local Options = require("src.core.settings_options")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Settings = { name = "settings", opaque = true }
Settings.__index = Settings

local HEADING_H = 20 -- virtual pixels per group heading
local LABEL_H = 14 -- virtual pixels for an option's label line
local NOTE_GAP = 2 -- virtual pixels between a control and its note
local ITEM_GAP = 8 -- virtual pixels after each option

function Settings.new()
  return setmetatable({ list = ScrollList.new() }, Settings)
end

function Settings:enter()
  local minSize = self.app.ctx.tuning.input.minTouchTarget
  self.buttons = Buttons.new(minSize)
  self.rowButtons = Buttons.new(minSize)
  self.list.onMove = function()
    self:layout()
  end
end

function Settings:resize()
  self:layout()
end

local function noteOf(opt, settings, env)
  return opt.note and opt.note(settings, env) or nil
end

function Settings:layout()
  local app = self.app
  local ctx = app.ctx
  local tuning = ctx.tuning
  local settings = ctx.settings
  local minTouch = tuning.input.minTouchTarget
  local env = ctx.settingsEnv()
  local P = Layout.panel(app.view, tuning.settings, minTouch)
  self.box = P.box
  self.buttons:clear()
  self.rowButtons:clear()
  self.items = {}

  local ctrlH = Layout.controlH(minTouch)
  local innerW = P.list.w - 2 * Layout.PAD - tuning.ui.scrollBarWidth - 4
  local x0 = P.list.x + Layout.PAD

  -- First pass: item heights (positions relative to the list top), so the list can fit and clamp.
  local y = 0
  local lastGroup
  for _, opt in ipairs(settings:visible(ctx.platform)) do
    if opt.group ~= lastGroup then
      lastGroup = opt.group
      self.items[#self.items + 1] = { heading = opt.group, y = y, h = HEADING_H }
      y = y + HEADING_H
    end
    local item = { opt = opt, y = y, note = noteOf(opt, settings, env) }
    local h
    if opt.kind == "toggle" then
      h = ctrlH
    elseif opt.kind == "slider" then
      h = LABEL_H + ctrlH
    else
      item.entries = Options.choicesOf(opt, settings, env)
      local _, segH = Layout.segments(x0, 0, innerW, #item.entries, ctrlH, tuning.settings.minSegment)
      h = LABEL_H + segH
    end
    if item.note then
      h = h + NOTE_GAP + Text.wrappedHeight(item.note, "small", innerW)
    end
    item.h = h
    y = y + h + ITEM_GAP
    self.items[#self.items + 1] = item
  end
  -- Not an option: opens the sound test (D100).
  self.items[#self.items + 1] = { heading = "Sound test", y = y, h = HEADING_H }
  y = y + HEADING_H
  self.items[#self.items + 1] = { soundTest = true, y = y, h = ctrlH }
  y = y + ctrlH + ITEM_GAP

  local window = self.list:fit(P.list, y, tuning.ui.scrollHintHeight, ctrlH)
  local top = self.list:origin()

  -- Second pass: buttons for rows in view.
  for _, item in ipairs(self.items) do
    item.ay = top + item.y
    item.visible = self.list:visible(item.ay, item.h)
    local opt = item.opt
    if item.soundTest and item.visible then
      self.rowButtons:add({
        x = x0,
        y = item.ay,
        w = innerW,
        h = ctrlH,
        label = "Listen to every sound",
        onPress = function()
          self.app:push(require("src.scenes.sound_test").new())
        end,
      })
    end
    if opt and item.visible then
      local value = settings:get(opt.id)
      if opt.kind == "toggle" then
        local bw = 64
        self.rowButtons:add({
          x = x0 + innerW - bw,
          y = item.ay,
          w = bw,
          h = ctrlH,
          label = value and "On" or "Off",
          selected = value,
          onPress = function()
            settings:set(opt.id, not value)
            self:layout()
          end,
        })
        item.noteY = item.ay + ctrlH + NOTE_GAP
      elseif opt.kind == "slider" then
        local by = item.ay + LABEL_H
        local bw = 40
        local function nudge(dir)
          return function()
            settings:set(opt.id, value + dir * opt.step)
            self:layout()
          end
        end
        self.rowButtons:add({ x = x0, y = by, w = bw, h = ctrlH, label = "-", enabled = value > opt.min, onPress = nudge(-1) })
        self.rowButtons:add({ x = x0 + innerW - bw, y = by, w = bw, h = ctrlH, label = "+", enabled = value < opt.max, onPress = nudge(1) })
        item.bar = { x = x0 + bw + 6, y = by + ctrlH / 2 - 3, w = innerW - 2 * bw - 12, h = 6 }
        item.noteY = by + ctrlH + NOTE_GAP
      else
        local rects, segH = Layout.segments(x0, item.ay + LABEL_H, innerW, #item.entries, ctrlH, tuning.settings.minSegment)
        for i, entry in ipairs(item.entries) do
          local r = rects[i]
          self.rowButtons:add({
            x = r.x,
            y = r.y,
            w = r.w,
            h = r.h,
            label = entry.label,
            selected = entry.selected == nil and entry.value == value or entry.selected == true,
            enabled = entry.enabled ~= false,
            onPress = function()
              settings:set(opt.id, entry.value)
              self:layout()
            end,
          })
        end
        item.noteY = item.ay + LABEL_H + segH + NOTE_GAP
      end
    end
  end

  self.buttons:add({
    x = P.defaults.x,
    y = P.defaults.y,
    w = P.defaults.w,
    h = P.defaults.h,
    label = "Defaults",
    onPress = function()
      settings:reset()
      self:layout()
    end,
  })
  self.buttons:add({
    x = P.done.x,
    y = P.done.y,
    w = P.done.w,
    h = P.done.h,
    label = "Done",
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
  self.window = window
end

function Settings:exit()
  self.app.ctx.settings:save()
end

--- A tap on a slider's bar sets the value there (the -/+ buttons stay for fine steps). True if handled.
function Settings:tapBar(x, y)
  if not self.list:contains(x, y) then
    return false
  end
  local ctrlH = Layout.controlH(self.app.ctx.tuning.input.minTouchTarget)
  for _, item in ipairs(self.items) do
    local bar = item.visible and item.bar
    if bar and x >= bar.x and x <= bar.x + bar.w and y >= bar.y + bar.h / 2 - ctrlH / 2 and y <= bar.y + bar.h / 2 + ctrlH / 2 then
      local opt = item.opt
      self.app.ctx.settings:set(opt.id, opt.min + (opt.max - opt.min) * (x - bar.x) / bar.w)
      self:layout()
      return true
    end
  end
  return false
end

function Settings:action(name, data)
  if name == "press" or name == "release" then
    self.list:action(name, data) -- a drag that ends moving lets the list coast (D94)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "select" and self:tapBar(data.x, data.y) then
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    -- Row buttons only answer inside the list's window: a half-scrolled row must not reach out of it.
    if self.list:contains(data.x, data.y) then
      self.rowButtons:action(name, data)
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout()
  end
  return true
end

function Settings:draw()
  local ctx = self.app.ctx
  local settings = ctx.settings
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Settings", b.x + Layout.PAD, b.y + 8, { size = "heading" })
  self.list:begin(self.app.view.scale)
  for _, item in ipairs(self.items) do
    if item.visible then
      local x0 = b.x + Layout.PAD
      local innerW = b.w - 2 * Layout.PAD - ctx.tuning.ui.scrollBarWidth - 4
      if item.heading then
        Text.draw(item.heading, x0, item.ay + 4, { size = "body", color = theme.colors.accent })
      elseif item.opt then
        local opt = item.opt
        local value = settings:get(opt.id)
        local labelY = item.ay + (opt.kind == "toggle" and (Layout.controlH(ctx.tuning.input.minTouchTarget) - 12) / 2 or 0)
        Text.draw(opt.label, x0, labelY, { size = "body", width = innerW - 70 })
        if opt.kind == "slider" then
          Text.draw(Options.valueText(opt, value), x0, labelY, { size = "body", width = innerW, align = "right", color = theme.colors.accent })
          local bar = item.bar
          love.graphics.setColor(0, 0, 0, 0.4)
          love.graphics.rectangle("fill", bar.x, bar.y, bar.w, bar.h, 2, 2)
          love.graphics.setColor(theme.colors.accent)
          love.graphics.rectangle("fill", bar.x, bar.y, bar.w * (value - opt.min) / (opt.max - opt.min), bar.h, 2, 2)
        end
        if item.note then
          Text.draw(item.note, x0, item.noteY, { size = "small", width = innerW, color = theme.colors.textDim })
        end
      end
    end
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(ctx.tuning.ui)
  self.buttons:draw()
end

return Settings
