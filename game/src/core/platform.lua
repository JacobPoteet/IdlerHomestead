-- Platform capability flags (GDD §10).
-- Features check capabilities, never OS names, so new platforms only need changes here.

local M = {}

local os = love.system.getOS()
local desktop = os == "Windows" or os == "OS X" or os == "Linux"

local capabilities = {
  -- Borderless always-on-top desktop companion window (Win32 FFI; GDD §9.3).
  widgetMode = os == "Windows",
  -- Show an in-game Quit button. Mobile OSes and browsers manage app lifetime themselves.
  quitButton = desktop,
  -- Touch is the primary input; UI should favour larger targets and long-press over right-click.
  touchPrimary = os == "Android" or os == "iOS",
  -- The window can be freely resized by the player.
  resizableWindow = desktop,
}

M.os = os

--- True if the platform supports a capability. Errors on unknown capability names.
function M.has(name)
  local value = capabilities[name]
  if value == nil then
    error("Unknown platform capability '" .. tostring(name) .. "'", 2)
  end
  return value
end

return M
