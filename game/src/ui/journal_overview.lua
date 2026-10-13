-- Journal overview drawing (GDD D81, #194): the chip row (jumps and filter) and the scrolling grid of
-- chapter tiles under area headings. Reads the nav state and the stats; changes nothing.
-- INTENTIONALLY MINIMAL (a temporary design): all sizes, colors and labels come from tuning.ui.journal.

local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Overview = {}

local function box(r, fill, border, alpha, radius)
  love.graphics.setColor(fill)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, radius, radius)
  love.graphics.setColor(border[1], border[2], border[3], alpha or 1)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, radius, radius)
end

--- The chip row. A filter chip is lit while it is the active filter.
function Overview.drawChips(nav, spec)
  local colors = theme.colors
  local _, lineH = Text.measure("A", "small")
  for _, chip in ipairs(nav.chips) do
    local on = chip.kind == nav.filter
    box(chip, on and spec.colors.chipOn or colors.button, on and colors.accent or colors.panelBorder, 1, spec.radius)
    Text.draw(chip.label, chip.x, chip.y + (chip.h - lineH) / 2, { size = "small", width = chip.w, align = "center", color = on and colors.text or colors.textDim })
  end
end

local function countsLine(spec, s)
  local parts = {}
  if s.ideas > 0 then
    parts[#parts + 1] = string.format(spec.labels.ideas, s.ideas)
  end
  if s.locked > 0 then
    parts[#parts + 1] = string.format(spec.labels.locked, s.locked)
  end
  return table.concat(parts, spec.labels.separator)
end

local function drawTile(tile, chapter, s, spec)
  local colors = theme.colors
  local pad = spec.tilePad
  local act = s.toStudy > 0
  box(tile, spec.colors.tile, act and colors.accent or colors.panelBorder, act and 1 or 0.6, spec.radius)
  local _, lineH = Text.measure("A", "small")
  local y = tile.y + pad
  Text.draw(chapter.name, tile.x + pad, y, { size = "small", color = colors.accent, width = tile.w - 2 * pad })
  y = y + lineH
  Text.draw(string.format(spec.labels.known, s.known, s.total), tile.x + pad, y, { size = "small", color = colors.text, width = tile.w - 2 * pad })
  y = y + lineH
  Text.draw(countsLine(spec, s), tile.x + pad, y, { size = "small", color = colors.textDim, width = tile.w - 2 * pad })
  if act then
    Text.draw(string.format(spec.labels.toStudy, s.toStudy), tile.x + pad, tile.y + tile.h - pad - lineH, { size = "small", color = colors.accent, width = tile.w - 2 * pad })
  end
end

--- The headings and tiles, clipped to the body and shifted by the scroll offset. `scale` is the view's
--- screen scale (the scissor works in screen pixels).
function Overview.draw(nav, data, spec, scale)
  local colors, b = theme.colors, nav.body
  love.graphics.setScissor(math.floor(b.x * scale), math.floor(b.y * scale), math.ceil(b.w * scale), math.ceil(b.h * scale))
  love.graphics.push()
  love.graphics.translate(b.x, b.y - nav.offset)
  if #nav.grid.items == 0 then
    Text.draw(spec.labels.empty, 0, 8 + nav.offset, { size = "small", color = colors.textDim, width = b.w, align = "center" })
  end
  for _, item in ipairs(nav.grid.items) do
    if item.y + item.h >= nav.offset and item.y <= nav.offset + b.h then
      if item.kind == "heading" then
        Text.draw(item.name, item.x, item.y + 3, { size = "small", color = colors.textDim, width = item.w })
        love.graphics.setColor(colors.panelBorder[1], colors.panelBorder[2], colors.panelBorder[3], 0.5)
        love.graphics.rectangle("fill", item.x, item.y + item.h - 3, item.w, 1)
      else
        drawTile(item, data.chapters[item.index], data.stats[item.index], spec)
      end
    end
  end
  love.graphics.pop()
  -- Scroll thumb, only where the grid overflows.
  local height = nav.grid.height
  if height > b.h then
    local thumbH = math.max(spec.thumbMin, b.h * b.h / height)
    local at = nav.offset / (height - b.h) * (b.h - thumbH)
    love.graphics.setColor(1, 1, 1, spec.thumbAlpha)
    love.graphics.rectangle("fill", b.x + b.w - spec.thumbWidth, b.y + at, spec.thumbWidth, thumbH)
  end
  love.graphics.setScissor()
end

return Overview
