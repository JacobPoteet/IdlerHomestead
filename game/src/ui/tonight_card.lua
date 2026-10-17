-- The Tonight card (GDD §4.2, D161, #340): warmth, food, water, shelter, exposure and the risks ahead, each gap with a
-- one-tap fix. A side card on a wide view, a bottom sheet on a tall one (the place is src/ui/tonight.lua). It
-- never blocks input: it answers only inside its own rectangle, so the world stays tappable around it. Every
-- control is a plain button (touch and mouse), and Tab, Enter and Esc reach the same ones from the keyboard (the
-- scene forwards them). Presentation only: the fixes themselves are the scene's, through Dusk.

local Buttons = require("src.ui.buttons")
local Plate = require("src.ui.plate")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local TonightText = require("src.ui.tonight_text")
local theme = require("src.ui.theme")

local Card = {}
Card.__index = Card

--- `ctx` = the app context (tuning, input).
function Card.new(ctx)
  local touch = ctx.tuning.input.minTouchTarget
  return setmetatable({
    ctx = ctx,
    cfg = ctx.tuning.ui.tonight,
    list = ScrollList.new(),
    buttons = Buttons.new(touch), -- the title strip: Close
    rowButtons = Buttons.new(touch), -- the fixes, inside the scrolling body
    items = {},
    model = nil,
    rect = { x = 0, y = 0, w = 0, h = 0 },
    focus = 1,
    focusShown = false,
    order = {},
  }, Card)
end

-- The font needs a window; headless (tests) there is none, and a character-width guess will do.
local function wrapped(str, w)
  local ok, h = pcall(Text.wrappedHeight, str, "small", w)
  if ok then
    return h
  end
  return math.ceil(#str * 6 / math.max(w, 1)) * 10
end

local function width(str, size)
  local ok, w = pcall(Text.measure, str, size)
  return ok and w or #str * 6
end

--- The height the model's rows want when the body is `w` wide (the strip not counted).
function Card:measure(model, w)
  local cfg = self.cfg
  local touch = self.ctx.tuning.input.minTouchTarget
  local h = 0
  for _, row in ipairs(model.rows) do
    h = h + 13 + wrapped(row.text, w) + 2
    if row.fix then
      h = h + math.max(cfg.fixH, touch) + 2
    end
    h = h + cfg.rowGap
  end
  for _, note in ipairs(model.notes) do
    h = h + wrapped(note.text, w) + 2
  end
  return h
end

--- Show `model` (TonightText.build) in `rect`. `onClose()` runs on Close, `onFix(fix)` on a fix button.
function Card:setup(model, rect, onClose, onFix)
  self.model, self.rect, self.onClose, self.onFix = model, rect, onClose, onFix
  self:layout()
end

--- Lay the card out for the current model: the strip's Close, then the rows of the body.
function Card:layout()
  local r, cfg = self.rect, self.cfg
  local touch = self.ctx.tuning.input.minTouchTarget
  local strip = math.max(cfg.stripH, touch)
  self.buttons:clear()
  self.rowButtons:clear()
  self.items, self.order = {}, {}
  if not self.model then
    return
  end
  local bh = strip - 6
  local close = self.buttons:add({
    x = r.x + r.w - cfg.pad - 56,
    y = r.y + 3,
    w = 56,
    h = bh,
    label = TonightText.close,
    onPress = function()
      self.onClose()
    end,
  })
  self.titleW = r.w - 2 * cfg.pad - 56 - 4
  local body = { x = r.x + cfg.pad, y = r.y + strip + 2, w = r.w - 2 * cfg.pad, h = r.h - strip - 2 - cfg.pad }
  local ui = self.ctx.tuning.ui
  local contentH = self:measure(self.model, body.w)
  local view = self.list:fit(body, contentH, ui.scrollHintHeight, cfg.fixH * 2)
  local right = body.x + body.w - (self.list.overflow and (ui.scrollBarWidth + 4) or 0)
  local left, bw = body.x, right - body.x
  local ry = self.list:origin()
  local function visible(y, h)
    return y + h > view.y and y < view.y + view.h
  end
  for _, row in ipairs(self.model.rows) do
    if visible(ry, 13) then
      self.items[#self.items + 1] =
        { kind = "text", x = left, y = ry, str = row.label, color = TonightText.color(row.level), size = "body" }
      local word = row.word
      self.items[#self.items + 1] = {
        kind = "text",
        x = right - width(word, "body"),
        y = ry,
        str = word,
        color = TonightText.color(row.level),
        size = "body",
      }
    end
    ry = ry + 13
    local th = wrapped(row.text, bw)
    if visible(ry, th) then
      self.items[#self.items + 1] =
        { kind = "text", x = left, y = ry, str = row.text, color = theme.colors.textDim, width = bw, size = "small" }
    end
    ry = ry + th + 2
    if row.fix then
      local fh = math.max(cfg.fixH, touch)
      if visible(ry, fh) then
        local fix = row.fix
        local button = self.rowButtons:add({
          x = left,
          y = ry,
          w = bw,
          h = fh,
          label = fix.label,
          enabled = not fix.queued,
          style = (row.level >= 2 and "danger") or nil,
          size = "small",
          onPress = function()
            self.onFix(fix)
          end,
        })
        if button.enabled then
          self.order[#self.order + 1] = button
        end
      end
      ry = ry + fh + 2
    end
    ry = ry + cfg.rowGap
  end
  for _, note in ipairs(self.model.notes) do
    local nh = wrapped(note.text, bw)
    if visible(ry, nh) then
      self.items[#self.items + 1] = {
        kind = "text",
        x = left,
        y = ry,
        str = note.text,
        color = note.dim and theme.colors.textDim or theme.colors.text,
        width = bw,
        size = "small",
      }
    end
    ry = ry + nh + 2
  end
  self.order[#self.order + 1] = close
  self.focus = math.max(1, math.min(self.focus, #self.order))
end

function Card:contains(x, y)
  local r = self.rect
  return x ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Keyboard ---------------------------------------------------------------------------------------------------------

--- Tab: show the ring (on the control it last held, the first to begin with); with the ring showing, move the focus
--- to the next (delta 1) or previous (-1) control. Controls scrolled out of view are not on the order.
function Card:moveFocus(delta)
  if not self.focusShown then
    self.focusShown = true
    return
  end
  if #self.order == 0 then
    return
  end
  self.focus = (self.focus - 1 + delta) % #self.order + 1
end

--- Enter: press the focused control. Returns true when something was pressed.
function Card:activate()
  local b = self.order[self.focus]
  if b and b.enabled and b.onPress then
    b.onPress(b)
    return true
  end
  return false
end

--- The focused control (for the ring), or nil while the ring is hidden.
function Card:focused()
  if not self.focusShown then
    return nil
  end
  return self.order[self.focus]
end

-- Input -------------------------------------------------------------------------------------------------------------

--- Feed an input action. Returns true when the card used it (it only answers inside its rect, so the world stays
--- tappable around it).
function Card:action(name, data)
  if name == "press" or name == "release" then
    self.list:action(name, data)
  end
  local inside = self:contains(data.x, data.y)
  if name == "release" then
    self.grab = false
  elseif name == "press" then
    self.grab = inside -- a drag that starts on the card scrolls it (a pan carries no position)
    self.focusShown = false -- a pointer press puts the keyboard ring away
  end
  if (name == "press" or name == "select" or name == "hover" or name == "release") and inside then
    if self.buttons:action(name, data) then
      return true
    end
    if self.list:contains(data.x, data.y) and self.rowButtons:action(name, data) then
      return true
    end
    return name ~= "hover"
  end
  local mine = name == "zoom" and inside or name == "pan" and not data.keys and (self.grab or inside)
  if mine then
    if self.list:action(name, data, self.ctx.tuning.ui) then
      self:layout()
    end
    return true
  end
  return false
end

-- Drawing -----------------------------------------------------------------------------------------------------------

function Card:draw(view)
  local r, cfg = self.rect, self.cfg
  local model = self.model
  Plate.draw(r.x, r.y, r.w, r.h, { kind = "panel", weather = false })
  local strip = math.max(cfg.stripH, self.ctx.tuning.input.minTouchTarget)
  local _, th = Text.measure(model.title, "body")
  local ty = r.y + (strip - th) / 2
  Text.draw(model.title, r.x + cfg.pad, ty, { size = "body" })
  local sub = model.subtitle
  local x = r.x + cfg.pad + Text.measure(model.title, "body") + 8
  if x + Text.measure(sub, "small") < r.x + self.titleW then
    Text.draw(sub, x, ty + 1, { size = "small", color = theme.colors.textDim })
  end
  self.buttons:draw()
  self.list:begin(view.scale)
  for _, item in ipairs(self.items) do
    Text.draw(item.str, item.x, item.y, { size = item.size, color = item.color, width = item.width })
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(self.ctx.tuning.ui)
  local focus = self:focused()
  if focus then
    love.graphics.setColor(theme.colors.text)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", focus.x - 1.5, focus.y - 1.5, focus.w + 3, focus.h + 3)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Card
