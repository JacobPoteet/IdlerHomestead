-- Modal yes/no confirmation.
-- opts: { title, message, confirmLabel, cancelLabel?, danger = bool, onConfirm(), onCancel()? }
-- The box grows to fit a long message.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Confirm = { name = "confirm" }
Confirm.__index = Confirm

function Confirm.new(opts)
  return setmetatable({ opts = opts }, Confirm)
end

function Confirm:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Confirm:resize(view)
  local w = math.min(300, view.w - 32)
  local h = math.max(100, 28 + Text.wrappedHeight(self.opts.message or "", "small", w - 24) + 46)
  self.box = { x = (view.w - w) / 2, y = (view.h - h) / 2, w = w, h = h }
  local b, bw = self.box, 80
  self.buttons:clear()
  self.buttons:add({
    x = b.x + b.w - bw - 12,
    y = b.y + b.h - 34,
    w = bw,
    h = 24,
    label = self.opts.confirmLabel or "OK",
    style = self.opts.danger and "danger" or "accent",
    onPress = function()
      self.app:pop()
      self.opts.onConfirm()
    end,
  })
  self.buttons:add({
    x = b.x + b.w - bw * 2 - 20,
    y = b.y + b.h - 34,
    w = bw,
    h = 24,
    label = self.opts.cancelLabel or "Cancel",
    onPress = function()
      self.app:pop()
      if self.opts.onCancel then
        self.opts.onCancel()
      end
    end,
  })
end

function Confirm:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true -- modal: swallow everything
end

function Confirm:draw()
  Draw.overlay(self.app.view)
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw(self.opts.title or "", b.x + 12, b.y + 10, { size = "body" })
  Text.draw(self.opts.message or "", b.x + 12, b.y + 28, {
    size = "small",
    width = b.w - 24,
    color = theme.colors.textDim,
  })
  self.buttons:draw()
end

return Confirm
