-- Fish guide (GDD §7.10): every species, what you've caught, and hints for the rest.
-- Backed by the save slot's meta, so it fills up across runs.

local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Guide = { name = "guide" }
Guide.__index = Guide

local ROW_H = 26

function Guide.new(world)
  return setmetatable({ world = world }, Guide)
end

function Guide:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Guide:resize(view)
  local count = #self.world.registry:all("fish")
  self.box = Panel.box(view, 420, 50 + count * ROW_H + 10)
  self.buttons:clear()
  Panel.closeButton(self.buttons, self.box, function()
    self.app:pop()
  end)
end

local function capitalize(s)
  return (s:gsub("^%l", string.upper))
end

local function hint(fish)
  local parts = {}
  if fish.seasons then
    local names = {}
    for _, s in ipairs(fish.seasons) do
      names[#names + 1] = capitalize(s)
    end
    parts[#parts + 1] = table.concat(names, "/")
  end
  if fish.hours then
    local spans = {}
    for _, h in ipairs(fish.hours) do
      spans[#spans + 1] = string.format("%02d-%02d", h[1], h[2])
    end
    parts[#parts + 1] = table.concat(spans, ", ")
  end
  if #parts == 0 then
    return "Any time"
  end
  return table.concat(parts, " · ")
end

function Guide:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

function Guide:draw()
  local b = self.box
  local guide = self.world.meta.fishGuide or {}
  local caught, total = 0, 0
  for _, fish in ipairs(self.world.registry:all("fish")) do
    total = total + 1
    if guide[fish.id] then
      caught = caught + 1
    end
  end
  Panel.frame(self.app.view, b, "Fish guide", string.format("%d of %d species caught", caught, total))
  for n, fish in ipairs(self.world.registry:all("fish")) do
    local y = b.y + 44 + (n - 1) * ROW_H
    local entry = guide[fish.id]
    Panel.icon(entry and ("icon_" .. fish.id) or "icon_unknown", b.x + 12, y + 2)
    Text.draw(entry and fish.name or "???", b.x + 30, y + 2, { size = "small" })
    Text.draw(capitalize(fish.rarity) .. " · " .. hint(fish), b.x + 30, y + 13, {
      size = "small",
      color = theme.colors.textDim,
    })
    if entry then
      Text.draw(string.format("x%d · best %d cm", entry.count, entry.best), b.x, y + 7, {
        size = "small",
        width = b.w - 12,
        align = "right",
        color = theme.colors.accent,
      })
    end
  end
  self.buttons:draw()
end

return Guide
