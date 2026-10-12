-- Routine panel: the idle homesteader's priority list (GDD §7.4, priorities v1).
-- Reorder categories and switch them on or off. Changes apply immediately.

local Tasks = require("src.sim.systems.tasks")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Routine = { name = "routine" }
Routine.__index = Routine

local ROW_H = 30

function Routine.new(world)
  return setmetatable({ world = world }, Routine)
end

function Routine:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Routine:resize(view)
  local list = self.world.state.priorities
  local w = math.min(300, view.w - 24)
  local h = 56 + #list * ROW_H + 36
  self.box = { x = (view.w - w) / 2, y = math.max(8, (view.h - h) / 2), w = w, h = h }
  self:layout()
end

function Routine:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  self.rows = {}
  for i, entry in ipairs(world.state.priorities) do
    local y = b.y + 44 + (i - 1) * ROW_H
    self.rows[i] = { y = y, entry = entry }
    local right = b.x + b.w - 10
    local function add(label, onPress, opts)
      opts = opts or {}
      local w = opts.w or 26
      right = right - w
      self.buttons:add({
        x = right,
        y = y,
        w = w,
        h = 24,
        label = label,
        enabled = opts.enabled ~= false,
        selected = opts.selected,
        onPress = onPress,
      })
      right = right - 4
    end
    add(entry.enabled and "On" or "Off", function()
      Tasks.setPriorityEnabled(world, entry.category, not entry.enabled)
      self:layout()
    end, { w = 40, selected = entry.enabled })
    add("v", function()
      Tasks.movePriority(world, entry.category, 1)
      self:layout()
    end, { enabled = i < #world.state.priorities })
    add("^", function()
      Tasks.movePriority(world, entry.category, -1)
      self:layout()
    end, { enabled = i > 1 })
  end
  self.buttons:add({
    x = b.x + (b.w - 80) / 2,
    y = b.y + b.h - 32,
    w = 80,
    h = 24,
    label = "Done",
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
end

function Routine:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

function Routine:draw()
  Draw.overlay(self.app.view)
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Routine", b.x + 12, b.y + 10, { size = "body" })
  Text.draw("When you step away, work is done top to bottom.", b.x + 12, b.y + 26, {
    size = "small",
    color = theme.colors.textDim,
  })
  for i, row in ipairs(self.rows) do
    local def = self.world.registry:get("task_categories", row.entry.category)
    Text.draw(i .. ".  " .. def.name, b.x + 14, row.y + 7, {
      size = "body",
      color = row.entry.enabled and theme.colors.text or theme.colors.textDim,
    })
  end
  self.buttons:draw()
end

return Routine
