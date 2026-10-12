-- A find (GDD §8.4, D53): a small modal offering three things, pick one; the others are gone.
-- Time stands still while it is open, and it cannot be dismissed without choosing, so a pending
-- offer (which is saved with the run) always comes back here.
-- new(world, onPicked(find def))

local Finds = require("src.sim.systems.finds")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local FindsScene = { name = "finds" }
FindsScene.__index = FindsScene

local CARD_H = 44 -- one choice
local CARD_GAP = 6
local ICON_SCALE = 2

function FindsScene.new(world, onPicked)
  return setmetatable({ world = world, onPicked = onPicked, selected = nil }, FindsScene)
end

function FindsScene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  local session = self.app.ctx.session
  if session then
    self.restoreSpeed = session:speed()
    session:setSpeed(0)
  end
  self.defs = {}
  for _, id in ipairs(Finds.pending(self.world).choices) do
    self.defs[#self.defs + 1] = self.world.registry:get("finds", id)
  end
end

function FindsScene:exit()
  local session = self.app.ctx.session
  if session and self.restoreSpeed then
    session:setSpeed(self.restoreSpeed)
  end
end

function FindsScene:take()
  local def = self.selected and self.defs[self.selected]
  if def and Finds.choose(self.world, def.id) then
    self.app:pop()
    if self.onPicked then
      self.onPicked(def)
    end
  end
end

function FindsScene:select(n)
  if self.defs[n] then
    self.selected = n
    self.takeButton.enabled = true
  end
end

function FindsScene:resize(view)
  local h = 62 + #self.defs * (CARD_H + CARD_GAP) + 40
  self.box = Panel.box(view, 320, h)
  local b = self.box
  self.buttons:clear()
  self.cards = {}
  for n = 1, #self.defs do
    local y = b.y + 54 + (n - 1) * (CARD_H + CARD_GAP)
    self.cards[n] = self.buttons:add({
      x = b.x + 10,
      y = y,
      w = b.w - 20,
      h = CARD_H,
      label = "",
      selected = self.selected == n,
      onPress = function()
        self:select(n)
        for i, card in ipairs(self.cards) do
          card.selected = i == n
        end
      end,
    })
  end
  self.takeButton = self.buttons:add({
    x = b.x + b.w - 100,
    y = b.y + b.h - 34,
    w = 90,
    h = 26,
    label = "Take it",
    style = "accent",
    enabled = self.selected ~= nil,
    onPress = function()
      self:take()
    end,
  })
end

function FindsScene:keypressed(key)
  local n = tonumber(key)
  if n and self.defs[n] then
    self:select(n)
    for i, card in ipairs(self.cards) do
      card.selected = i == n
    end
  elseif (key == "return" or key == "kpenter") and self.selected then
    self:take()
  end
end

function FindsScene:action(name, data)
  self.buttons:action(name, data)
  return true -- modal: swallow everything (an offer must be answered)
end

function FindsScene:draw()
  Panel.frame(self.app.view, self.box, "You found something", "Take one. The others are gone.")
  self.buttons:draw()
  for n, def in ipairs(self.defs) do
    local card = self.cards[n]
    Panel.icon(def.icon, card.x + 8, card.y + (card.h - 12 * ICON_SCALE) / 2, 1, ICON_SCALE)
    local tx = card.x + 12 + 12 * ICON_SCALE + 6
    Text.draw(def.name, tx, card.y + 8, { size = "body" })
    Text.draw(def.line, tx, card.y + 23, {
      size = "small",
      width = card.w - (tx - card.x) - 6,
      color = theme.colors.textDim,
    })
  end
end

return FindsScene
