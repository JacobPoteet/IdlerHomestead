-- Settings > Controls (D121, #237): every rebindable keyboard action with its key. Tap a row's key, press
-- the new key (Esc cancels); a key that another action owns asks to swap or keep; per-row and global reset.
-- Overrides are saved in the settings file (not a save slot) and merged over tuning.input.keyActions by
-- src/core/key_bindings.lua. Rows are touch-sized, so the screen opens and reads on a phone, but binding
-- a key needs a keyboard.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local KeyBindings = require("src.core.key_bindings")
local Layout = require("src.ui.settings_layout")
local ScrollList = require("src.ui.scroll_list")
local Strings = require("src.ui.controls_text")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Controls = { name = "controls", opaque = true }
Controls.__index = Controls

function Controls.new()
  return setmetatable({ list = ScrollList.new(), waiting = nil, pending = nil, message = nil }, Controls)
end

function Controls:enter()
  local minSize = self.app.ctx.tuning.input.minTouchTarget
  self.buttons = Buttons.new(minSize)
  self.rowButtons = Buttons.new(minSize)
  self.list.onMove = function()
    self:layout()
  end
  self:layout()
end

function Controls:resize()
  self:layout()
end

function Controls:exit()
  self:stopWaiting()
end

function Controls:overrides()
  return self.app.ctx.settings:keyOverrides()
end

function Controls:stopWaiting()
  self.waiting = nil
  self.app.ctx.input:endCapture()
end

--- Wait for the next key press for `action`.
function Controls:startWaiting(action)
  self.pending = nil
  self.message = nil
  self.waiting = action
  self.app.ctx.input:beginCapture(function(key)
    self:captured(action, key)
  end)
  self:layout()
end

--- Drop any half-finished rebind or question and clear the message.
function Controls:clearState()
  self:stopWaiting()
  self.pending = nil
  self.message = nil
end

--- The key the player pressed while waiting for `action`.
function Controls:captured(action, key)
  self.waiting = nil
  if key == "escape" then
    self.message = nil
    self:layout()
    return
  end
  local cfg = self.app.ctx.tuning.input
  local status, result, other = KeyBindings.bind(cfg, self:overrides(), action, key)
  if status == "reserved" then
    self:startWaiting(action) -- stay on this row until a usable key or Esc
    self.message = Strings.reserved(key)
  elseif status == "conflict" then
    self.pending = { action = action, key = key, other = other }
    self.message = Strings.conflict(key, other)
  elseif status == "ok" then
    self.app.ctx.settings:setKeyOverrides(result)
    self.message = Strings.bound(action, key)
  else
    self.message = nil
  end
  self:layout()
end

function Controls:resolveSwap(doSwap)
  local p = self.pending
  self.pending = nil
  self.message = nil
  if p and doSwap then
    local cfg = self.app.ctx.tuning.input
    local status, result, other = KeyBindings.swap(cfg, self:overrides(), p.action, p.key)
    if status == "swapped" then
      self.app.ctx.settings:setKeyOverrides(result)
      local eff = KeyBindings.effective(cfg, result)
      self.message = Strings.swapped(p.action, p.key, other, eff[other])
    end
  end
  self:layout()
end

function Controls:layout()
  local app = self.app
  local tuning = app.ctx.tuning
  local cfg = tuning.input
  local ui = tuning.ui.controls
  local P = Layout.panel(app.view, tuning.settings, cfg.minTouchTarget)
  self.box = P.box
  self.buttons:clear()
  self.rowButtons:clear()
  local ctrlH = Layout.controlH(cfg.minTouchTarget)
  local x0 = P.list.x + Layout.PAD
  local innerW = P.list.w - 2 * Layout.PAD - tuning.ui.scrollBarWidth - 4

  -- The message band sits under the title; the list takes the rest.
  self.band = { x = x0, y = P.list.y, w = P.list.w - 2 * Layout.PAD, h = ui.bandHeight }
  local listRect = { x = P.list.x, y = P.list.y + ui.bandHeight, w = P.list.w, h = P.list.h - ui.bandHeight }

  local overrides = self:overrides()
  local eff = KeyBindings.effective(cfg, overrides)
  local y = 0
  self.items = {}
  for _, action in ipairs(KeyBindings.actions(cfg)) do
    self.items[#self.items + 1] = { action = action, y = y, h = ctrlH }
    y = y + ctrlH + ui.rowGap
  end
  local noteH = Text.wrappedHeight(Strings.fixedNote, "small", innerW)
  self.items[#self.items + 1] = { note = Strings.fixedNote, y = y, h = noteH }
  y = y + noteH + ui.rowGap

  self.window = self.list:fit(listRect, y, tuning.ui.scrollHintHeight, ctrlH)
  local top = self.list:origin()
  local resetX = x0 + innerW - ui.resetWidth
  local keyX = resetX - ui.buttonGap - ui.keyWidth
  for _, item in ipairs(self.items) do
    item.ay = top + item.y
    item.visible = self.list:visible(item.ay, item.h)
    local action = item.action
    if action and item.visible then
      local waiting = self.waiting == action
      self.rowButtons:add({
        x = keyX,
        y = item.ay,
        w = ui.keyWidth,
        h = ctrlH,
        label = waiting and Strings.waiting or Strings.keyName(eff[action]),
        selected = waiting,
        onPress = function()
          local wasWaiting = self.waiting == action
          self:clearState()
          if wasWaiting then
            self:layout()
          else
            self:startWaiting(action)
          end
        end,
      })
      self.rowButtons:add({
        x = resetX,
        y = item.ay,
        w = ui.resetWidth,
        h = ctrlH,
        label = Strings.resetRow,
        enabled = overrides[action] ~= nil,
        onPress = function()
          self:clearState()
          self.app.ctx.settings:setKeyOverrides(KeyBindings.reset(cfg, self:overrides(), action))
          self:layout()
        end,
      })
    end
  end

  if self.pending then
    local bw = (self.band.w - ui.buttonGap) / 2
    local by = self.band.y + self.band.h - ctrlH - ui.rowGap
    self.buttons:add({
      x = self.band.x,
      y = by,
      w = bw,
      h = ctrlH,
      label = Strings.swap,
      style = "accent",
      onPress = function()
        self:resolveSwap(true)
      end,
    })
    self.buttons:add({
      x = self.band.x + bw + ui.buttonGap,
      y = by,
      w = bw,
      h = ctrlH,
      label = Strings.keep,
      onPress = function()
        self:resolveSwap(false)
      end,
    })
  end
  self.buttons:add({
    x = P.defaults.x,
    y = P.defaults.y,
    w = P.defaults.w,
    h = P.defaults.h,
    label = Strings.resetAll,
    enabled = next(overrides) ~= nil,
    onPress = function()
      self:clearState()
      self.app.ctx.settings:setKeyOverrides({})
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
end

function Controls:action(name, data)
  if name == "press" or name == "release" then
    self.list:action(name, data)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "select" and self.waiting and not self.rowButtons:hit(data.x, data.y) then
    self:clearState() -- a tap away from the key buttons abandons the rebind
    self:layout()
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    if self.list:contains(data.x, data.y) then
      self.rowButtons:action(name, data)
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    if self.pending then
      self:resolveSwap(false)
    else
      self.app:pop()
    end
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout()
  end
  return true
end

function Controls:draw()
  local ctx = self.app.ctx
  local b = self.box
  local ui = ctx.tuning.ui.controls
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw(Strings.title, b.x + Layout.PAD, b.y + 8, { size = "heading" })
  local band = self.band
  Text.draw(self.message or Strings.hint, band.x, band.y + 2, {
    size = "small",
    width = band.w,
    color = self.pending and theme.colors.accent or theme.colors.textDim,
  })
  self.list:begin(self.app.view.scale)
  local x0 = b.x + Layout.PAD
  local innerW = b.w - 2 * Layout.PAD - ctx.tuning.ui.scrollBarWidth - 4
  local textW = innerW - ui.resetWidth - ui.keyWidth - 2 * ui.buttonGap
  for _, item in ipairs(self.items) do
    if item.visible then
      if item.action then
        local def = Strings.actions[item.action]
        Text.draw(def[1], x0, item.ay + 2, { size = "body", width = textW })
        Text.draw(def[2], x0, item.ay + 15, { size = "small", width = textW, color = theme.colors.textDim })
      else
        Text.draw(item.note, x0, item.ay, { size = "small", width = innerW, color = theme.colors.textDim })
      end
    end
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(ctx.tuning.ui)
  self.buttons:draw()
end

return Controls
