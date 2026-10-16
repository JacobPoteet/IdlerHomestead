-- Menu > Tips (D69, #152): replay any first-time tip, turn the tip cards on or off, or bring them all
-- back. A browse panel: input here does not count against the idle takeover.

local Ftue = require("src.sim.systems.ftue")
local SpoilText = require("src.ui.spoil_text")
local Book = require("src.scenes.book")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Tips = { name = "tips" }
Tips.__index = Tips

function Tips.new(world)
  return setmetatable({ world = world }, Tips)
end

function Tips:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

--- Show one step's text again (the spoilage step shows the live explanation with its real rates).
function Tips:replay(def)
  local world, app = self.world, self.app
  local opts = { title = def.title, message = Ftue.text(world, def), okLabel = "Got it" }
  if def.replay == "spoil" then
    opts.message = SpoilText.explanation(world)
    opts.more = {
      label = "Open Pantry",
      onPress = function()
        Book.open(app, "pantry")
      end,
    }
  end
  app:push(require("src.scenes.notice").new(opts))
end

function Tips:resize(view)
  self.view = view
  local cfg = self.app.ctx.tuning.ftue
  local ROW_H, ROW_GAP, PAD, HEADER_H, LEGEND_H =
    cfg.tipsRowHeight, cfg.tipsRowGap, cfg.tipsPadding, cfg.tipsHeaderHeight, cfg.tipsLegendHeight
  local margin = cfg.tipsViewMargin
  local cols = cfg.tipsColumns
  local steps = Ftue.steps(self.world)
  local function heightFor(c)
    return HEADER_H + ROW_H + ROW_GAP + math.ceil(#steps / c) * (ROW_H + ROW_GAP) + LEGEND_H + ROW_H + 2 * PAD
  end
  -- A short view gets more, narrower columns rather than a list that runs off the screen.
  while
    heightFor(cols) > view.h - margin
    and cols < cfg.tipsMaxColumns
    and (cols + 1) * cfg.tipsMinColumnWidth + 2 * PAD <= view.w - 2 * margin
  do
    cols = cols + 1
  end
  self.cols = cols
  local w = math.min(cfg.tipsBaseWidth + (cols - cfg.tipsColumns) * cfg.tipsColumnWidth, view.w - 2 * margin)
  local h = heightFor(cols)
  self.box = { x = math.floor((view.w - w) / 2), y = math.max(margin / 2, math.floor((view.h - h) / 2)), w = w, h = h }
  local b = self.box
  local inner = b.w - 2 * PAD
  self.buttons:clear()
  local y = b.y + HEADER_H
  local half = math.floor((inner - ROW_GAP) / 2)
  local on = Ftue.enabled(self.world)
  self.buttons:add({
    x = b.x + PAD,
    y = y,
    w = half,
    h = ROW_H,
    label = on and "Tips: on" or "Tips: off",
    style = on and "accent" or nil,
    onPress = function()
      Ftue.setEnabled(self.world, not Ftue.enabled(self.world))
      self:resize(self.view)
    end,
  })
  self.buttons:add({
    x = b.x + PAD + half + ROW_GAP,
    y = y,
    w = half,
    h = ROW_H,
    label = "Show all again",
    onPress = function()
      Ftue.reset(self.world)
      self:resize(self.view)
    end,
  })
  y = y + ROW_H + ROW_GAP
  local colW = math.floor((inner - (cols - 1) * ROW_GAP) / cols)
  for i, step in ipairs(steps) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    self.buttons:add({
      x = b.x + PAD + col * (colW + ROW_GAP),
      y = y + row * (ROW_H + ROW_GAP),
      w = colW,
      h = ROW_H,
      label = step.def.title,
      size = "small",
      dim = step.seen, -- tips already seen are muted, so the ones still to come stand out (D89)
      onPress = function()
        self:replay(step.def)
      end,
    })
  end
  self.buttons:add({
    x = b.x + PAD,
    y = b.y + b.h - PAD - ROW_H,
    w = inner,
    h = ROW_H,
    label = "Close",
    onPress = function()
      self.app:pop()
    end,
  })
end

function Tips:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true -- modal
end

function Tips:draw()
  Draw.overlay(self.app.view)
  local b = self.box
  local cfg = self.app.ctx.tuning.ftue
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw(
    "Tips",
    b.x,
    b.y + cfg.tipsTitleTop,
    { size = "body", width = b.w, align = "center", color = theme.colors.text }
  )
  self.buttons:draw()
  Text.draw(
    "Dim tips are the ones you have seen.",
    b.x,
    b.y + b.h - cfg.tipsPadding - cfg.tipsRowHeight - cfg.tipsLegendHeight + cfg.tipsLegendNudge,
    {
      size = "small",
      width = b.w,
      align = "center",
      color = theme.colors.textDim,
    }
  )
end

return Tips
