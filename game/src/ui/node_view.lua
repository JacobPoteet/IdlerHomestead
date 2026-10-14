-- Shared drawing for Field Journal nodes and note stamps (GDD §8.3). Used by the knowledge map and
-- by the recovery scene so a note or an idea looks the same everywhere.

local Journal = require("src.sim.systems.journal")
local Panel = require("src.ui.panel")
local theme = require("src.ui.theme")

local NodeView = {}

local PAPER = { 0.27, 0.25, 0.17, 1 } -- a written stamp's paper
local BLANK = { 0.15, 0.17, 0.15, 1 } -- a stamp not written yet

--- A note stamp: a small paper tile with the note's icon, or a blank tile if it isn't written.
--- size: tile edge in virtual pixels (the 12px icon is centred in it).
function NodeView.stamp(registry, noteId, x, y, size, written, emphasis)
  local colors = theme.colors
  love.graphics.setColor(written and PAPER or BLANK)
  love.graphics.rectangle("fill", x, y, size, size, 3, 3)
  love.graphics.setColor(emphasis and colors.text or written and colors.accent or colors.panelBorder)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, size - 1, size - 1, 3, 3)
  local inset = (size - 12) / 2
  Panel.icon(written and registry:get("notes", noteId).icon or "icon_note_blank", x + inset, y + inset)
end

--- A left-to-right row of the stamps an item needs: written ones filled, the rest blank.
--- Returns the x just past the last stamp.
function NodeView.needStamps(world, item, x, y, size, gap)
  for _, noteId in ipairs(item.needs or {}) do
    NodeView.stamp(world.registry, noteId, x, y, size, Journal.hasNote(world, noteId))
    x = x + size + gap
  end
  return x
end

--- A dashed rectangle outline.
function NodeView.dashedRect(x, y, w, h, dash, gap)
  love.graphics.setLineWidth(1)
  local function run(x1, y1, x2, y2)
    local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local dx, dy = (x2 - x1) / length, (y2 - y1) / length
    local at = 0
    while at < length do
      local to = math.min(at + dash, length)
      love.graphics.line(x1 + dx * at, y1 + dy * at, x1 + dx * to, y1 + dy * to)
      at = to + gap
    end
  end
  run(x, y + 0.5, x + w, y + 0.5)
  run(x + w - 0.5, y, x + w - 0.5, y + h)
  run(x + w, y + h - 0.5, x, y + h - 0.5)
  run(x + 0.5, y + h, x + 0.5, y)
end

return NodeView
