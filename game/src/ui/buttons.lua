-- A group of tappable buttons for a scene.
-- Works the same with mouse and touch: press highlights, select (tap/click) activates.
-- Hover is cosmetic only (desktop), never required.

local theme = require("src.ui.theme")
local Text = require("src.ui.text")
local Assets = require("src.render.assets")

local Buttons = {}
Buttons.__index = Buttons

--- minSize: smallest allowed button edge in virtual pixels (tuning.input.minTouchTarget).
function Buttons.new(minSize)
  return setmetatable({ list = {}, minSize = minSize or 0, hovered = nil, pressed = nil }, Buttons)
end

local function key(b)
  return b and (b.x .. ":" .. b.y .. ":" .. b.w .. ":" .. b.h) or nil
end

--- Remove all buttons. Hover/press state carries over to a rebuilt button at the same spot,
--- so panels can relayout (e.g. to refresh prices) without breaking a click in progress.
function Buttons:clear()
  self.list = {}
  self.keepHovered, self.keepPressed = key(self.hovered), key(self.pressed)
  self.hovered, self.pressed = nil, nil
end

--- b: { x, y, w, h, label, onPress, enabled = true, style = "normal"|"danger"|"accent", size,
---      icon = spriteId, selected = bool }
function Buttons:add(b)
  b.w = math.max(b.w, self.minSize)
  b.h = math.max(b.h, self.minSize)
  if b.enabled == nil then
    b.enabled = true
  end
  self.list[#self.list + 1] = b
  local k = key(b)
  if k == self.keepHovered then
    self.hovered = b
  end
  if k == self.keepPressed and b.enabled then
    self.pressed = b
  end
  return b
end

function Buttons:hit(x, y)
  for i = #self.list, 1, -1 do
    local b = self.list[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
  return nil
end

--- Feed an input action. Returns true if a button consumed it.
function Buttons:action(name, data)
  if name == "hover" then
    self.hovered = self:hit(data.x, data.y)
    return false
  elseif name == "press" then
    local b = self:hit(data.x, data.y)
    self.pressed = b and b.enabled and b or nil
    return b ~= nil
  elseif name == "release" then
    self.pressed = nil
    return false
  elseif name == "select" then
    local b = self:hit(data.x, data.y)
    if b then
      if b.enabled and b.onPress then
        b.onPress(b)
      end
      return true
    end
  end
  return false
end

function Buttons:draw()
  local colors = theme.colors
  for _, b in ipairs(self.list) do
    local fill = colors.button
    if not b.enabled then
      fill = colors.buttonDisabled
    elseif self.pressed == b or b.selected then
      fill = colors.buttonPressed
    elseif self.hovered == b then
      fill = colors.buttonHover
    end
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 3, 3)
    local border = colors.panelBorder
    if b.style == "danger" then
      border = colors.danger
    elseif b.style == "accent" or b.selected then
      border = colors.accent
    end
    love.graphics.setColor(border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1, 3, 3)
    local tw, th = Text.measure(b.label, b.size or "body")
    local textX, textW = b.x, b.w
    if b.icon then
      local icon = Assets.sprite(b.icon)
      local total = icon.w + (b.label ~= "" and (3 + tw) or 0)
      local ix = math.floor(b.x + (b.w - total) / 2)
      love.graphics.setColor(1, 1, 1, b.enabled and 1 or 0.5)
      love.graphics.draw(icon.image, icon.quad, ix, math.floor(b.y + (b.h - icon.h) / 2))
      textX, textW = ix + icon.w + 3, tw + 1
    end
    Text.draw(b.label, textX, b.y + (b.h - th) / 2, {
      size = b.size or "body",
      width = textW,
      align = b.icon and "left" or "center",
      color = b.enabled and colors.text or colors.textDim,
    })
  end
end

return Buttons
