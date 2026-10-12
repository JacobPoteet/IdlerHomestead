-- Field Journal (GDD §8.1): the study queue, ideas you could study, and the notes you've written.
-- Studying happens at night; choosing what to study is always the player's decision.
-- A plain panel for now; the visual knowledge map (GDD §8.3) replaces this layout.

local Journal = require("src.sim.systems.journal")
local Buttons = require("src.ui.buttons")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local JournalScene = { name = "journal" }
JournalScene.__index = JournalScene

local ROW_H = 26
local STAMP = 26

function JournalScene.new(world)
  return setmetatable({ world = world, selectedNote = nil }, JournalScene)
end

function JournalScene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
end

function JournalScene:resize(view)
  self.box = Panel.box(view, 460, view.h - 16)
  self:layout()
end

-- Ideas that aren't already in the queue.
function JournalScene:openIdeas()
  local list = {}
  for _, def in ipairs(Journal.ideas(self.world)) do
    if Journal.status(self.world, def.id) == "idea" then
      list[#list + 1] = def
    end
  end
  return list
end

function JournalScene:layout()
  local b, world = self.box, self.world
  local registry = world.registry
  self.buttons:clear()
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)

  local y = b.y + 42
  self.queueY = y
  self.queueRows = {}
  for _, id in ipairs(Journal.queue(world)) do
    y = y + 12
    self.queueRows[#self.queueRows + 1] = { item = registry:get("catalog", id), y = y }
    self.buttons:add({ x = b.x + b.w - 70, y = y, w = 58, h = ROW_H - 4, label = "Remove", size = "small",
      onPress = function()
        Journal.unqueue(world, id)
        self:layout()
      end })
    y = y + ROW_H - 12
  end
  if #self.queueRows == 0 then
    y = y + 26
  end

  y = y + 10
  self.ideasY = y
  self.ideaRows = {}
  local full = #Journal.queue(world) >= world.tuning.study.queueSize
  for _, def in ipairs(self:openIdeas()) do
    y = y + 12
    self.ideaRows[#self.ideaRows + 1] = { item = def, y = y }
    self.buttons:add({ x = b.x + b.w - 70, y = y, w = 58, h = ROW_H - 4, label = full and "Full" or "Study",
      size = "small", style = not full and "accent" or nil, enabled = not full,
      onPress = function()
        Journal.study(world, def.id)
        self:layout()
      end })
    y = y + ROW_H - 12
  end
  if #self.ideaRows == 0 then
    y = y + 26
  end

  y = y + 10
  self.notesY = y
  self.stamps = {}
  local x = b.x + 12
  y = y + 14
  for _, note in ipairs(registry:all("notes")) do
    if x + STAMP > b.x + b.w - 12 then
      x, y = b.x + 12, y + STAMP + 4
    end
    local earned = Journal.hasNote(world, note.id)
    self.stamps[#self.stamps + 1] = { note = note, x = x, y = y, earned = earned }
    self.buttons:add({ x = x, y = y, w = STAMP, h = STAMP, label = "", selected = self.selectedNote == note.id,
      onPress = function()
        self.selectedNote = note.id
        self:layout()
      end })
    x = x + STAMP + 4
  end
  self.notesBottom = y + STAMP + 6
end

function JournalScene:update(dt)
  -- Study progresses while the panel is open; refresh now and then.
  self.refresh = (self.refresh or 0) - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layout()
  end
end

function JournalScene:action(name, data)
  if not self.buttons:action(name, data) and name == "cancel" then
    self.app:pop()
  end
  return true
end

local function heading(text, x, y)
  Text.draw(text, x, y, { size = "small", color = theme.colors.textDim })
end

local function progressBar(x, y, w, fraction)
  love.graphics.setColor(theme.colors.buttonDisabled)
  love.graphics.rectangle("fill", x, y, w, 5, 2, 2)
  local filled = math.floor(w * fraction + 0.5)
  if filled >= 1 then
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", x, y, filled, 5, 2, 2)
  end
end

local function nights(n)
  return n == 1 and "1 night" or (n .. " nights")
end

-- Note stamps an item needs: filled when written.
local function needStamps(world, item, x, y)
  for _, noteId in ipairs(item.needs or {}) do
    local note = world.registry:get("notes", noteId)
    Panel.icon(note.icon, x, y, Journal.hasNote(world, noteId) and 1 or 0.3)
    x = x + 14
  end
end

function JournalScene:draw()
  local b, world = self.box, self.world
  local dim = theme.colors.textDim
  local written, total = 0, 0
  for _, note in ipairs(world.registry:all("notes")) do
    total = total + 1
    if Journal.hasNote(world, note.id) then
      written = written + 1
    end
  end
  Panel.frame(self.app.view, b, "Field Journal", "Notes spark ideas. Ideas are studied at night and known for good.")

  heading(string.format("Studying at night (%d/%d)", #self.queueRows, world.tuning.study.queueSize), b.x + 12, self.queueY)
  for n, row in ipairs(self.queueRows) do
    local item = row.item
    Panel.icon(Panel.catalogIcon(item), b.x + 12, row.y + 3)
    Text.draw(item.name, b.x + 30, row.y + 1, { size = "small", color = n == 1 and theme.colors.text or dim })
    local fraction = Journal.progress(world, item.id)
    progressBar(b.x + 30, row.y + 12, 140, fraction)
    Text.draw(string.format("%.1f / %s", fraction * item.studyNights, nights(item.studyNights)), b.x + 178, row.y + 9, {
      size = "small",
      color = dim,
    })
  end
  if #self.queueRows == 0 then
    local hint = #self.ideaRows > 0 and "Nothing queued. Pick an idea to study tonight." or "Nothing to study yet."
    Text.draw(hint, b.x + 12, self.queueY + 14, {
      size = "small",
      color = #self.ideaRows > 0 and theme.colors.accent or dim,
    })
  end

  heading("Ideas", b.x + 12, self.ideasY)
  for _, row in ipairs(self.ideaRows) do
    local item = row.item
    Panel.icon(Panel.catalogIcon(item), b.x + 12, row.y + 3)
    Text.draw(item.name, b.x + 30, row.y + 3, { size = "small" })
    needStamps(world, item, b.x + 150, row.y + 2)
    Text.draw(string.format("%s · $%d", nights(item.studyNights), item.price), b.x + 240, row.y + 3, {
      size = "small",
      color = dim,
    })
  end
  if #self.ideaRows == 0 then
    Text.draw("Keep living out here. New notes spark ideas.", b.x + 12, self.ideasY + 14, { size = "small", color = dim })
  end

  heading(string.format("Notes (%d/%d)", written, total), b.x + 12, self.notesY)
  self.buttons:draw()
  for _, stamp in ipairs(self.stamps) do
    local inset = (STAMP - 12) / 2
    Panel.icon(stamp.earned and stamp.note.icon or "icon_note_blank", stamp.x + inset, stamp.y + inset)
  end
  if self.selectedNote then
    local note = world.registry:get("notes", self.selectedNote)
    local info = Journal.noteInfo(world, note.id)
    local text
    if info then
      text = string.format("%s:  %s  (%s day %d)", note.name, note.line, info.season, info.day)
    else
      text = "Not written yet."
    end
    Text.draw(text, b.x + 12, self.notesBottom, { size = "small", width = b.w - 24 })
  end
end

return JournalScene
