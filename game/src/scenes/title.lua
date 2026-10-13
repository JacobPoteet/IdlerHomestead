-- Title screen.

local Buttons = require("src.ui.buttons")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")
local Version = require("src.core.version")

local Title = { name = "title", opaque = true }
Title.__index = Title

function Title.new()
  return setmetatable({}, Title)
end

function Title:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Title:resize(view)
  local ctx = self.app.ctx
  self.buttons:clear()
  local w, h = 140, 28
  local x, y = (view.w - w) / 2, view.h * 0.55
  self.buttons:add({
    x = x,
    y = y,
    w = w,
    h = h,
    label = "Play",
    style = "accent",
    onPress = function()
      self.app:switch(require("src.scenes.slots").new())
    end,
  })
  if ctx.platform.has("quitButton") then
    self.buttons:add({
      x = x,
      y = y + h + 8,
      w = w,
      h = h,
      label = "Quit",
      onPress = function()
        love.event.quit()
      end,
    })
  end
end

function Title:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" and self.app.ctx.platform.has("quitButton") then
    love.event.quit()
    return true
  end
  return false
end

function Title:draw()
  local view = self.app.view
  Text.draw("Idler Homestead", 0, view.h * 0.24, { size = "title", width = view.w, align = "center" })
  Text.draw("an off-grid idle homestead", 0, view.h * 0.24 + 36, {
    size = "body",
    width = view.w,
    align = "center",
    color = theme.colors.textDim,
  })
  self.buttons:draw()
  local vt = self.app.ctx.tuning.ui.version
  Text.draw(Version.get().label, vt.margin, view.h - 14, {
    size = vt.size,
    width = view.w - vt.margin,
    align = "left",
    color = theme.colors[vt.color],
  })
  Text.draw("prototype", 0, view.h - 14, {
    size = "small",
    width = view.w - 6,
    align = "right",
    color = theme.colors.textDim,
  })
end

return Title
