-- Small shared drawing helpers for UI.

local theme = require("src.ui.theme")

local Draw = {}

function Draw.panel(x, y, w, h)
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(theme.colors.panelBorder)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
end

--- Dim everything beneath a modal.
function Draw.overlay(view)
  love.graphics.setColor(theme.colors.overlay)
  love.graphics.rectangle("fill", 0, 0, view.w, view.h)
end

--- "1h 05m" / "12m" style playtime.
function Draw.formatPlaytime(seconds)
  seconds = math.floor(seconds or 0)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  if hours > 0 then
    return string.format("%dh %02dm", hours, minutes)
  end
  return string.format("%dm", minutes)
end

return Draw
