-- A group of tappable buttons for a scene.
-- Works the same with mouse and touch: press highlights, select (tap/click) activates.
-- Hover is cosmetic only (desktop), never required.

local theme = require("src.ui.theme")
local Text = require("src.ui.text")
local HoldRepeat = require("src.ui.hold_repeat")
local Assets = require("src.render.assets")
local Plate = require("src.ui.plate")

local Buttons = {}
Buttons.__index = Buttons

Buttons.PULSE_PERIOD = 2 -- seconds per breath of a `pulse` button's border (presentation only)

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
---      icon = spriteId, selected = bool, onRepeat = function(units) -> false to stop }
--- `onRepeat` makes a stepper: a tap still calls onPress, and holding the button calls onRepeat with
--- the units to move (see Buttons:update and src/ui/hold_repeat.lua); a hold that repeated does not
--- also fire onPress on release.
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
    self.swallow = false
    self.hold = self.pressed and self.pressed.onRepeat and { elapsed = 0, fired = false } or nil
    return b ~= nil
  elseif name == "release" then
    self.pressed = nil
    self.swallow = self.hold ~= nil and self.hold.fired -- the repeats already did the work
    self.hold = nil
    return false
  elseif name == "select" then
    local b = self:hit(data.x, data.y)
    if b then
      if self.swallow then
        self.swallow = false
        return true
      end
      if b.enabled and b.onPress then
        if Buttons.onActivate then
          Buttons.onActivate(b) -- the audio service's tap sound (D100); nil in tests
        end
        b.onPress(b)
      end
      return true
    end
  end
  return false
end

--- Drive hold-to-repeat with real (UI clock) seconds: scenes with steppers call this every frame
--- with their `tuning.ui.holdRepeat`. Does nothing unless a button with `onRepeat` is held.
function Buttons:update(dt, cfg)
  local hold = self.hold
  if not hold then
    return
  end
  local b = self.pressed
  if not b or not b.onRepeat then
    self.hold = nil -- the held button went away (the list scrolled or relaid out)
    return
  end
  if hold.stopped then
    return
  end
  local prev = hold.elapsed
  hold.elapsed = prev + dt
  local units = HoldRepeat.units(prev, hold.elapsed, cfg)
  if units > 0 then
    hold.fired = true
    if b.onRepeat(units) == false then
      hold.stopped = true -- e.g. the number hit its limit; the hold ends quietly
    end
  end
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
    local ink
    if b.style == "danger" then
      ink = colors.danger
    elseif b.style == "accent" or b.selected then
      ink = colors.accent
    end
    if b.pulse then
      -- A gentle, persistent attention pulse (never hover-only): the outline breathes toward amber.
      local wave = 0.5 + 0.5 * math.sin(love.timer.getTime() * 2 * math.pi / Buttons.PULSE_PERIOD)
      local dark, amber = colors.panelBorder, colors.accent
      ink = {
        dark[1] + (amber[1] - dark[1]) * wave,
        dark[2] + (amber[2] - dark[2]) * wave,
        dark[3] + (amber[3] - dark[3]) * wave,
      }
    end
    local pressed = self.pressed == b
    Plate.draw(b.x, b.y, b.w, b.h, {
      base = fill,
      kind = "button",
      ink = ink,
      lit = pressed and 0 or nil, -- a pressed button loses its sunlit edge, as if pushed in
      alpha = 1,
      weather = false,
    })
    if b.latched then
      -- A held-on tool (the Plan latch, D94): a second, inner amber ring so it reads apart from a plain selection.
      love.graphics.setColor(colors.accent)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", b.x + 3.5, b.y + 3.5, b.w - 7, b.h - 7)
    end
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
      color = (b.enabled and not b.dim) and colors.text or colors.textDim, -- dim: a muted label on a live button (a seen tip)
    })
  end
end

return Buttons
