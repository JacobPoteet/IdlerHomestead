-- The store's item card (#266, D107): a small modal over the Catalog or the town shop that says what an
-- item is before it is bought. Opened by a tap or a long-press on the row (never hover), closed by Close,
-- a tap outside it, or Escape; its button buys the item, so reading and buying stay two deliberate steps.
-- The text comes from src/ui/item_text.lua (content `desc`/`line` plus facts read from the sim).

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local ItemText = require("src.ui.item_text")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local ItemCard = {}
ItemCard.__index = ItemCard

local PAD = 10 -- view px inside the card
local GAP = 4 -- view px between rows of text
local BUTTON_H = 26 -- view px; the card's buttons

function ItemCard.new(minTouch)
  return setmetatable({ buttons = Buttons.new(minTouch), id = nil }, ItemCard)
end

function ItemCard:isOpen()
  return self.id ~= nil
end

--- Show item `id`. pickup: bought in town. onBuy(id) runs the purchase (it should return true when it went through).
function ItemCard:open(world, id, pickup, onBuy)
  self.world, self.id, self.pickup, self.onBuy = world, id, pickup, onBuy
end

function ItemCard:close()
  self.id = nil
  self.buttons:clear()
end

--- (Re)build the text, box and buttons for the current view and state. Cheap; call after money changes.
function ItemCard:layout(view)
  if not self.id then
    return
  end
  local world = self.world
  local t = world.tuning.ui.itemCard
  local info = ItemText.build(world, self.id, self.pickup)
  self.info = info
  local w = math.min(t.width, view.w - 16)
  local inner = w - 2 * PAD
  local textW = inner - t.labelWidth
  local h = PAD + Text.wrappedHeight(info.title, "body", inner) + GAP
  h = h + Text.wrappedHeight(info.price, "small", inner) + GAP * 2
  h = h + Text.wrappedHeight(info.desc, "small", inner) + GAP * 2
  for _, line in ipairs(info.lines) do
    line.h = Text.wrappedHeight(line.text, "small", textW)
    h = h + line.h + GAP
  end
  h = math.min(h + GAP + BUTTON_H + PAD, view.h - 16)
  self.box = {
    x = math.floor((view.w - w) / 2),
    y = math.floor((view.h - h) / 2),
    w = w,
    h = h,
  }
  local b = self.box
  self.buttons:clear()
  local half = math.floor((inner - GAP) / 2)
  local id, pickup = self.id, self.pickup
  self.buttons:add({
    x = b.x + PAD,
    y = b.y + b.h - PAD - BUTTON_H,
    w = half,
    h = BUTTON_H,
    label = info.owned and t.owned
      or (info.cheat and t.cheatGet)
      or string.format(pickup and t.buy or t.order, info.cost),
    enabled = info.reason == nil,
    style = info.reason == nil and "accent" or nil,
    onPress = function()
      if self.onBuy and self.onBuy(id) then
        self:close()
      else
        self:layout(view)
      end
    end,
  })
  self.buttons:add({
    x = b.x + PAD + half + GAP,
    y = b.y + b.h - PAD - BUTTON_H,
    w = half,
    h = BUTTON_H,
    label = t.close,
    onPress = function()
      self:close()
    end,
  })
end

--- Feed an input action. Returns true when the card is open (it is modal and swallows everything).
function ItemCard:action(name, data)
  if not self.id then
    return false
  end
  if name == "cancel" then
    self:close()
    return true
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "select" and data and self.box then
    local b = self.box
    if data.x < b.x or data.x >= b.x + b.w or data.y < b.y or data.y >= b.y + b.h then
      self:close() -- a tap outside puts the card away
    end
  end
  return true
end

local TONES = { text = "text", dim = "textDim", warn = "danger" }

function ItemCard:draw(view)
  if not self.id or not self.box or not self.info then
    return
  end
  local b, info = self.box, self.info
  local t = self.world.tuning.ui.itemCard
  local inner = b.w - 2 * PAD
  Draw.overlay(view)
  Draw.panel(b.x, b.y, b.w, b.h)
  local y = b.y + PAD
  Text.draw(info.title, b.x + PAD, y, { size = "body", width = inner })
  y = y + Text.wrappedHeight(info.title, "body", inner) + GAP
  Text.draw(info.price, b.x + PAD, y, { size = "small", width = inner, color = theme.colors.accent })
  y = y + Text.wrappedHeight(info.price, "small", inner) + GAP * 2
  Text.draw(info.desc, b.x + PAD, y, { size = "small", width = inner })
  y = y + Text.wrappedHeight(info.desc, "small", inner) + GAP * 2
  local previous
  for _, line in ipairs(info.lines) do
    if line.label ~= previous then -- a label heads its run of lines once
      Text.draw(line.label, b.x + PAD, y, { size = "small", color = theme.colors.textDim })
    end
    previous = line.label
    Text.draw(line.text, b.x + PAD + t.labelWidth, y, {
      size = "small",
      width = inner - t.labelWidth,
      color = theme.colors[TONES[line.tone]],
    })
    y = y + line.h + GAP
  end
  self.buttons:draw()
end

return ItemCard
