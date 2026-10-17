-- Routine panel: the idle homesteader's priority list (GDD §7.4, priorities v1 and thresholds, D66).
-- Reorder categories, switch them on or off, and give a category a condition ("If" button): the
-- routine skips it while the condition is not met. The "If" button picks a row; the strip under the
-- list edits that row's condition kind and value with big stepper buttons. Changes apply at once.
-- Once the "Rules of thumb" perk is known, a block under the list sets a standing order per event class (Ask me,
-- Careful, Bold; B5, #349, docs/PLAN_DEPTH.md 6.4). Before that the block is not shown, so the perk is never named.

local Events = require("src.sim.systems.events")
local Tasks = require("src.sim.systems.tasks")
local Rules = require("src.sim.routine_rules")
local ScrollList = require("src.ui.scroll_list")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Routine = { name = "routine" }
Routine.__index = Routine

local ROW_H = 26
local HEADER_H = 40
local EDITOR_H = 56
local ORDERS_HEAD_H = 36 -- the standing orders block's heading and its one-line help
local CLASS_NAMES = { body = "Body", home = "Home", land = "Land", visitors = "Visitors" }
local MODE_NAMES = { ask = "Ask me", careful = "Careful", bold = "Bold" }
local MODE_W = 62

--- Are conditions switched on (tuning.idle.routineConditions)? Off for the playtest: no "If" button, no editor.
local function conditionsOn(world)
  return world.tuning.idle.routineConditions
end

--- Height the condition editor strip takes (none while conditions are off).
local function editorH(world)
  return conditionsOn(world) and EDITOR_H or 0
end

--- Height the standing orders block takes (none until the perk is known).
local function ordersH(world)
  return Events.ordersUnlocked(world) and (ORDERS_HEAD_H + #Events.CLASSES * ROW_H) or 0
end

function Routine.new(world)
  return setmetatable({ world = world, list = ScrollList.new() }, Routine)
end

function Routine:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.rowButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.list.onMove = function()
    self:layout()
  end
  self.selected = self.selected or self.world.state.priorities[1].category
end

function Routine:resize(view)
  local list = self.world.state.priorities
  self.box = Panel.box(view, 380, HEADER_H + #list * ROW_H + editorH(self.world) + ordersH(self.world) + 44)
  self:layout()
end

function Routine:layout()
  local b, world, ui = self.box, self.world, self.app.ctx.tuning.ui
  self.buttons:clear()
  self.rowButtons:clear()
  self.rows = {}
  -- The priority rows scroll in a window (the shared kit, D87/D94) when the screen is too short for all
  -- of them; the editor strip and Done stay put under it.
  local count = #world.state.priorities
  self.list:fit({
    x = b.x,
    y = b.y + HEADER_H,
    w = b.w,
    h = b.h - HEADER_H - editorH(world) - ordersH(world) - 44,
  }, count * ROW_H, ui.scrollHintHeight, ROW_H)
  local top = self.list:origin()
  for i, entry in ipairs(world.state.priorities) do
    local y = top + (i - 1) * ROW_H
    self.rows[i] = { y = y, entry = entry, visible = self.list:visible(y, ROW_H) }
    local right = b.x + b.w - 10 - (self.list.overflow and ui.scrollBarWidth + 4 or 0)
    local function add(label, onPress, opts)
      opts = opts or {}
      local w = opts.w or 26
      right = right - w
      if self.rows[i].visible then
        self.rowButtons:add({
          x = right,
          y = y,
          w = w,
          h = 24,
          label = label,
          enabled = opts.enabled ~= false,
          selected = opts.selected,
          onPress = onPress,
        })
      end
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
    if conditionsOn(world) then
      add("If", function()
        self.selected = entry.category
        self:layout()
      end, { selected = self.selected == entry.category })
    end
  end

  -- Standing orders: one row per event class, three buttons each, under the list (it scrolls, this does not).
  self.ordersY = nil
  if Events.ordersUnlocked(world) then
    self.ordersY = b.y + b.h - 44 - editorH(world) - ordersH(world)
    for n, class in ipairs(Events.CLASSES) do
      local y = self.ordersY + ORDERS_HEAD_H + (n - 1) * ROW_H
      local right = b.x + b.w - 12
      for m = #Events.MODES, 1, -1 do
        local mode = Events.MODES[m]
        right = right - MODE_W
        self.buttons:add({
          x = right,
          y = y,
          w = MODE_W,
          h = 24,
          label = MODE_NAMES[mode],
          selected = Events.orderMode(world, class) == mode,
          onPress = function()
            Events.setOrder(world, class, mode)
            self:layout()
          end,
        })
        right = right - 4
      end
    end
  end

  if not conditionsOn(world) then
    self:addDone(b)
    return
  end

  -- Editor strip for the selected category.
  local ey = b.y + b.h - EDITOR_H - 26
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

  self:addDone(b)
end

function Routine:addDone(b)
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
  if name == "press" or name == "release" then
    self.list:action(name, data) -- a drag that ends moving lets the list coast (D94)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "press" or name == "select" or name == "hover" then
    -- Row buttons only answer inside the list's window: a half-scrolled row must not reach out of it.
    if self.list:contains(data.x, data.y) then
      self.rowButtons:action(name, data)
    end
  elseif name == "release" then
    self.rowButtons:action(name, data)
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout()
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
  local b = self.box
  Panel.frame(self.app.view, b, "Routine", "Done top to bottom while you are away.")
  self.list:begin(self.app.view.scale)
  for i, row in ipairs(self.rows) do
    local cat = row.entry.category
    local def = self.world.registry:get("task_categories", cat)
    local met = Tasks.conditionMet(self.world, cat) -- always true while conditions are off
    local live = row.entry.enabled and met
    Text.draw(i .. ".  " .. def.name, b.x + 14, row.y + 6, {
      size = "body",
      color = live and theme.colors.text or theme.colors.textDim,
    })
    if conditionsOn(self.world) and row.entry.cond then
      Text.draw((met and "" or "waiting: ") .. Rules.describe(self.world, row.entry.cond), b.x + 130, row.y + 8, {
        size = "small",
        color = met and theme.colors.text or theme.colors.textDim,
      })
    end
  end
  self.rowButtons:draw()
  self.list:finish()
  if self.ordersY then
    Text.draw("When trouble comes", b.x + 14, self.ordersY + 2, { size = "body" })
    Text.draw(
      "Careful pays only what you can spare. Bold costs nothing.",
      b.x + 14,
      self.ordersY + 18,
      { size = "small", color = theme.colors.textDim }
    )
    for n, class in ipairs(Events.CLASSES) do
      Text.draw(CLASS_NAMES[class], b.x + 14, self.ordersY + ORDERS_HEAD_H + (n - 1) * ROW_H + 6, { size = "body" })
    end
  end
  self.list:drawCue(self.app.ctx.tuning.ui)
  if conditionsOn(self.world) then
    local cat = self.selected
    local def = self.world.registry:get("task_categories", cat)
    local cond = Tasks.condition(self.world, cat)
    Text.draw(def.name .. ": only when", b.x + 12, self.editorY, { size = "small", color = theme.colors.textDim })
    Text.draw(self:valueText(cond), self.valueX + 2, self.editorY + 24, { size = "small" })
  end
  self.buttons:draw()
end

return Routine
