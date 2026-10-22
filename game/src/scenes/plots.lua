-- The plot preview (D200, #384, docs/PLAN_DEPTH.md 12.1): three plots offered for the next run, opened from the recovery
-- scene's Choose land button. Each card shows the plot's traits and its risk and reward; tapping one chooses it, and
-- Done goes back. Entirely optional: Head out without a choice takes the first plot, so skipping this is a fine run.
-- The offer lives in the slot (Run.offerPlots), so it is the same three when the game is quit and reopened.

local Run = require("src.meta.run")
local PlotText = require("src.ui.plot_text")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Plate = require("src.ui.plate")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Plots = { name = "plots" }
Plots.__index = Plots

local TOP = 56 -- virtual pixels from the panel top to the first card
local CARD_GAP = 6
local PAD = 8 -- inside a card

--- opts: { data = slot data, onChange = function() }. The offer must already exist (Run.offerPlots).
function Plots.new(opts)
  return setmetatable({ opts = opts }, Plots)
end

function Plots.open(app, opts)
  app:push(Plots.new(opts))
end

function Plots:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Plots:resize(view)
  self.box = Panel.box(view, 460, view.h - 16)
  self:layout()
end

function Plots:picked()
  local plots = self.opts.data.meta.recovery.plots
  return plots.chosen or 1
end

function Plots:choose(n)
  Run.choosePlot(self.opts.data, n)
  self.app.ctx.store:write(self.opts.slot, self.opts.data) -- the choice survives a quit
  if self.opts.onChange then
    self.opts.onChange()
  end
  self:layout()
end

function Plots:layout()
  local b, ctx = self.box, self.app.ctx
  local tuning, registry = ctx.tuning, ctx.registry
  local list = self.opts.data.meta.recovery.plots.list
  self.buttons:clear()
  self.cards = {}
  local textW = b.w - 24 - PAD * 2
  local y = b.y + TOP
  for n, plot in ipairs(list) do
    local traits = PlotText.traits(tuning, plot)
    local tag = PlotText.tag(registry, tuning, plot)
    local h = PAD * 2 + 14 + Text.wrappedHeight(traits, "small", textW) + 2 + Text.wrappedHeight(tag, "small", textW)
    local card = { n = n, plot = plot, traits = traits, tag = tag, x = b.x + 12, y = y, w = b.w - 24, h = h }
    self.cards[n] = card
    self.buttons:add({
      x = card.x,
      y = card.y,
      w = card.w,
      h = card.h,
      label = PlotText.name(tuning, n),
      onPress = function()
        self:choose(n)
      end,
      draw = function(btn)
        self:drawCard(card, btn)
      end,
    })
    y = y + h + CARD_GAP
  end
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.buttons:add({
    x = b.x + b.w - 92,
    y = b.y + b.h - 36,
    w = 80,
    h = 26,
    label = tuning.plots.words.done,
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
  self.footerW = b.w - 24 - 92
end

function Plots:drawCard(card, btn)
  local colors = theme.colors
  local tuning = self.app.ctx.tuning
  local selected = card.n == self:picked()
  local fill = colors.button
  if self.buttons.pressed == btn or selected then
    fill = colors.buttonPressed
  elseif self.buttons.hovered == btn then
    fill = colors.buttonHover
  end
  Plate.draw(card.x, card.y, card.w, card.h, {
    base = fill,
    kind = "button",
    ink = selected and colors.accent or nil,
    alpha = 1,
    weather = false,
  })
  local tx, textW = card.x + PAD, card.w - PAD * 2
  local y = card.y + PAD
  Text.draw(PlotText.name(tuning, card.n), tx, y, { size = "small", color = colors.text })
  if selected then
    Text.draw(
      tuning.plots.words.chosen,
      tx,
      y,
      { size = "small", width = textW, align = "right", color = colors.accent }
    )
  end
  y = y + 14
  Text.draw(card.traits, tx, y, { size = "small", width = textW, color = colors.text })
  y = y + Text.wrappedHeight(card.traits, "small", textW) + 2
  Text.draw(
    card.tag,
    tx,
    y,
    { size = "small", width = textW, color = card.plot.hazard and colors.accent or colors.textDim }
  )
end

function Plots:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true -- modal: swallow everything
end

function Plots:draw()
  local b, words = self.box, self.app.ctx.tuning.plots.words
  Panel.frame(self.app.view, b, words.title)
  Text.draw(words.intro, b.x + 12, b.y + 24, { size = "small", width = b.w - 24 - 58, color = theme.colors.textDim })
  self.buttons:draw()
  Text.draw(
    words.footer,
    b.x + 12,
    b.y + b.h - 34,
    { size = "small", width = self.footerW, color = theme.colors.textDim }
  )
end

return Plots
