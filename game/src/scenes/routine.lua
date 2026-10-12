-- Routine panel: the idle homesteader's priority list (GDD §7.4, priorities v1 and thresholds, D66).
-- Reorder categories, switch them on or off, and give a category a condition ("If" button): the
-- routine skips it while the condition is not met. The "If" button picks a row; the strip under the
-- list edits that row's condition kind and value with big stepper buttons. Changes apply at once.

local Tasks = require("src.sim.systems.tasks")
local Rules = require("src.sim.routine_rules")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Routine = { name = "routine" }
Routine.__index = Routine

local ROW_H = 26
local HEADER_H = 40
local EDITOR_H = 56

function Routine.new(world)
  return setmetatable({ world = world }, Routine)
end

function Routine:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.selected = self.selected or self.world.state.priorities[1].category
end

function Routine:resize(view)
  local list = self.world.state.priorities
  local w = math.min(380, view.w - 24)
  local h = HEADER_H + #list * ROW_H + EDITOR_H + 44
  self.box = { x = (view.w - w) / 2, y = math.max(8, (view.h - h) / 2), w = w, h = h }
  self:layout()
end

function Routine:layout()
  local b, world = self.box, self.world
  self.buttons:clear()
  self.rows = {}
  for i, entry in ipairs(world.state.priorities) do
    local y = b.y + HEADER_H + (i - 1) * ROW_H
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
    add("If", function()
      self.selected = entry.category
      self:layout()
    end, { selected = self.selected == entry.category })
  end

  -- Editor strip for the selected category.
  local ey = b.y + HEADER_H + #world.state.priorities * ROW_H + 18
  self.editorY = ey - 14
  local cat = self.selected
  local cond = Tasks.condition(world, cat)
  self.buttons:add({
    x = b.x + 12,
    y = ey,
    w = 150,
    h = 28,
    label = Rules.kindName(world, cond),
    onPress = function()
      Tasks.cycleCondition(world, cat)
      self:layout()
    end,
  })
  local right = b.x + b.w - 12
  local function stepper(label, delta)
    right = right - 32
    self.buttons:add({
      x = right,
      y = ey,
      w = 32,
      h = 28,
      label = label,
      enabled = cond ~= nil,
      onPress = function()
        Tasks.stepCondition(world, cat, delta)
        self:layout()
      end,
    })
    right = right - 4
  end
  stepper("+", 1)
  self.valueX = right - 70
  right = right - 70
  stepper("-", -1)

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

--- The value text for the editor ("40 pieces", "Summer").
function Routine:valueText(cond)
  if cond == nil then
    return ""
  end
  local def = self.world.registry:get("routine_conditions", cond.kind)
  if def.measure == "seasonIndex" then
    local name = self.world.tuning.time.seasons[cond.value]
    return name:sub(1, 1):upper() .. name:sub(2)
  end
  return cond.value .. " " .. def.unit
end

function Routine:draw()
  Draw.overlay(self.app.view)
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Routine", b.x + 12, b.y + 8, { size = "body" })
  Text.draw("Done top to bottom while you are away.", b.x + 12, b.y + 24, {
    size = "small",
    color = theme.colors.textDim,
  })
  for i, row in ipairs(self.rows) do
    local cat = row.entry.category
    local def = self.world.registry:get("task_categories", cat)
    local met = Tasks.conditionMet(self.world, cat)
    local live = row.entry.enabled and met
    Text.draw(i .. ".  " .. def.name, b.x + 14, row.y + 6, {
      size = "body",
      color = live and theme.colors.text or theme.colors.textDim,
    })
    if row.entry.cond then
      Text.draw((met and "" or "waiting: ") .. Rules.describe(self.world, row.entry.cond), b.x + 130, row.y + 8, {
        size = "small",
        color = met and theme.colors.text or theme.colors.textDim,
      })
    end
  end
  local cat = self.selected
  local def = self.world.registry:get("task_categories", cat)
  local cond = Tasks.condition(self.world, cat)
  Text.draw(def.name .. ": only when", b.x + 12, self.editorY, { size = "small", color = theme.colors.textDim })
  Text.draw(self:valueText(cond), self.valueX + 2, self.editorY + 24, { size = "small" })
  self.buttons:draw()
end

return Routine
