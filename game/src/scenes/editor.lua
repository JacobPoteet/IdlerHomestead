-- In-game editor (GDD D133): a developer panel docked at the right edge, over the live world, opened with
-- F8 while the F1 overlay is on. It is a stack of panels (tabs); the first is the shader editor
-- (src/ui/editor_panel_shaders.lua). Nothing it changes is saved: it edits the running tuning tables, and
-- F6 puts the files' values back. The world keeps drawing and updating under it, and presses outside the
-- panel go to the scene below, so the camera still pans and zooms while you tune.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Needs = require("src.sim.systems.needs")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Editor = { name = "editor" }
Editor.__index = Editor

--- The panels, in tab order: { id, title, module }.
Editor.PANELS = {
  { id = "shaders", title = "Shaders", module = "src.ui.editor_panel_shaders" },
  { id = "wind", title = "Wind", module = "src.ui.editor_panel_wind" },
}

local PANEL_W = 330 -- virtual pixels; the docked panel's width
local MARGIN = 8 -- virtual pixels round the panel
local PAD = 8 -- virtual pixels inside it
local TITLE_H = 30 -- virtual pixels: title and tab strip
local GAP = 4 -- virtual pixels between neighbouring buttons

Editor.PAD, Editor.GAP = PAD, GAP

function Editor.new()
  return setmetatable({ list = ScrollList.new(), active = 1, panels = {} }, Editor)
end

function Editor:enter()
  local minSize = self.app.ctx.tuning.input.minTouchTarget
  self.minSize = minSize
  self.buttons = Buttons.new(minSize)
  self.rowButtons = Buttons.new(minSize)
  self.list.onMove = function()
    self:layout()
  end
  self.toast = nil
  -- Testing the look at every hour of the day must not cost a night of cold: nothing hurts while this is open.
  local session = self.app.ctx.session
  if session then
    Needs.setInvincible(session.world, true)
  end
end

--- The active panel's instance (built on first use, so it can read the live tuning).
function Editor:panel()
  local entry = Editor.PANELS[self.active]
  if not self.panels[entry.id] then
    self.panels[entry.id] = require(entry.module).new(self)
  end
  return self.panels[entry.id]
end

--- Leaving puts back what compare mode had swapped out, so a closed editor never leaves old values live.
function Editor:exit()
  local session = self.app.ctx.session
  if session then
    Needs.setInvincible(session.world, false)
  end
  for _, instance in pairs(self.panels) do
    if instance.close then
      instance:close()
    end
  end
end

function Editor:resize()
  self:layout()
end

--- Show a short line at the bottom of the panel.
function Editor:say(text)
  self.toast = { text = text, left = 3 }
end

function Editor:update(dt)
  if self.toast then
    self.toast.left = self.toast.left - dt
    if self.toast.left <= 0 then
      self.toast = nil
    end
  end
  self.buttons:update(dt, self.app.ctx.tuning.ui.holdRepeat)
  self.rowButtons:update(dt, self.app.ctx.tuning.ui.holdRepeat)
end

function Editor:layout()
  local app = self.app
  local view = app.view
  local w = math.min(PANEL_W, view.w - 2 * MARGIN)
  self.box = { x = view.w - w - MARGIN, y = MARGIN, w = w, h = view.h - 2 * MARGIN }
  local b = self.box
  self.buttons:clear()
  self.rowButtons:clear()
  -- Tabs along the title strip, then Close.
  local x = b.x + b.w - PAD
  local closeW = 52
  x = x - closeW
  self.buttons:add({
    x = x,
    y = b.y + 4,
    w = closeW,
    h = 22,
    label = "Close",
    onPress = function()
      self.app:pop()
    end,
  })
  local tabX = b.x + 72
  for i, entry in ipairs(Editor.PANELS) do
    self.buttons:add({
      x = tabX,
      y = b.y + 4,
      w = 72,
      h = 22,
      label = entry.title,
      selected = i == self.active,
      onPress = function()
        self.active = i
        self.list.offset = 0
        self:layout()
      end,
    })
    tabX = tabX + 72 + GAP
  end
  self:panel():layout({ x = b.x + PAD, y = b.y + TITLE_H, w = b.w - 2 * PAD, h = b.h - TITLE_H - PAD })
end

--- Is the point inside the docked panel?
function Editor:contains(x, y)
  local b = self.box
  return x ~= nil and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h
end

--- The scene under the editor, which gets every press outside the panel.
function Editor:below()
  local stack = self.app.stack
  for i = #stack, 1, -1 do
    if stack[i] == self then
      return stack[i - 1]
    end
  end
end

function Editor:forward(name, data)
  local scene = self:below()
  if scene and scene.action then
    return scene:action(name, data)
  end
  return false
end

function Editor:action(name, data)
  -- A press decides who owns the gesture until its release: the panel, or the world below.
  if name == "press" then
    self.owner = self:contains(data.x, data.y) and "panel" or "world"
  end
  local owner = self.owner
  if name == "hover" or name == "select" or name == "zoom" then
    owner = self:contains(data.x, data.y) and "panel" or "world"
  elseif name == "cancel" then
    self.app:pop()
    return true
  elseif (name == "pan" and data.keys) or not (name == "press" or name == "release" or name == "pan") then
    owner = "world" -- the keys and every other action (arrows, tool keys) still drive the camera
  end
  if owner == "world" then
    local handled = self:forward(name, data)
    if name == "release" then
      self.owner = nil
    end
    return handled
  end
  if name == "release" then
    self.owner = nil
  end
  if name == "press" or name == "release" or name == "pan" or name == "zoom" then
    if self.list:action(name, data, self.app.ctx.tuning.ui) then
      self:layout()
    end
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    if self.list:contains(data.x, data.y) then
      self.rowButtons:action(name, data)
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  end
  return true
end

function Editor:draw()
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Editor", b.x + PAD, b.y + 4, { size = "body", color = theme.colors.accent })
  Text.draw("invincible", b.x + PAD, b.y + 17, { size = "small", color = theme.colors.textDim })
  self:panel():draw()
  self.buttons:draw()
  if self.toast then
    Text.draw(self.toast.text, b.x + PAD, b.y + b.h - 12, { size = "small", color = theme.colors.accent })
  end
end

return Editor
