-- Modal information card: a title, a wrapped message and one or two buttons.
-- opts: { title, headline? (accent line above the message), message?, okLabel = "Got it",
--         tone? (colour of the headline, default accent), rows? = { { label, value } } (labelled numbers under the headline), why? (one short dim line),
--         width? (virtual pixels, default 340), more? = { label, onPress() } }
-- `more` is an optional second button (for example "Open Pantry"); the card closes first.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Notice = { name = "notice" }
Notice.__index = Notice

function Notice.new(opts)
  return setmetatable({ opts = opts }, Notice)
end

function Notice:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Notice:resize(view)
  local w = math.min(self.opts.width or 340, view.w - 24)
  local inner = w - 24
  local rowGap = self.app.ctx.tuning.ui.modal.rowGap
  self.headline = self.opts.headline
  self.headlineSize = self.opts.rows and "body" or "small" -- chip modals (D112) lead with a larger status line
  self.headlineH = self.headline and Text.wrappedHeight(self.headline, self.headlineSize, inner) + 6 or 0
  self.rows = self.opts.rows or {}
  self.rowH = select(2, Text.measure("Ag", "small")) + rowGap
  self.rowsH = #self.rows * self.rowH + (#self.rows > 0 and 4 or 0)
  local message = self.opts.message
  self.messageH = message and Text.wrappedHeight(message, "small", inner) or 0
  self.why = self.opts.why
  self.whyH = self.why and Text.wrappedHeight(self.why, "small", inner) + 2 or 0
  local h = 28 + self.headlineH + self.rowsH + self.messageH + self.whyH + 46
  self.box = { x = math.floor((view.w - w) / 2), y = math.floor((view.h - h) / 2), w = w, h = h }
  local b, bw = self.box, 96
  self.buttons:clear()
  self.buttons:add({
    x = b.x + b.w - bw - 12,
    y = b.y + b.h - 34,
    w = bw,
    h = 24,
    label = self.opts.okLabel or "Got it",
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
  local more = self.opts.more
  if more then
    self.buttons:add({
      x = b.x + b.w - bw * 2 - 20,
      y = b.y + b.h - 34,
      w = bw,
      h = 24,
      label = more.label,
      onPress = function()
        self.app:pop()
        more.onPress()
      end,
    })
  end
end

function Notice:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true -- modal: swallow everything
end

function Notice:draw()
  Draw.overlay(self.app.view)
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw(self.opts.title or "", b.x + 12, b.y + 10, { size = "body" })
  local y = b.y + 28
  if self.headline then
    Text.draw(
      self.headline,
      b.x + 12,
      y,
      { size = self.headlineSize, width = b.w - 24, color = self.opts.tone or theme.colors.accent }
    )
    y = y + self.headlineH
  end
  for _, row in ipairs(self.rows) do
    Text.draw(row.label, b.x + 12, y, { size = "small", color = theme.colors.textDim })
    Text.draw(row.value, b.x + 12, y, { size = "small", width = b.w - 24, align = "right" })
    y = y + self.rowH
  end
  if #self.rows > 0 then
    y = y + 4
  end
  if self.opts.message then
    Text.draw(self.opts.message, b.x + 12, y, { size = "small", width = b.w - 24, color = theme.colors.textDim })
    y = y + self.messageH
  end
  if self.why then
    Text.draw(self.why, b.x + 12, y + 2, { size = "small", width = b.w - 24, color = theme.colors.textDim })
  end
  self.buttons:draw()
end

return Notice
