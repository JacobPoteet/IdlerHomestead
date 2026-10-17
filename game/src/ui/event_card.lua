-- The event card (D172, #348, docs/PLAN_DEPTH.md §6.2, §6.3): the card where the player answers a misfortune event.
-- Two option blocks, each with its cost, its effect in plain words and how safe it is (one the player cannot pay is
-- disabled and says why), then the ignore outcome, which is always shown and is itself a tap (the safe, free choice), and
-- the ignore window's timer. Like the Tonight card it is a side card on a wide view and a bottom sheet on a tall one (the
-- place is Tonight.place), never blocks input outside its own rectangle, and every control is a plain button (touch and
-- mouse); Tab and Enter reach the same ones from the keyboard (the scene forwards them). Presentation only: the model is
-- EventText.build, and the answers are the scene's, through Events.choose and Events.ignore.

local Buttons = require("src.ui.buttons")
local EventText = require("src.ui.event_text")
local Plate = require("src.ui.plate")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Card = {}
Card.__index = Card

local LINE = 11 -- pixels per line of the 7 px font

--- `ctx` = the app context (tuning, input).
function Card.new(ctx)
  return setmetatable({
    ctx = ctx,
    cfg = ctx.tuning.ui.eventCard,
    list = ScrollList.new(),
    blocks = Buttons.new(ctx.tuning.input.minTouchTarget),
    items = {},
    order = {},
    model = nil,
    rect = { x = 0, y = 0, w = 0, h = 0 },
    focus = 1,
    focusShown = false,
  }, Card)
end

-- The font needs a window; headless (tests) there is none, and a character-width guess will do.
local function wrapped(str, w)
  local ok, h = pcall(Text.wrappedHeight, str, "small", w)
  if ok then
    return h
  end
  return math.ceil(#str * 6 / math.max(w, 1)) * LINE
end

--- The lines of one block as { text, color, size }, in order: option blocks lead with the label and the cost (or the
--- reason it cannot be chosen), the ignore block with its head.
local function blockLines(block, ignore)
  local colors = theme.colors
  local dim = block.enabled == false
  local lines = {}
  if ignore then
    lines[#lines + 1] = { text = block.head, color = colors.text, size = "body" }
  else
    lines[#lines + 1] = { text = block.label, color = dim and colors.textDim or colors.text, size = "body" }
  end
  lines[#lines + 1] = {
    text = block.cost,
    color = (block.cost == EventText.free or dim) and colors.textDim or colors.accent,
    size = "small",
  }
  if block.reason then
    lines[#lines + 1] = { text = block.reason, color = colors.danger, size = "small" }
  end
  for _, e in ipairs(block.effects) do
    lines[#lines + 1] = { text = "- " .. e, color = colors.text, size = "small" }
  end
  lines[#lines + 1] = { text = block.risk, color = colors.textDim, size = "small" }
  return lines
end

local function linesHeight(lines, w)
  local h = 0
  for _, l in ipairs(lines) do
    h = h + (l.size == "body" and LINE or wrapped(l.text, w))
  end
  return h
end

--- The height the body wants when the card is `w` wide (the strip and the timer not counted).
function Card:measure(model, w)
  local cfg = self.cfg
  local touch = self.ctx.tuning.input.minTouchTarget
  local inner = w - 2 * cfg.blockPad
  local h = wrapped(model.line, w) + cfg.blockGap
  for _, o in ipairs(model.options) do
    h = h + math.max(linesHeight(blockLines(o), inner) + 2 * cfg.blockPad, touch) + cfg.blockGap
  end
  h = h + math.max(linesHeight(blockLines(model.ignore, true), inner) + 2 * cfg.blockPad, cfg.ignoreMinH, touch)
  return h
end

--- The height of the timer under the body: its line and the bar.
function Card:timerHeight()
  return LINE + 2 + self.cfg.barH
end

--- Show `model` (EventText.build) in `rect`. `onChoose(index)` runs on an option, `onIgnore()` on the ignore block.
function Card:setup(model, rect, onChoose, onIgnore)
  self.model, self.rect, self.onChoose, self.onIgnore = model, rect, onChoose, onIgnore
  self:layout()
end

--- Lay the blocks out for the current model, from the scroll offset.
function Card:layout()
  local r, cfg = self.rect, self.cfg
  local touch = self.ctx.tuning.input.minTouchTarget
  local strip = math.max(cfg.stripH, touch)
  self.blocks:clear()
  self.items, self.order = {}, {}
  if not self.model then
    return
  end
  local timerH = self:timerHeight()
  local body = {
    x = r.x + cfg.pad,
    y = r.y + strip + 2,
    w = r.w - 2 * cfg.pad,
    h = r.h - strip - 2 - cfg.pad - timerH - 4,
  }
  local ui = self.ctx.tuning.ui
  local contentH = self:measure(self.model, body.w)
  local view = self.list:fit(body, contentH, ui.scrollHintHeight, touch * 2)
  local right = body.x + body.w - (self.list.overflow and (ui.scrollBarWidth + 4) or 0)
  local left, bw = body.x, right - body.x
  local ry = self.list:origin()
  local top = 0 -- content-space offset, for revealing a focused block
  self.timerRect = { x = body.x, y = r.y + r.h - cfg.pad - timerH, w = body.w }
  local lh = wrapped(self.model.line, bw)
  self.items[#self.items + 1] =
    { x = left, y = ry, str = self.model.line, color = theme.colors.textDim, width = bw, size = "small" }
  ry, top = ry + lh + cfg.blockGap, top + lh + cfg.blockGap
  local function addBlock(block, ignore, press)
    local lines = blockLines(block, ignore)
    local want = linesHeight(lines, bw - 2 * cfg.blockPad) + 2 * cfg.blockPad
    local h = math.max(want, touch, ignore and cfg.ignoreMinH or 0)
    local b = self.blocks:add({
      x = left,
      y = ry,
      w = bw,
      h = h,
      label = ignore and block.head or block.label,
      enabled = block.enabled ~= false,
      onPress = press,
      lines = lines,
      draw = function(btn)
        self:drawBlock(btn)
      end,
    })
    b.top, b.contentH = top, h
    if b.enabled then
      self.order[#self.order + 1] = b
    end
    ry, top = ry + h + cfg.blockGap, top + h + cfg.blockGap
  end
  for _, o in ipairs(self.model.options) do
    addBlock(o, false, function()
      self.onChoose(o.index)
    end)
  end
  addBlock(self.model.ignore, true, function()
    self.onIgnore()
  end)
  self.focus = math.max(1, math.min(self.focus, math.max(#self.order, 1)))
  self.view = view
end

--- Draw one block: a button plate in its state with its lines inside.
function Card:drawBlock(b)
  local colors = theme.colors
  local fill = colors.button
  if not b.enabled then
    fill = colors.buttonDisabled
  elseif self.blocks.pressed == b then
    fill = colors.buttonPressed
  elseif self.blocks.hovered == b then
    fill = colors.buttonHover
  end
  Plate.draw(b.x, b.y, b.w, b.h, {
    base = fill,
    kind = "button",
    lit = self.blocks.pressed == b and 0 or nil,
    alpha = 1,
    weather = false,
  })
  local pad = self.cfg.blockPad
  local y = b.y + pad
  local w = b.w - 2 * pad
  for _, l in ipairs(b.lines) do
    Text.draw(l.text, b.x + pad, y, { size = l.size, color = l.color, width = w })
    y = y + (l.size == "body" and LINE or wrapped(l.text, w))
  end
end

function Card:contains(x, y)
  local r = self.rect
  return x ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Keyboard ---------------------------------------------------------------------------------------------------------

--- Tab: show the ring (on the control it last held, the first to begin with); with the ring showing, move the focus to
--- the next (delta 1) or previous (-1) control, scrolling it into view.
function Card:moveFocus(delta)
  if not self.focusShown then
    self.focusShown = true
  elseif #self.order > 0 then
    self.focus = (self.focus - 1 + delta) % #self.order + 1
  end
  local b = self.order[self.focus]
  if b and self.list.overflow then
    self.list:reveal(b.top, b.contentH)
    self:layout()
  end
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
    if self.list:contains(data.x, data.y) and self.blocks:action(name, data) then
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
  local colors = theme.colors
  Plate.draw(r.x, r.y, r.w, r.h, { kind = "panel", weather = false })
  local strip = math.max(cfg.stripH, self.ctx.tuning.input.minTouchTarget)
  local _, th = Text.measure(model.title, "body")
  Text.draw(model.title, r.x + cfg.pad, r.y + (strip - th) / 2, { size = "body" })
  if model.wake then
    local ww = Text.measure(EventText.wake, "small")
    Text.draw(
      EventText.wake,
      r.x + r.w - cfg.pad - ww,
      r.y + (strip - th) / 2 + 1,
      { size = "small", color = colors.accent }
    )
  end
  self.list:begin(view.scale)
  for _, item in ipairs(self.items) do
    Text.draw(item.str, item.x, item.y, { size = item.size, color = item.color, width = item.width })
  end
  self.blocks:draw()
  self.list:finish()
  self.list:drawCue(self.ctx.tuning.ui)
  -- The ignore window: its words, then a bar that drains as it runs out.
  local t, timer = self.timerRect, model.timer
  Text.draw(timer.text, t.x, t.y, { size = "small", color = colors.textDim })
  local by = t.y + LINE + 2
  love.graphics.setColor(colors.buttonDisabled)
  love.graphics.rectangle("fill", t.x, by, t.w, cfg.barH)
  love.graphics.setColor(colors.accent)
  love.graphics.rectangle("fill", t.x, by, math.floor(t.w * timer.fraction), cfg.barH)
  love.graphics.setColor(1, 1, 1, 1)
  local focus = self:focused()
  if focus then
    love.graphics.setColor(colors.text)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", focus.x - 1.5, focus.y - 1.5, focus.w + 3, focus.h + 3)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Card
