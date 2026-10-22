-- Starting loadouts (D201, #386, docs/PLAN_DEPTH.md 12.3): the kit the next run begins with, opened from the Plots scene's
-- Starting kit button. The first row is the standard start (the default, nothing taken away); each loadout below brings a
-- bundle of gear for a small cost and unlocks when the Journal has taught what it needs (a locked row says which node).
-- Tapping a row chooses it; Done goes back. Never required: skipping this is the standard start.

local Run = require("src.meta.run")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Plate = require("src.ui.plate")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Loadouts = { name = "loadouts" }
Loadouts.__index = Loadouts

local TOP = 52 -- virtual pixels from the panel top to the first row
local ROW_GAP = 5
local PAD = 8 -- inside a row

--- opts: { data = slot data, slot, metaWorld, onChange = function() }.
function Loadouts.new(opts)
  return setmetatable({ opts = opts }, Loadouts)
end

function Loadouts.open(app, opts)
  app:push(Loadouts.new(opts))
end

function Loadouts:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Loadouts:resize(view)
  self.box = Panel.box(view, 460, view.h - 16)
  self:layout()
end

function Loadouts:choose(id)
  local ok = Run.chooseLoadout(self.opts.data, self.opts.metaWorld, id)
  if ok then
    self.app.ctx.store:write(self.opts.slot, self.opts.data) -- the choice survives a quit
    if self.opts.onChange then
      self.opts.onChange()
    end
  end
  self:layout()
end

function Loadouts:layout()
  local b = self.box
  local words = self.app.ctx.tuning.plots.words
  local current = self.opts.data.meta.recovery.loadout
  self.buttons:clear()
  self.rows = {}
  local textW = b.w - 24 - PAD * 2
  local y = b.y + TOP
  local entries = { { id = false, name = words.kitNone, line = words.kitNoneLine, unlocked = true } }
  for _, item in ipairs(Run.loadouts(self.opts.metaWorld)) do
    local def = item.def
    local second
    if item.unlocked then
      second = string.format(words.kitCost, def.penaltyLine)
    else
      second = string.format(words.kitLocked, item.unlockName)
    end
    entries[#entries + 1] = { id = def.id, name = def.name, line = def.line, second = second, unlocked = item.unlocked }
  end
  for n, e in ipairs(entries) do
    local h = PAD * 2 + 12 + Text.wrappedHeight(e.line, "small", textW)
    if e.second then
      h = h + Text.wrappedHeight(e.second, "small", textW)
    end
    local row = {
      e = e,
      selected = (e.id == false and current == nil) or e.id == current,
      x = b.x + 12,
      y = y,
      w = b.w - 24,
      h = h,
    }
    self.rows[n] = row
    self.buttons:add({
      x = row.x,
      y = row.y,
      w = row.w,
      h = row.h,
      label = e.name,
      enabled = e.unlocked,
      onPress = function()
        self:choose(e.id or nil)
      end,
      draw = function(btn)
        self:drawRow(row, btn)
      end,
    })
    y = y + h + ROW_GAP
  end
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.buttons:add({
    x = b.x + b.w - 92,
    y = b.y + b.h - 36,
    w = 80,
    h = 26,
    label = words.done,
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
end

function Loadouts:drawRow(row, btn)
  local colors = theme.colors
  local words = self.app.ctx.tuning.plots.words
  local e = row.e
  local fill = colors.button
  if not e.unlocked then
    fill = colors.buttonDisabled
  elseif self.buttons.pressed == btn or row.selected then
    fill = colors.buttonPressed
  elseif self.buttons.hovered == btn then
    fill = colors.buttonHover
  end
  Plate.draw(row.x, row.y, row.w, row.h, {
    base = fill,
    kind = "button",
    ink = row.selected and colors.accent or nil,
    alpha = 1,
    weather = false,
  })
  local tx, textW = row.x + PAD, row.w - PAD * 2
  local ink = e.unlocked and colors.text or colors.textDim
  local y = row.y + PAD
  Text.draw(e.name, tx, y, { size = "small", color = ink })
  if row.selected then
    Text.draw(words.kitChosen, tx, y, { size = "small", width = textW, align = "right", color = colors.accent })
  end
  y = y + 12
  Text.draw(e.line, tx, y, { size = "small", width = textW, color = ink })
  if e.second then
    y = y + Text.wrappedHeight(e.line, "small", textW)
    Text.draw(
      e.second,
      tx,
      y,
      { size = "small", width = textW, color = e.unlocked and colors.accent or colors.textDim }
    )
  end
end

function Loadouts:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true -- modal: swallow everything
end

function Loadouts:draw()
  local b, words = self.box, self.app.ctx.tuning.plots.words
  Panel.frame(self.app.view, b, words.kitTitle)
  Text.draw(words.kitIntro, b.x + 12, b.y + 22, { size = "small", width = b.w - 24 - 58, color = theme.colors.textDim })
  self.buttons:draw()
end

return Loadouts
