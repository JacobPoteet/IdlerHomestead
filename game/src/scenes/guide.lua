-- Fish guide (GDD §7.10): every species, what you've caught, and hints for the rest.
-- Backed by the save slot's meta, so it fills up across runs.

local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
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
  self.list = ScrollList.new()
end

function Guide:resize(view)
  local count = #self.world.registry:all("fish")
  self.box = Panel.box(view, 420, 50 + count * ROW_H + 10)
  self.buttons:clear()
  Panel.closeButton(self.buttons, self.box, function()
    self.app:pop()
  end)
  -- The species list scrolls (D87, #8) when the panel is shorter than the guide.
  local b = self.box
  self.list:fit({ x = b.x, y = b.y + 44, w = b.w, h = b.h - 44 - 6 }, count * ROW_H, self.app.ctx.tuning.ui.scrollHintHeight, ROW_H)
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
  if name == "press" or name == "release" then -- a drag that ends moving lets the list coast (D94)
    self.list:action(name, data)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    return true
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
  self.list:begin(self.app.view.scale)
  for n, fish in ipairs(self.world.registry:all("fish")) do
    local y = self.list:origin() + (n - 1) * ROW_H
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
        width = b.w - 12 - (self.list.overflow and self.app.ctx.tuning.ui.scrollBarWidth + 4 or 0),
        align = "right",
        color = theme.colors.accent,
      })
    end
  end
  self.list:finish()
  self.list:drawCue(self.app.ctx.tuning.ui)
  self.buttons:draw()
end

return Guide
