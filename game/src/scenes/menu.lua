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
  local cfg = self.app.ctx.tuning.ui.menu
  local wardrobe = self.app.ctx.tuning.ui.wardrobe
  local rows = {
    {
      label = "Resume",
      style = "accent",
      onPress = function()
        self.app:pop()
      end,
    },
    {
      label = wardrobe.menuRow,
      onPress = function()
        self.app:pop() -- the Wardrobe comes up over the world, and Close returns there
        require("src.scenes.wardrobe").open(self.app)
      end,
    },
    {
      label = "Tips",
      onPress = function()
        self.app:push(require("src.scenes.tips").new(self.app.ctx.session.world))
      end,
    },
    {
      label = "Settings",
      onPress = function()
        self.app:push(require("src.scenes.settings").new())
      end,
    },
    {
      label = "Save & exit",
      onPress = function()
        self.app:pop()
        self.onExit()
      end,
    },
  }
  local w = cfg.width
  local h = cfg.firstRowY + #rows * cfg.rowH + (#rows - 1) * cfg.rowGap + cfg.bottomPad
  self.box = { x = (view.w - w) / 2, y = (view.h - h) / 2, w = w, h = h }
  local b = self.box
  self.buttons:clear()
  for n, row in ipairs(rows) do
    row.x = b.x + cfg.pad
    row.y = b.y + cfg.firstRowY + (n - 1) * (cfg.rowH + cfg.rowGap)
    row.w = b.w - 2 * cfg.pad
    row.h = cfg.rowH
    self.buttons:add(row)
  end
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
  Text.draw("Menu", b.x, b.y + self.app.ctx.tuning.ui.menu.titleY, { size = "body", width = b.w, align = "center" })
  self.buttons:draw()
end

return Menu
