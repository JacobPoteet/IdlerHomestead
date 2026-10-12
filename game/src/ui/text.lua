-- Crisp text in virtual coordinates.
-- Scenes draw under the app's integer scale; drawing a small font scaled up would blur, so fonts
-- are created at (virtual size x window scale) and drawn at 1/scale to land on real pixels.

local theme = require("src.ui.theme")

local Text = {}

local scale = 1
local cache = {}

--- Called by the game whenever the window scale changes.
function Text.setScale(s)
  if s ~= scale then
    scale = s
    cache = {}
  end
end

--- Font for a virtual size (number or theme.textSize key).
function Text.font(size)
  size = theme.textSize[size] or size
  local font = cache[size]
  if not font then
    font = love.graphics.newFont(math.max(1, math.floor(size * scale + 0.5)))
    cache[size] = font
  end
  return font
end

--- Width and height of a string in virtual pixels.
function Text.measure(str, size)
  local font = Text.font(size)
  return font:getWidth(str) / scale, font:getHeight() / scale
end

--- Draw text. opts: { size, color, align = "left"|"center"|"right", width }
--- With align/width, text wraps and aligns within [x, x + width].
function Text.draw(str, x, y, opts)
  opts = opts or {}
  local font = Text.font(opts.size or "body")
  love.graphics.setFont(font)
  love.graphics.setColor(opts.color or theme.colors.text)
  local inv = 1 / scale
  -- Snap to whole screen pixels so glyphs stay sharp.
  local sx, sy = math.floor(x * scale + 0.5) * inv, math.floor(y * scale + 0.5) * inv
  if opts.width then
    love.graphics.printf(str, sx, sy, opts.width * scale, opts.align or "left", 0, inv, inv)
  else
    love.graphics.print(str, sx, sy, 0, inv, inv)
  end
end

return Text
