-- The message log panel (D90, #167): the last lines the toasts said, newest first, in a scrolling list.
-- Opened from the homestead by tapping a toast or the Log button. A browse panel: it reads the log
-- the homestead keeps (src/ui/message_log.lua) and changes nothing.

local Buttons = require("src.ui.buttons")
local MessageLog = require("src.ui.message_log")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Scene = { name = "message_log" }
Scene.__index = Scene

local PAD, HEAD_H, WHEN_H, ROW_GAP = 12, 38, 11, 7

function Scene.new(log)
  return setmetatable({ log = log, list = ScrollList.new() }, Scene)
end

function Scene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Scene:resize(view)
  self.box = Panel.box(view, self.app.ctx.tuning.ui.log.panelWidth, view.h - 16)
  self:layout()
end

function Scene:layout()
  local b, ui = self.box, self.app.ctx.tuning.ui
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  -- Each row is its date line, then the text wrapped to the panel; rows are measured once per layout.
  local textW = b.w - 2 * PAD - ui.scrollBarWidth - 4
  self.rows, self.contentH = {}, 0
  for _, line in ipairs(self.log:lines()) do
    local label = MessageLog.label(line)
    local h = WHEN_H + Text.wrappedHeight(label, "small", textW) + ROW_GAP
    self.rows[#self.rows + 1] = { line = line, label = label, top = self.contentH, h = h }
    self.contentH = self.contentH + h
  end
  local top = b.y + HEAD_H
  self.textW = textW
  self.list:fit({ x = b.x, y = top, w = b.w, h = b.y + b.h - 6 - top }, self.contentH, ui.scrollHintHeight, 20)
end

function Scene:update()
  local lines = self.log:lines()
  local newest = lines[1]
  if #lines ~= self.seenCount or (newest and newest.count ~= self.seenNewest) then
    self.seenCount, self.seenNewest = #lines, newest and newest.count
    self:layout() -- news that arrives while the log is open joins the list
  end
end

function Scene:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui.scrollWheelStep) then
    -- the list follows the finger; the rows are positioned from the offset when drawn
  end
  return true -- modal
end

function Scene:draw()
  local b = self.box
  Panel.frame(self.app.view, b, "Message log", "Newest first. Tap a toast or Log to open.")
  local dim = theme.colors.textDim
  self.list:begin(self.app.view.scale)
  local y0 = self.list:origin()
  for n, row in ipairs(self.rows) do
    local y = y0 + row.top
    if self.list:visible(y, row.h) then
      Text.draw(MessageLog.when(row.line), b.x + PAD, y, { size = "small", color = dim })
      Text.draw(row.label, b.x + PAD, y + WHEN_H, { size = "small", width = self.textW, color = theme.colors.text })
    end
  end
  self.list:finish()
  if #self.rows == 0 then
    Text.draw("Nothing yet. News from the homestead lands here.", b.x + PAD, self.list.view.y + 4, { size = "small", color = dim })
  end
  self.list:drawCue(self.app.ctx.tuning.ui)
  self.buttons:draw()
end

return Scene
