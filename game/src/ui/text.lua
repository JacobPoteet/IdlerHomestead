-- Text in virtual (UI) coordinates, in the game's pixel font (D142).
-- The font is drawn at a whole number of UI pixels per font pixel and snapped to the UI pixel grid, so
-- every glyph pixel lands on the same grid as the plates and icons under the app's integer scale. A warm
-- dark shadow sits one UI pixel down and right (the world's top-left sun).

local theme = require("src.ui.theme")
local PixelFont = require("src.ui.pixel_font")

local Text = {}

local LINE_SPACING = 2 -- font pixels between wrapped lines

--- Kept for callers that change the window scale: the pixel font needs no rebuild, so this is a no-op.
function Text.setScale() end

--- UI pixels per font pixel for a size (a theme.textScale key, or a number of UI pixels per font pixel).
function Text.scale(size)
  return theme.textScale[size or "body"] or (type(size) == "number" and size) or 1
end

--- The LÖVE font (the same pixel font at every size; draw it at Text.scale(size)).
function Text.font()
  return PixelFont.get()
end

local function lineHeight(font)
  return font:getHeight() + LINE_SPACING
end

--- Width and height of a string in UI pixels. The height is one line of glyphs (caps and descenders).
function Text.measure(str, size)
  local font, m = PixelFont.get(), Text.scale(size)
  return font:getWidth(str) * m, font:getHeight() * m
end

--- Height in UI pixels of a string wrapped to `width` UI pixels.
function Text.wrappedHeight(str, size, width)
  local font, m = PixelFont.get(), Text.scale(size)
  local _, lines = font:getWrap(str, width / m)
  local n = math.max(1, #lines)
  return (n * lineHeight(font) - LINE_SPACING) * m
end

--- Draw text. opts: { size, color, align = "left"|"center"|"right", width, shadow = false }
--- With align/width, text wraps and aligns within [x, x + width].
function Text.draw(str, x, y, opts)
  opts = opts or {}
  local font, m = PixelFont.get(), Text.scale(opts.size)
  font:setLineHeight(lineHeight(font) / font:getHeight())
  love.graphics.setFont(font)
  local color = opts.color or theme.colors.text
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  local function put(px, py)
    if opts.width then
      love.graphics.printf(str, px, py, opts.width / m, opts.align or "left", 0, m, m)
    else
      love.graphics.print(str, px, py, 0, m, m)
    end
  end
  if opts.shadow ~= false then
    local s = theme.colors.textShadow
    love.graphics.setColor(s[1], s[2], s[3], s[4] * (color[4] or 1))
    put(x + 1, y + 1)
  end
  love.graphics.setColor(color)
  put(x, y)
end

return Text
