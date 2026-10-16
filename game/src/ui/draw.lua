-- Small shared drawing helpers for UI.

local theme = require("src.ui.theme")
local Plate = require("src.ui.plate")

local Draw = {}

--- A modal panel: a frosted plate lit like the world (src/ui/plate.lua), more solid than a HUD plate so
--- its text reads over the land. opts as Plate.draw.
function Draw.panel(x, y, w, h, opts)
  opts = opts or {}
  opts.kind = opts.kind or "panel"
  Plate.draw(x, y, w, h, opts)
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
