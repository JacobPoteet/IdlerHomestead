-- Recovery in town (GDD §4.3): review the run, take the one free study, then head out to new
-- land. Shown after the rescue, and on loading a slot that's still recovering.

local Journal = require("src.sim.systems.journal")
local Run = require("src.meta.run")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local NodeView = require("src.ui.node_view")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Recovery = { name = "recovery", opaque = true }
Recovery.__index = Recovery

local ROW_H = 28 -- an idea row: name and effect line
local LEARN_W = 72 -- width of the Learn button
local STAMP = 18 -- note stamp edge on an idea row
local STAMP_GAP = 2
local MAX_IDEAS = 5
local TABLE_Y = 54 -- progress table top, below the run line
local TABLE_ROW = 14 -- a table row (small text)
local TABLE_H = 66 -- vertical space the progress table takes; everything below moves down by it
local COL_LABEL_W = 138 -- row label column
local COL_WIDTHS = { 124, 84, 84 } -- this run (cell and marker), previous run, slot best

function Recovery.new()
  return setmetatable({}, Recovery)
end

function Recovery:enter(slot, data)
  self.slot, self.data = slot, data
  self.metaWorld = Run.metaWorld(self.app.ctx, data.meta)
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.app.ctx.store:write(slot, data) -- recovering survives a quit
end

function Recovery:resize(view)
  self.box = Panel.box(view, 460, view.h - 16)
  self:layout()
end

function Recovery:headOut()
  Run.startNext(self.data)
  self.app:switch(require("src.scenes.homestead").new(), self.slot, self.data)
end

function Recovery:layout()
  local b, recovery = self.box, self.data.meta.recovery
  self.buttons:clear()
  -- What ended the run (D99): the cause line and hint every time, plus one suggested first change on
  -- the slot's first recovery (#173). The study section below moves down to make room.
  local ctx = self.app.ctx
  local cause = recovery.summary.cause or { kind = "unknown" }
  self.failure = Run.failureText(ctx.registry, ctx.tuning, cause)
  self.firstChange = Run.rescues(self.data.meta) == 1
      and (ctx.tuning.ui.failure.firstChange .. " " .. Run.firstChange(ctx.registry, ctx.tuning, cause))
    or nil
  self.causeW = b.w - 24 - 18
  self.progress = Run.progressTable(ctx.tuning, self.data.meta.career, recovery.summary)
  local height = Text.wrappedHeight(self.failure.line, "small", self.causeW)
    + Text.wrappedHeight(self.failure.hint, "small", self.causeW)
    + (self.firstChange and Text.wrappedHeight(self.firstChange, "small", self.causeW) + 2 or 0)
  self.shift = TABLE_H + math.max(0, math.ceil(height) - 12) -- the block starts at +108 and the study label sits at +132, both below the progress table
  self.buttons:add({
    x = b.x + b.w - 136,
    y = b.y + b.h - 36,
    w = 124,
    h = 26,
    label = "Head out",
    style = "accent",
    onPress = function()
      self:headOut()
    end,
  })
  self.ideaRows = {}
  if recovery.freeStudyUsed then
    return
  end
  local y = b.y + 150 + self.shift
  for n, def in ipairs(Journal.ideas(self.metaWorld)) do
    if n > MAX_IDEAS then
      break
    end
    local textW = self:textWidth(def)
    local rowH = math.max(ROW_H, 14 + Text.wrappedHeight(def.line, "small", textW) + 2)
    self.ideaRows[#self.ideaRows + 1] = { item = def, y = y, textW = textW }
    self.buttons:add({
      x = b.x + b.w - LEARN_W - 12,
      y = y,
      w = LEARN_W,
      h = 24,
      label = "Learn",
      size = "small",
      style = "accent",
      onPress = function()
        Run.freeStudy(self.data, self.metaWorld, def.id)
        self.app.ctx.store:write(self.slot, self.data)
        self:layout()
      end,
    })
    y = y + rowH
  end
end

-- Width for an idea row's name and effect line: what's left between the icon and the stamps.
function Recovery:textWidth(def)
  local stamps = #(def.needs or {}) * (STAMP + STAMP_GAP)
  return self.box.w - 12 - 18 - LEARN_W - 12 - 8 - stamps - 8
end

function Recovery:action(name, data)
  self.buttons:action(name, data)
  return true
end

local function capitalize(s)
  return (s:gsub("^%l", string.upper))
end

-- Years survived and best year's income: this run, and (from the second run) the previous run and the
-- slot's best, with a marker where this run set a new best (D117, #275).
function Recovery:drawProgress(x, y)
  local p, t = self.progress, self.app.ctx.tuning.ui.progress
  local dim = theme.colors.textDim
  local colX = { x + COL_LABEL_W }
  for i = 1, #p.columns - 1 do
    colX[i + 1] = colX[i] + COL_WIDTHS[i]
  end
  for i, label in ipairs(p.columns) do
    Text.draw(label, colX[i], y, { size = "small", color = dim })
  end
  for n, row in ipairs(p.rows) do
    local ry = y + n * TABLE_ROW
    Text.draw(row.label, x, ry, { size = "small", color = dim })
    for i, cell in ipairs(row.cells) do
      Text.draw(cell, colX[i], ry, { size = "small", color = i == 1 and theme.colors.text or dim })
    end
    if row.newBest then
      local w = Text.measure(row.cells[1], "small")
      Text.draw(t.newBest, colX[1] + w + 6, ry, { size = "small", color = theme.colors.accent })
    end
  end
  if p.first then
    Text.draw(t.firstRun, x, y + (#p.rows + 1) * TABLE_ROW + 2, { size = "small", color = dim, width = self.box.w - 24 })
  end
end

function Recovery:draw()
  local view, b = self.app.view, self.box
  local recovery = self.data.meta.recovery
  local s = recovery.summary
  local registry = self.app.ctx.registry
  local dim = theme.colors.textDim
  love.graphics.setColor(0.07, 0.08, 0.10, 1)
  love.graphics.rectangle("fill", 0, 0, view.w, view.h)
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Recovering in town", b.x + 12, b.y + 10, { size = "heading" })
  Text.draw(string.format("Run %d · lasted %d days · reached %s, year %d", s.run, s.days, capitalize(s.season), s.year),
    b.x + 12, b.y + 34, { size = "small", color = dim })

  self:drawProgress(b.x + 12, b.y + TABLE_Y)

  local top = TABLE_H -- the notes, study and cause blocks sit below the progress table
  Text.draw(string.format("Notes this run (%d)", #s.notes), b.x + 12, b.y + 54 + top, { size = "small", color = dim })
  local x = b.x + 12
  for _, id in ipairs(s.notes) do
    if x > b.x + b.w - 24 then
      break
    end
    Panel.icon(registry:get("notes", id).icon, x, b.y + 68 + top)
    x = x + 16
  end
  if #s.notes == 0 then
    Text.draw("None this time.", b.x + 12, b.y + 68 + top, { size = "small", color = dim })
  end

  local y = b.y + 92 + top
  if recovery.finishedStudy then
    Text.draw("Finished studying: " .. Journal.node(self.metaWorld, recovery.finishedStudy).name, b.x + 12, y, {
      size = "small",
      color = theme.colors.accent,
    })
  end

  local f = self.failure
  Panel.icon(f.icon, b.x + 12, b.y + 108 + top)
  Text.draw(f.line, b.x + 30, b.y + 108 + top, { size = "small", width = self.causeW })
  local cy = b.y + 108 + top + Text.wrappedHeight(f.line, "small", self.causeW)
  Text.draw(f.hint, b.x + 30, cy, { size = "small", width = self.causeW, color = dim })
  if self.firstChange then
    cy = cy + Text.wrappedHeight(f.hint, "small", self.causeW) + 2
    Text.draw(self.firstChange, b.x + 30, cy, { size = "small", width = self.causeW, color = theme.colors.accent })
  end

  Text.draw("One free study while you recover", b.x + 12, b.y + 132 + self.shift, { size = "small", color = dim })
  if recovery.freeStudyUsed then
    Text.draw("Learned: " .. Journal.node(self.metaWorld, recovery.freeStudy).name, b.x + 12, b.y + 150 + self.shift, {
      size = "body",
      color = theme.colors.accent,
    })
  elseif #self.ideaRows == 0 then
    Text.draw("No ideas yet. Notes from your next run will spark some.", b.x + 12, b.y + 150 + self.shift, {
      size = "small",
      color = dim,
    })
  end
  for _, row in ipairs(self.ideaRows) do
    Panel.icon(Panel.nodeIcon(registry, row.item), b.x + 12, row.y + 6)
    Text.draw(row.item.name, b.x + 30, row.y + 1, { size = "small", width = row.textW })
    Text.draw(row.item.line, b.x + 30, row.y + 13, { size = "small", width = row.textW, color = dim })
    local stampsW = #(row.item.needs or {}) * (STAMP + STAMP_GAP)
    NodeView.needStamps(self.metaWorld, row.item, b.x + b.w - LEARN_W - 12 - 8 - stampsW, row.y + 3, STAMP, STAMP_GAP)
  end

  Text.draw("New land, same knowledge. Nothing else comes with you.", b.x + 12, b.y + b.h - 34, {
    size = "small",
    width = b.w - 24 - 136, -- leave room for the Head out button
    color = dim,
  })
  self.buttons:draw()
end

return Recovery
