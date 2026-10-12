-- In-game menu. The homestead keeps running underneath: time passes while the game is open.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")

local Menu = { name = "menu" }
Menu.__index = Menu

--- onExit: called after the menu closes when the player chooses to leave the homestead.
function Menu.new(onExit)
  return setmetatable({ onExit = onExit }, Menu)
end

function Menu:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Menu:resize(view)
  local w, h = 160, 112
  self.box = { x = (view.w - w) / 2, y = (view.h - h) / 2, w = w, h = h }
  local b = self.box
  self.buttons:clear()
  self.buttons:add({
    x = b.x + 12,
    y = b.y + 32,
    w = b.w - 24,
    h = 28,
    label = "Resume",
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
  self.buttons:add({
    x = b.x + 12,
    y = b.y + 68,
    w = b.w - 24,
    h = 28,
    label = "Save & exit",
    onPress = function()
      self.app:pop()
      self.onExit()
    end,
  })
end

function Menu:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

function Menu:draw()
  Draw.overlay(self.app.view)
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Menu", b.x, b.y + 10, { size = "body", width = b.w, align = "center" })
  self.buttons:draw()
end

return Menu
