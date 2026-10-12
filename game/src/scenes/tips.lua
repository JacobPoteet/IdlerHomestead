-- Menu > Tips (D69, #152): replay any first-time tip, turn the tip cards on or off, or bring them all
-- back. A browse panel: input here does not count against the idle takeover.

local Ftue = require("src.sim.systems.ftue")
local SpoilText = require("src.ui.spoil_text")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Tips = { name = "tips" }
Tips.__index = Tips

local ROW_H, ROW_GAP, PAD, HEADER_H = 26, 4, 12, 30

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
        app:push(require("src.scenes.pantry").new(world))
      end,
    }
  end
  app:push(require("src.scenes.notice").new(opts))
end

function Tips:resize(view)
  self.view = view
  local cols = self.app.ctx.tuning.ftue.tipsColumns
  local steps = Ftue.steps(self.world)
  local rows = math.ceil(#steps / cols)
  local w = math.min(360, view.w - 16)
  local h = HEADER_H + ROW_H + ROW_GAP + rows * (ROW_H + ROW_GAP) + ROW_H + 2 * PAD
  self.box = { x = math.floor((view.w - w) / 2), y = math.max(4, math.floor((view.h - h) / 2)), w = w, h = h }
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
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Tips", b.x, b.y + 10, { size = "body", width = b.w, align = "center", color = theme.colors.text })
  self.buttons:draw()
end

return Tips
