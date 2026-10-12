-- Modal text prompt (e.g. naming a save slot). Opens the on-screen keyboard on mobile.
-- opts: { title, initial, maxLength, confirmLabel, onConfirm(text), onCancel() }

local utf8 = require("utf8")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Prompt = { name = "prompt" }
Prompt.__index = Prompt

function Prompt.new(opts)
  return setmetatable({ opts = opts, text = opts.initial or "", time = 0 }, Prompt)
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Prompt:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Prompt:resize(view)
  local w, h = math.min(300, view.w - 32), 104
  self.box = { x = (view.w - w) / 2, y = (view.h - h) / 2 - 30, w = w, h = h }
  self.field = { x = self.box.x + 12, y = self.box.y + 32, w = w - 24, h = 24 }
  local b = self.box
  local bw = 80
  self.buttons:clear()
  self.okButton = self.buttons:add({
    x = b.x + b.w - bw - 12,
    y = b.y + b.h - 34,
    w = bw,
    h = 24,
    label = self.opts.confirmLabel or "OK",
    style = "accent",
    onPress = function()
      self:confirm()
    end,
  })
  self.buttons:add({
    x = b.x + b.w - bw * 2 - 20,
    y = b.y + b.h - 34,
    w = bw,
    h = 24,
    label = "Cancel",
    onPress = function()
      self:cancel()
    end,
  })
  -- Tell the OS where the field is so the on-screen keyboard doesn't cover it.
  local s = view.scale
  love.keyboard.setTextInput(true, self.field.x * s, self.field.y * s, self.field.w * s, self.field.h * s)
end

function Prompt:exit()
  love.keyboard.setTextInput(false)
end

function Prompt:confirm()
  local value = trim(self.text)
  if value == "" then
    return
  end
  self.app:pop()
  self.opts.onConfirm(value)
end

function Prompt:cancel()
  self.app:pop()
  if self.opts.onCancel then
    self.opts.onCancel()
  end
end

function Prompt:textinput(t)
  local max = self.opts.maxLength or 32
  if utf8.len(self.text) + utf8.len(t) <= max then
    self.text = self.text .. t
  end
end

function Prompt:keypressed(key)
  if key == "backspace" then
    local offset = utf8.offset(self.text, -1)
    if offset then
      self.text = self.text:sub(1, offset - 1)
    end
  elseif key == "return" or key == "kpenter" then
    self:confirm()
  end
end

function Prompt:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" then
    self:cancel()
  elseif name == "select" then
    -- Tapping the field re-opens the keyboard on mobile if it was dismissed.
    local f = self.field
    if data.x >= f.x and data.x < f.x + f.w and data.y >= f.y and data.y < f.y + f.h then
      local s = self.app.view.scale
      love.keyboard.setTextInput(true, f.x * s, f.y * s, f.w * s, f.h * s)
    end
  end
  return true -- modal: swallow everything
end

function Prompt:update(dt)
  self.time = self.time + dt
  self.okButton.enabled = trim(self.text) ~= ""
end

function Prompt:draw()
  local view = self.app.view
  Draw.overlay(view)
  local b, f = self.box, self.field
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw(self.opts.title or "", b.x + 12, b.y + 10, { size = "body" })
  love.graphics.setColor(theme.colors.background)
  love.graphics.rectangle("fill", f.x, f.y, f.w, f.h, 2, 2)
  love.graphics.setColor(theme.colors.panelBorder)
  love.graphics.rectangle("line", f.x + 0.5, f.y + 0.5, f.w - 1, f.h - 1, 2, 2)
  local caret = (self.time % 1 < 0.5) and "|" or ""
  Text.draw(self.text .. caret, f.x + 6, f.y + 6, { size = "body" })
  self.buttons:draw()
end

return Prompt
