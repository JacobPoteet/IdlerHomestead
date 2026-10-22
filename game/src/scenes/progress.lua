-- The Progress panel (D163, #342, #276; docs/PLAN_DEPTH.md §3): where the run stands. The pressing goal, what is limiting
-- the homestead (D202, #377: water, labour, storage, power or the market, read from Bottleneck), the year and the winter
-- ahead, the Footing checklist, the run's milestones and the gates that open at Footing, in one scrolling list. A browse
-- panel: it reads the sim (Goal, Bottleneck, Milestones) and changes nothing. Opened by a tap on the goal line under the
-- top bar or by the P key; Close, Esc or P puts it away. Tap only, no hover.

local Bottleneck = require("src.sim.systems.bottleneck")
local Buttons = require("src.ui.buttons")
local Goal = require("src.sim.systems.goal")
local GoalText = require("src.ui.goal_text")
local Milestones = require("src.sim.systems.milestones")
local Panel = require("src.ui.panel")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Scene = { name = "progress" }
Scene.__index = Scene

function Scene.new(world)
  return setmetatable({ world = world, list = ScrollList.new(), age = 0 }, Scene)
end

function Scene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function Scene:resize(view)
  self.box = Panel.box(view, self.app.ctx.tuning.ui.goal.panelWidth, view.h - 16)
  self:layout()
end

-- The panel's sections for the figures now.
local function sectionsOf(world)
  local done, total = Milestones.tally(world)
  return GoalText.panel(
    Goal.current(world),
    Milestones.list(world),
    { done, total },
    Goal.gates(world),
    Bottleneck.current(world)
  )
end

-- A string that changes when any word of the panel does, so a look that found nothing new costs no layout.
local function signature(sections)
  local parts = {}
  for _, s in ipairs(sections) do
    parts[#parts + 1] = s.title .. "=" .. (s.tag or "")
    for _, r in ipairs(s.rows) do
      parts[#parts + 1] = (r.mark or "-") .. ":" .. r.text .. ":" .. tostring(r.level)
    end
  end
  return table.concat(parts, "|")
end

function Scene:layout()
  local b, ui = self.box, self.app.ctx.tuning.ui
  local cfg = ui.goal
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)
  self.sections = sectionsOf(self.world)
  self.sig = signature(self.sections)
  local textW = b.w - 2 * cfg.pad - ui.scrollBarWidth - 4
  local _, titleH = Text.measure("Ag", "body")
  local y = 0
  self.items = {}
  for n, section in ipairs(self.sections) do
    if n > 1 then
      y = y + cfg.sectionGap
    end
    self.items[#self.items + 1] = { kind = "title", section = section, top = y, h = titleH }
    y = y + titleH + cfg.rowGap
    for _, row in ipairs(section.rows) do
      local indent = row.mark and (cfg.markSize + cfg.markGap) or 0
      local h = Text.wrappedHeight(row.text, "small", textW - indent)
      self.items[#self.items + 1] = { kind = "row", row = row, top = y, h = h, indent = indent }
      y = y + h + cfg.rowGap
    end
  end
  self.contentH = y
  self.textW = textW
  local top = b.y + cfg.headH
  self.list:fit({ x = b.x, y = top, w = b.w, h = b.y + b.h - 6 - top }, self.contentH, ui.scrollHintHeight, 20)
end

function Scene:update(dt)
  self.age = self.age + dt
  if self.age >= self.app.ctx.tuning.ui.goal.refresh then
    self.age = 0
    if signature(sectionsOf(self.world)) ~= self.sig then
      self:layout() -- news that arrives while the panel is open changes its words
    end
  end
end

function Scene:action(name, data)
  if name == "press" or name == "release" then -- a drag that ends moving lets the list coast (D94)
    self.list:action(name, data)
  end
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" or name == "progress" then
    self.app:pop() -- Esc or P again
  else
    self.list:action(name, data, self.app.ctx.tuning.ui)
  end
  return true -- modal
end

local function inkOf(row)
  local colors = theme.colors
  if row.level == 2 then
    return colors.danger
  elseif row.level == 1 then
    return colors.accent
  elseif row.dim then
    return colors.textDim
  end
  return colors.text
end

-- A checklist box: filled when done, an outline when still to do, a heavier one for a gate that is locked.
local function drawMark(mark, x, y, size, ink)
  love.graphics.setColor(ink)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, size - 1, size - 1)
  if mark == "done" or mark == "open" then
    love.graphics.rectangle("fill", x + 2, y + 2, size - 4, size - 4)
  elseif mark == "lock" then
    love.graphics.rectangle("fill", x + 2, y + math.floor(size / 2), size - 4, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Scene:draw()
  local b, cfg = self.box, self.app.ctx.tuning.ui.goal
  Panel.frame(self.app.view, b, GoalText.title, "Tap the line under the top bar, or press P")
  local colors = theme.colors
  self.list:begin(self.app.view.scale)
  local y0 = self.list:origin()
  local x = b.x + cfg.pad
  for _, item in ipairs(self.items) do
    local y = y0 + item.top
    if self.list:visible(y, item.h) then
      if item.kind == "title" then
        if item.top > 0 then -- a thin rule sets each section off from the one above
          love.graphics.setColor(colors.textDim[1], colors.textDim[2], colors.textDim[3], 0.4)
          love.graphics.rectangle("fill", x, y - math.floor(cfg.sectionGap / 2), self.textW, 1)
          love.graphics.setColor(1, 1, 1, 1)
        end
        Text.draw(item.section.title, x, y, { size = "body" })
        if item.section.tag then
          local w = Text.measure(item.section.tag, "small")
          Text.draw(item.section.tag, b.x + b.w - cfg.pad - self.app.ctx.tuning.ui.scrollBarWidth - 4 - w, y + 2, {
            size = "small",
            color = colors.textDim,
          })
        end
      else
        local row, ink = item.row, inkOf(item.row)
        if row.mark then
          drawMark(row.mark, x, y + 1, cfg.markSize, ink)
        end
        Text.draw(row.text, x + item.indent, y, { size = "small", width = self.textW - item.indent, color = ink })
      end
    end
  end
  self.list:finish()
  self.list:drawCue(self.app.ctx.tuning.ui)
  self.buttons:draw()
end

return Scene
