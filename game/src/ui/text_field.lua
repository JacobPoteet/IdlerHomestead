-- A single-line text field (GDD D120, #208): the state and editing of one line of typed text, plus the
-- drawing of its box. Typing comes from `textinput` (physical keyboard or the on-screen one), Backspace
-- from `keypressed`; focusing it asks the OS for the on-screen keyboard where the field sits. Everything
-- about the text itself is pure and unit-tested; only focus() / blur() / draw() touch love.
--
--   local field = TextField.new(maxLength)
--   field:insert(text)  field:backspace()  field:clear()  field:isEmpty()
--   field:focus(rect, scale)  field:blur()  field:draw(rect, opts)

local utf8 = require("utf8")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local TextField = {}
TextField.__index = TextField

function TextField.new(maxLength)
  return setmetatable({ text = "", focused = false, max = maxLength, time = 0 }, TextField)
end

--- Add typed text at the end. Control characters (newlines, tabs) are dropped; text that would pass the
--- length limit is cut, never rejected whole, so a paste still lands what fits.
function TextField:insert(t)
  t = t:gsub("%c", "")
  for _, code in utf8.codes(t) do
    if utf8.len(self.text) >= self.max then
      break
    end
    self.text = self.text .. utf8.char(code)
  end
end

--- Remove the last character (a whole UTF-8 character).
function TextField:backspace()
  local offset = utf8.offset(self.text, -1)
  if offset then
    self.text = self.text:sub(1, offset - 1)
  end
end

function TextField:clear()
  self.text = ""
end

function TextField:isEmpty()
  return self.text == ""
end

--- Give the field the keyboard. `rect` is where it sits, in virtual pixels, so the OS can keep the
--- on-screen keyboard from covering it; `scale` is the view's pixel scale.
function TextField:focus(rect, scale)
  self.focused, self.time = true, 0
  love.keyboard.setTextInput(true, rect.x * scale, rect.y * scale, rect.w * scale, rect.h * scale)
end

--- Take the keyboard away. A touch device hides the on-screen keyboard; a desktop keeps text input on.
function TextField:blur()
  self.focused = false
  if require("src.core.platform").has("touchPrimary") then
    love.keyboard.setTextInput(false)
  end
end

function TextField:update(dt)
  self.time = self.time + dt
end

--- Draw the box with the text (or `opts.placeholder` while empty) and, while focused, a blinking caret.
--- opts: { placeholder, pad, blink }
function TextField:draw(rect, opts)
  local colors = theme.colors
  local _, lineH = Text.measure("A", "small")
  love.graphics.setColor(colors.background)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
  love.graphics.setColor(self.focused and colors.accent or colors.panelBorder)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1, 3, 3)
  local y = rect.y + (rect.h - lineH) / 2
  local width = rect.w - 2 * opts.pad
  if self.text == "" then
    Text.draw(opts.placeholder, rect.x + opts.pad, y, { size = "small", color = colors.textDim, width = width })
  else
    Text.draw(self.text, rect.x + opts.pad, y, { size = "small", width = width })
  end
  if self.focused and self.time % opts.blink < opts.blink / 2 then
    local w = self.text == "" and 0 or Text.measure(self.text, "small")
    love.graphics.setColor(colors.text)
    love.graphics.rectangle("fill", rect.x + opts.pad + math.min(w, width) + 1, y, 1, lineH)
  end
end

return TextField
