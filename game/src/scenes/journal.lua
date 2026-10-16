-- Field Journal (GDD §8.1, §8.3, D81): the study queue, the knowledge tree and the notes you've written.
-- Studying happens at night; choosing what to study is always the player's decision.
--
-- Layout, top to bottom: the study queue strip, the map area, and the notes strip. The map area shows
-- either the OVERVIEW (chapter tiles grouped under area headings, scrolling vertically) or one FOCUSED
-- chapter fitted to the view (note stamps left, nodes right, links; auto-laid-out by journal_map.lua, D41).
-- Tapping a node opens a compact card (below the chapter, or beside it on wide, short views).
-- The navigation is split into small, replaceable modules (D81, intentionally minimal):
--   ui/journal_layout.lua (pure geometry)   ui/journal_nav.lua (state and input)
--   ui/journal_overview.lua, ui/journal_focus.lua (drawing).   This scene glues them together.

local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Buttons = require("src.ui.buttons")
local Focus = require("src.ui.journal_focus")
local Layout = require("src.ui.journal_layout")
local Nav = require("src.ui.journal_nav")
local Search = require("src.ui.journal_search")
local TextField = require("src.ui.text_field")
local Overview = require("src.ui.journal_overview")
local NodeView = require("src.ui.node_view")
local Panel = require("src.ui.panel")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local JournalScene = { name = "journal" }
JournalScene.__index = JournalScene

-- Layout, in virtual pixels.
local MAX_W = 720 -- panel width on wide windows
local CHIP_H = 34 -- height of a study queue chip
local CHIP_GAP = 4 -- space between queue chips
local CARD_H = 64 -- node card height (taller when an unknown node lists what it needs)
local CARD_TEXT_X = 38 -- card text left edge, from the card's left
local CARD_TEXT_TOP = 21 -- card description top, from the card's top
local CARD_STAMP_ROOM = 30 -- space kept under the description for the needed-note stamps
local NOTE_STAMP = 24 -- note stamp edge in the notes strip (touch-sized)
local NOTE_GAP = 2 -- space between note stamps
local RING_R = 12.5 -- radius of a node's study progress ring
local ICON_SCALE = 2 -- node icons are drawn at twice their sprite size
local TITLE_PAD = 36 -- space from the panel top to the queue heading

local COLOR = {
  mapBg = { 0.09, 0.11, 0.10, 1 },
  region = { 0.14, 0.17, 0.15, 1 },
  known = { 0.22, 0.29, 0.20, 1 },
  active = { 0.19, 0.22, 0.18, 1 },
  idea = { 0.15, 0.17, 0.16, 1 },
  unknown = { 0.11, 0.13, 0.12, 1 },
  ink = { 0.78, 0.82, 0.62, 1 },
  linkOff = { 0.40, 0.44, 0.38, 0.55 },
  track = { 0.26, 0.29, 0.25, 1 },
  badge = { 0.89, 0.71, 0.36, 1 },
}
local SKETCH = { 0.80, 0.84, 0.95 } -- an idea's icon: pale, like pencil
local SILHOUETTE = { 0.16, 0.18, 0.17 } -- an unknown node's icon

local ORDER_REASONS =
  { owned = "Owned", ordered = "Ordered", ["pickup only"] = "In town", ["too big for storage"] = "Too big" }

-- Test hook: a function(world) -> chapters that replaces Journal.chapters (the screenshot driver uses it to
-- show a grown journal). Nil in the game.
JournalScene.chapterSource = nil

-- The chapter the Journal was last left in, by chapter id, so the next visit reopens on it (D120, #208). It
-- lives here, in memory for the session, on purpose: it is a convenience and not game state, so it is
-- not in the slot save (no SAVE_COMPAT change) and not one of the settings (those are typed options, D96).
-- { world, id }: set whenever a chapter is on show, and only honoured for that same world, so a new game or
-- a loaded slot starts on the default. A chapter that is gone is ignored.
JournalScene.lastChapter = nil

function JournalScene.new(world, onToast)
  return setmetatable(
    { world = world, onToast = onToast, selected = nil, selectedNote = nil, nav = Nav.new() },
    JournalScene
  )
end

function JournalScene:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.cardButtons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self.spec = self.app.ctx.tuning.ui.journal
  self.pendingFocus = true
  self.refresh = 0
  self.field = TextField.new(self.spec.search.maxLength)
end

function JournalScene:exit()
  self.field:blur()
end

local function inRect(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function nights(n)
  return n == 1 and "1 night" or (n .. " nights")
end

local function capitalize(s)
  return (s:gsub("^%l", string.upper))
end

-- Layout --------------------------------------------------------------------------------------

function JournalScene:resize(view)
  local world = self.world
  local b = Panel.box(view, MAX_W, view.h - 16)
  self.box = b
  local inner = b.w - 12
  local _, lineH = Text.measure("A", "small")

  self.queueRect = { x = b.x + 6, y = b.y + TITLE_PAD + lineH + 3, w = inner, h = CHIP_H }

  self.notes = world.registry:all("notes")
  local perRow = math.max(1, math.floor((inner + NOTE_GAP) / (NOTE_STAMP + NOTE_GAP)))
  local rows = math.ceil(#self.notes / perRow)
  local infoH = (inner < 460 and 2 or 1) * lineH
  local notesH = lineH + 3 + rows * (NOTE_STAMP + NOTE_GAP) + infoH + 2
  self.notesRect = { x = b.x + 6, y = b.y + b.h - 6 - notesH, w = inner, h = notesH, perRow = perRow }

  local mapTop = self.queueRect.y + CHIP_H + 4
  self.mapRect = { x = b.x + 6, y = mapTop, w = inner, h = self.notesRect.y - 4 - mapTop }
  self:placeCard()

  self.chapters = self:chapterList()
  self.groups = Layout.groups(self.chapters, self.spec.defaultArea)
  Nav.resized(self.nav)
  self:layoutButtons()
  if self.pendingFocus then
    -- Open on the overview, scrolled to the chapter that has something to do.
    self.pendingFocus = false
    local target = Layout.startTarget(Journal.queue(world), self:ideaIds())
    local index = target and Layout.chapterIndexOf(self.chapters, target)
    if index then
      self.nav.cur = index
      Nav.revealTile(self.nav, index, self.spec)
    end
    -- Back where you left off, when that chapter still exists.
    local last = Search.rememberedIndex(self.chapters, self:lastChapterId())
    if last then
      self.nav.cur = last
      Nav.revealTile(self.nav, last, self.spec)
      Nav.openChapter(self.nav, last)
      self:layoutButtons()
    end
  end
end

--- The id of the chapter to reopen on: the one last viewed in this world, or nil.
function JournalScene:lastChapterId()
  local last = JournalScene.lastChapter
  return last and last.world == self.world and last.id or nil
end

function JournalScene:chapterList()
  return (JournalScene.chapterSource or Journal.chapters)(self.world)
end

--- The ids of the ideas nobody has queued yet ("to study"), in journal order.
function JournalScene:ideaIds()
  local ids = {}
  for _, def in ipairs(Journal.ideas(self.world)) do
    if Journal.status(self.world, def.id) == "idea" then
      ids[#ids + 1] = def.id
    end
  end
  return ids
end

--- What to do to learn a node that is still unknown (D72, #160): "Needs: Fell a tree; Catch a fish", from
--- the hints of the notes it is missing. Nil when it is not unknown. The node's name stays hidden.
function JournalScene:unlockText(id)
  if not id or Journal.status(self.world, id) ~= "unknown" then
    return nil
  end
  local parts = {}
  for _, note in ipairs(Journal.missingNotes(self.world, id)) do
    parts[#parts + 1] = note.hint
  end
  if #parts == 0 then
    return nil
  end
  return "Needs: " .. table.concat(parts, "; ")
end

--- The open card's height: tall enough for the unlock text, which wraps under the title.
function JournalScene:cardHeight()
  local text = self:unlockText(self.selected)
  if not text then
    return CARD_H
  end
  local _, _, side = Layout.cardSlot(self.mapRect, 0, self.spec)
  local width = side and self.spec.sideCardWidth or self.mapRect.w - 2 * self.spec.pad
  return math.max(CARD_H, CARD_TEXT_TOP + Text.wrappedHeight(text, "small", width - CARD_TEXT_X - 8) + CARD_STAMP_ROOM)
end

function JournalScene:placeCard()
  self.cardRect, self.cardH, self.cardSide = Layout.cardSlot(self.mapRect, self:cardHeight(), self.spec)
end

--- Open a node's card and show its chapter, unless `keepChapter` (a tap inside the chapter already shown).
function JournalScene:select(id, keepChapter)
  self.selected, self.selectedNote = id, nil
  local index = id and not keepChapter and Layout.chapterIndexOf(self.chapters, id)
  if index then
    Nav.openChapter(self.nav, index)
  end
  self:layoutButtons()
  if id then
    Nav.revealNode(self.nav, id, keepChapter)
  end
end

--- Jump to a search result: leave the search, show the node's chapter and open its card.
function JournalScene:pickResult(result)
  self.field:clear()
  self.field:blur()
  self:select(result.id)
end

function JournalScene:selectNote(id)
  self.selectedNote = id
  self:layoutButtons()
end

--- Rebuild the navigation chips and the overview / focus geometry from the current journal state.
function JournalScene:layoutNav()
  local world, nav = self.world, self.nav
  local function statusOf(id)
    return Journal.status(world, id)
  end
  local ideas = self:ideaIds()
  self.stats = Layout.allStats(self.chapters, statusOf)
  self.results = Search.find(self.chapters, statusOf, self.field.text)
  local data = {
    chapters = self.chapters,
    stats = self.stats,
    groups = self.groups,
    ideaCount = #ideas,
    results = self.results,
    showField = self.field.focused or not self.field:isEmpty(),
    selected = self.selected,
  }
  self.resultData = data
  local free = Layout.freeRect(self.mapRect, self.selected and self.cardRect or nil, self.cardSide, self.spec)
  Nav.layout(nav, data, free, self.spec, self.app.ctx.tuning.input.minTouchTarget)
  if nav.view == "focus" and self.chapters[nav.cur] then
    JournalScene.lastChapter = { world = self.world, id = self.chapters[nav.cur].id } -- the chapter last viewed, for the next visit
  end
  -- The search field takes the keyboard when tapped; Clear empties it and shows the chapters again.
  if nav.field then
    nav.field.onPress = function()
      self.field:focus(nav.field, self.app.view.scale)
    end
    self.hits[#self.hits + 1] = nav.field
  end
  if nav.clear then
    nav.clear.onPress = function()
      self:endSearch()
    end
    self.hits[#self.hits + 1] = nav.clear
  end
  for _, chip in ipairs(nav.chips) do
    local kind = chip.kind
    chip.onPress = function()
      if kind == "back" then
        Nav.backToOverview(nav)
        self.selected, self.selectedNote = nil, nil
        self:layoutButtons()
      elseif kind == "queue" then
        local id = Layout.queueTarget(Journal.queue(world))
        if id then
          self:select(id)
        end
      elseif kind == "search" then
        self:startSearch()
      elseif kind == "study" then
        local id = Layout.nextIdea(self:ideaIds(), self.selected)
        if id then
          self:select(id)
        end
      else
        Nav.setFilter(nav, kind)
        self:layoutButtons()
      end
    end
    self.hits[#self.hits + 1] = chip
  end
end

--- Open the search field (a row under the top of the map) and give it the keyboard.
function JournalScene:startSearch()
  self.field.focused = true
  self:layoutButtons()
  self.field:focus(self.nav.field, self.app.view.scale)
end

--- Empty the search field and hand the keyboard back.
function JournalScene:endSearch()
  self.field:clear()
  self.field:blur()
  self:layoutButtons()
end

-- Buttons and tap targets. Chips and note stamps are plain hit rectangles (drawn by hand);
-- the Close button and the card's buttons use the shared Buttons widget.
function JournalScene:layoutButtons()
  local world, b = self.world, self.box
  self:placeCard()
  self.buttons:clear()
  self.cardButtons:clear()
  self.hits = {}
  Panel.closeButton(self.buttons, b, function()
    self.app:pop()
  end)

  -- Study queue chips.
  local size = world.tuning.study.queueSize
  local q = self.queueRect
  self.chips = {}
  local chipW = math.floor((q.w - (size - 1) * CHIP_GAP) / size)
  for slot, id in ipairs(Journal.queue(world)) do
    local chip = { id = id, x = q.x + (slot - 1) * (chipW + CHIP_GAP), y = q.y, w = chipW, h = CHIP_H }
    self.chips[slot] = chip
    chip.onPress = function()
      self:select(id)
    end
    self.hits[#self.hits + 1] = chip
  end
  self.freeSlots = {}
  for slot = #self.chips + 1, size do
    self.freeSlots[#self.freeSlots + 1] = { x = q.x + (slot - 1) * (chipW + CHIP_GAP), y = q.y, w = chipW, h = CHIP_H }
  end

  -- Note stamps.
  local n = self.notesRect
  self.noteStamps = {}
  for i, note in ipairs(self.notes) do
    local col, row = (i - 1) % n.perRow, math.floor((i - 1) / n.perRow)
    local stamp = {
      note = note,
      x = n.x + col * (NOTE_STAMP + NOTE_GAP),
      y = n.y + select(2, Text.measure("A", "small")) + 3 + row * (NOTE_STAMP + NOTE_GAP),
      w = NOTE_STAMP,
      h = NOTE_STAMP,
    }
    stamp.onPress = function()
      self:selectNote(note.id)
    end
    self.noteStamps[i] = stamp
    self.hits[#self.hits + 1] = stamp
  end

  -- The map area: chips (jumps, filter) and the overview grid or the fitted chapter.
  self:layoutNav()

  -- The open node's card.
  self.cardStamps = {}
  local id = self.selected
  if not id then
    return
  end
  local c = self.cardRect
  local def = Journal.node(world, id)
  local status = Journal.status(world, id)
  local kind = Journal.kindOf(world, id)
  local btn = { x = c.x + c.w - 90, y = c.y + c.h - 30, w = 82, h = 24, size = "small" }
  if status == "idea" then
    local full = #Journal.queue(world) >= world.tuning.study.queueSize
    btn.label, btn.enabled = full and "Queue full" or "Study", not full
    btn.style = not full and "accent" or nil
    btn.onPress = function()
      Journal.study(world, id)
      self:layoutButtons()
    end
  elseif status == "queued" or status == "studying" then
    btn.label = "Remove"
    btn.onPress = function()
      Journal.unqueue(world, id)
      self:layoutButtons()
    end
  elseif status == "known" and kind == "catalog" then
    local reason = Market.cannotBuy(world, id, false)
    btn.label = ORDER_REASONS[reason] or ("Order $" .. (Market.itemPrice(world, id) + world.tuning.economy.deliveryFee))
    btn.enabled = reason == nil
    btn.style = Market.itemPrice(world, id) < def.price and "accent" or nil
    btn.onPress = function()
      if Market.order(world, id) and self.onToast then
        self.onToast("Ordered " .. def.name .. " · arrives tomorrow")
      end
      self:layoutButtons()
    end
  else
    btn = nil
  end
  if btn then
    self.cardButtons:add(btn)
  end
  local x = c.x + 8
  for _, noteId in ipairs(def.needs or {}) do
    local stamp = { note = noteId, x = x, y = c.y + c.h - 6 - 22, w = 22, h = 22 }
    stamp.onPress = function()
      self:selectNote(noteId)
    end
    self.cardStamps[#self.cardStamps + 1] = stamp
    x = x + 26
  end
  self.cardStampsRight = x
end

function JournalScene:update(dt)
  self.field:update(dt)
  -- Study progresses and money changes while the panel is open; keep the buttons honest.
  self.refresh = self.refresh - dt
  if self.refresh <= 0 then
    self.refresh = 0.5
    self:layoutButtons()
  end
end

-- Input ---------------------------------------------------------------------------------------

function JournalScene:cardOpen()
  return self.selected ~= nil
end

function JournalScene:tapMap(x, y)
  local nav = self.nav
  if nav.list then
    local index = Nav.resultAt(nav, x, y)
    if index then
      self:pickResult(self.results[index])
    end
    return
  end
  if nav.view == "overview" then
    local index = Nav.tileAt(nav, x, y)
    if index then
      Nav.openChapter(nav, index)
      self.selected, self.selectedNote = nil, nil
      self:layoutButtons()
    end
    return
  end
  if not inRect(nav.body, x, y) then
    return
  end
  local kind, id = Layout.hit(nav.fit, x, y, nav.focusOffset)
  if kind == "node" then
    self:select(id, true)
  elseif kind == "note" then
    self.selected = nil
    self:selectNote(id)
  else
    -- Empty paper: put the card and the note away.
    self.selected, self.selectedNote = nil, nil
    self:layoutButtons()
  end
end

function JournalScene:action(name, data)
  local consumed = false
  if self:cardOpen() and self.cardButtons:action(name, data) then
    consumed = true
  elseif self.buttons:action(name, data) then
    consumed = true
  end

  if name == "press" then
    self.dragInMap = not consumed
      and inRect(self.mapRect, data.x, data.y)
      and not (self:cardOpen() and inRect(self.cardRect, data.x, data.y))
  elseif name == "pan" then
    -- Typing "a", "s", "d" or "w" must not scroll the list under the search field.
    if (data.keys and not self.field.focused) or (self.dragInMap and not data.keys) then
      Nav.drag(self.nav, data.dy)
    end
  elseif name == "zoom" then
    -- The mouse wheel scrolls the overview.
    if inRect(self.mapRect, data.x, data.y) then
      Nav.wheel(self.nav, data.steps, self.spec.wheelStep)
    end
  elseif name == "select" and not consumed then
    local x, y = data.x, data.y
    if self:cardOpen() and inRect(self.cardRect, x, y) then
      for _, stamp in ipairs(self.cardStamps) do
        if inRect(stamp, x, y) then
          stamp.onPress()
          break
        end
      end
    else
      local hit
      for _, h in ipairs(self.hits) do
        if inRect(h, x, y) then
          hit = h
        end
      end
      if hit then
        hit.onPress()
      elseif inRect(self.mapRect, x, y) then
        self:tapMap(x, y)
      end
    end
  elseif name == "cancel" then
    if self.field.focused or not self.field:isEmpty() then
      self:endSearch()
    elseif self.selected or self.selectedNote then
      self.selected, self.selectedNote = nil, nil
      self:layoutButtons()
    elseif self.nav.view == "focus" then
      Nav.backToOverview(self.nav)
      self:layoutButtons()
    else
      self.app:pop()
    end
  end
  return true
end

--- Typed text goes to the search field once it has the keyboard.
function JournalScene:textinput(text)
  if self.field.focused then
    self.field:insert(text)
    self.nav.resultOffset = 0
    self:layoutButtons()
  end
end

--- Backspace edits the query, Enter opens the first match, Ctrl+F puts the keyboard in the search field.
function JournalScene:keypressed(key)
  if self.field.focused then
    if key == "backspace" then
      self.field:backspace()
      self.nav.resultOffset = 0
      self:layoutButtons()
    elseif (key == "return" or key == "kpenter") and self.results and self.results[1] then
      self:pickResult(self.results[1])
    end
  elseif key == "f" and (love.keyboard.isDown("lctrl", "rctrl")) then
    self:startSearch()
  end
end

-- Drawing -------------------------------------------------------------------------------------

local function progressBar(x, y, w, fraction, color)
  love.graphics.setColor(theme.colors.buttonDisabled)
  love.graphics.rectangle("fill", x, y, w, 5, 2, 2)
  local filled = math.floor(w * fraction + 0.5)
  if filled >= 1 then
    love.graphics.setColor(color or theme.colors.accent)
    love.graphics.rectangle("fill", x, y, filled, 5, 2, 2)
  end
end

local function drawRing(cx, cy, r, fraction, color)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(COLOR.track)
  love.graphics.circle("line", cx, cy, r, 24)
  if fraction > 0 then
    love.graphics.setColor(color)
    if fraction >= 0.995 then
      love.graphics.circle("line", cx, cy, r, 24)
    else
      love.graphics.arc("line", "open", cx, cy, r, -math.pi / 2, -math.pi / 2 + fraction * 2 * math.pi, 24)
    end
  end
  love.graphics.setLineWidth(1)
end

local function drawBadge(cx, cy)
  love.graphics.setColor(COLOR.badge)
  love.graphics.circle("fill", cx, cy, 5)
  love.graphics.setColor(0.12, 0.10, 0.06, 1)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(cx - 2.5, cy, cx - 0.5, cy + 2, cx + 2.5, cy - 2)
  love.graphics.setLineWidth(1)
end

-- Is this item "owned this run"? Only catalog gear and buildings can be.
function JournalScene:owned(def, status)
  return status == "known" and Journal.kindOf(self.world, def.id) == "catalog" and Inventory.owns(self.world, def.id)
end

function JournalScene:drawNode(node)
  local world, colors = self.world, theme.colors
  local def, id = node.def, node.id
  local status = Journal.status(world, id)
  local x, y, w, h = node.x, node.y, node.w, node.h
  local iconId = Panel.nodeIcon(world.registry, def)

  local fill = COLOR.unknown
  local border = colors.panelBorder
  if status == "known" then
    fill, border = COLOR.known, COLOR.ink
  elseif status == "studying" or status == "queued" then
    fill, border = COLOR.active, colors.accent
  elseif status == "idea" then
    fill, border = COLOR.idea, colors.accent
  end
  love.graphics.setColor(fill)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(border)
  love.graphics.setLineWidth(1)
  if status == "idea" or status == "unknown" then
    if status == "unknown" then
      love.graphics.setColor(colors.panelBorder[1], colors.panelBorder[2], colors.panelBorder[3], 0.7)
    end
    NodeView.dashedRect(x, y, w, h, 3, 2)
  else
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  end
  if id == self.selected then
    love.graphics.setColor(colors.text)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x - 1, y - 1, w + 2, h + 2, 5, 5)
    love.graphics.setLineWidth(1)
  end

  local iconX, iconY = x + 4, y + (h - 12 * ICON_SCALE) / 2
  if status == "unknown" then
    Panel.icon(iconId, iconX, iconY, 0.55, ICON_SCALE, SILHOUETTE)
    Text.draw(
      "?",
      iconX,
      iconY + 5,
      { size = "body", color = colors.textDim, width = 12 * ICON_SCALE, align = "center" }
    )
  elseif status == "idea" then
    Panel.icon(iconId, iconX, iconY, 0.75, ICON_SCALE, SKETCH)
  else
    Panel.icon(iconId, iconX, iconY, 1, ICON_SCALE)
  end
  if status == "studying" or status == "queued" then
    drawRing(
      x + 16,
      y + h / 2,
      RING_R,
      Journal.progress(world, id),
      status == "studying" and colors.accent or colors.textDim
    )
  end

  local name = status == "unknown" and "???" or def.name
  local textW = w - 36
  local textH = Text.wrappedHeight(name, "small", textW)
  local color = (status == "known" or status == "studying") and colors.text
    or (status == "unknown" and colors.textDim or colors.text)
  Text.draw(name, x + 32, y + (h - textH) / 2, { size = "small", width = textW, color = color })
  if self:owned(def, status) then
    drawBadge(x + w - 3, y + 3)
  end
end

function JournalScene:linkFocus(link)
  if self.selectedNote then
    return link.stamp.note == self.selectedNote
  elseif self.selected then
    return link.node.id == self.selected
  end
  return nil
end

function JournalScene:drawRegion(region)
  local world, colors = self.world, theme.colors
  love.graphics.setColor(COLOR.region)
  love.graphics.rectangle("fill", region.x, region.y, region.w, region.h, 5, 5)
  love.graphics.setColor(colors.panelBorder[1], colors.panelBorder[2], colors.panelBorder[3], 0.6)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", region.x + 0.5, region.y + 0.5, region.w - 1, region.h - 1, 5, 5)
  local known = 0
  for _, node in ipairs(region.nodes) do
    if Journal.isKnown(world, node.id) then
      known = known + 1
    end
  end
  Text.draw(region.name, region.x + 6, region.y + 3, { size = "small", color = colors.accent })
  Text.draw(string.format("%d/%d", known, #region.nodes), region.x, region.y + 3, {
    size = "small",
    color = colors.textDim,
    width = region.w - 6,
    align = "right",
  })

  for _, link in ipairs(region.links) do
    local focus = self:linkFocus(link)
    local written = Journal.hasNote(world, link.stamp.note)
    local c = written and colors.accent or COLOR.linkOff
    local alpha = written and 0.7 or c[4]
    if focus == true then
      alpha = 1
    elseif focus == false then
      alpha = alpha * 0.35
    end
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.setLineWidth(focus and 2 or 1)
    local s, n = link.stamp, link.node
    love.graphics.line(s.x + s.w, s.y + s.h / 2, n.x, n.y + n.h / 2)
  end
  love.graphics.setLineWidth(1)
  for _, stamp in ipairs(region.stamps) do
    local emphasis = stamp.note == self.selectedNote
    if self.selected then
      for _, need in ipairs(Journal.node(world, self.selected).needs or {}) do
        emphasis = emphasis or need == stamp.note
      end
    end
    NodeView.stamp(world.registry, stamp.note, stamp.x, stamp.y, stamp.w, Journal.hasNote(world, stamp.note), emphasis)
  end
  for _, node in ipairs(region.nodes) do
    self:drawNode(node)
  end
end

function JournalScene:drawMap()
  local r, scale = self.mapRect, self.app.view.scale
  love.graphics.setColor(COLOR.mapBg)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
  local search = self.spec.search
  if self.nav.field then
    self.field:draw(
      self.nav.field,
      { placeholder = search.labels.placeholder, pad = search.textPad, blink = search.caretBlink }
    )
  end
  if self.nav.clear then
    Overview.drawClear(self.nav, self.spec)
  end
  Overview.drawChips(self.nav, self.spec)
  if self.nav.list then
    Overview.drawResults(self.nav, self.resultData, self.spec, scale)
  elseif self.nav.view == "focus" then
    Focus.draw(self, self.nav, self.spec)
  else
    Overview.draw(self.nav, { chapters = self.chapters, stats = self.stats }, self.spec, scale)
  end
  love.graphics.setColor(theme.colors.panelBorder)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
end

function JournalScene:drawQueue()
  local world, colors = self.world, theme.colors
  local dim = colors.textDim
  local size = world.tuning.study.queueSize
  local queue = Journal.queue(world)
  local q = self.queueRect
  Text.draw(
    string.format("Studying at night (%d/%d)", #queue, size),
    q.x,
    self.box.y + TITLE_PAD,
    { size = "small", color = dim }
  )
  if #queue == 0 then
    local ideas = #Journal.ideas(world) > 0
    love.graphics.setColor(ideas and colors.accent or colors.panelBorder)
    NodeView.dashedRect(q.x, q.y, q.w, q.h, 4, 3)
    local prompt = ideas and "Nothing queued. Tap an idea on the map to study it tonight."
      or "Nothing to study yet. Tap a ??? on the map to see what to do."
    local th = Text.wrappedHeight(prompt, "small", q.w - 16)
    Text.draw(
      prompt,
      q.x + 8,
      q.y + (q.h - th) / 2,
      { size = "small", width = q.w - 16, color = ideas and colors.accent or dim }
    )
    return
  end
  for slot, chip in ipairs(self.chips) do
    local def = Journal.node(world, chip.id)
    love.graphics.setColor(colors.button)
    love.graphics.rectangle("fill", chip.x, chip.y, chip.w, chip.h, 3, 3)
    love.graphics.setColor(
      chip.id == self.selected and colors.text or (slot == 1 and colors.accent or colors.panelBorder)
    )
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", chip.x + 0.5, chip.y + 0.5, chip.w - 1, chip.h - 1, 3, 3)
    Panel.icon(Panel.nodeIcon(world.registry, def), chip.x + 4, chip.y + 4)
    Text.draw(
      def.name,
      chip.x + 20,
      chip.y + 4,
      { size = "small", width = chip.w - 24, color = slot == 1 and colors.text or dim }
    )
    progressBar(
      chip.x + 4,
      chip.y + chip.h - 9,
      chip.w - 8,
      Journal.progress(world, chip.id),
      slot == 1 and colors.accent or dim
    )
  end
  for _, free in ipairs(self.freeSlots) do
    love.graphics.setColor(colors.panelBorder)
    NodeView.dashedRect(free.x, free.y, free.w, free.h, 3, 3)
    Text.draw("Free slot", free.x, free.y + (free.h - select(2, Text.measure("A", "small"))) / 2, {
      size = "small",
      color = dim,
      width = free.w,
      align = "center",
    })
  end
end

function JournalScene:drawNotes()
  local world, colors = self.world, theme.colors
  local n = self.notesRect
  local written = 0
  for _, note in ipairs(self.notes) do
    if Journal.hasNote(world, note.id) then
      written = written + 1
    end
  end
  Text.draw(string.format("Notes (%d/%d)", written, #self.notes), n.x, n.y, { size = "small", color = colors.textDim })
  for _, stamp in ipairs(self.noteStamps) do
    local earned = Journal.hasNote(world, stamp.note.id)
    NodeView.stamp(world.registry, stamp.note.id, stamp.x, stamp.y, stamp.w, earned, stamp.note.id == self.selectedNote)
  end
  local _, lineH = Text.measure("A", "small")
  local infoY = n.y + n.h - (n.w < 460 and 2 or 1) * lineH - 1
  if self.selectedNote then
    local note = world.registry:get("notes", self.selectedNote)
    local info = Journal.noteInfo(world, note.id)
    local text
    if info then
      text = string.format(
        "%s: %s (%s day %d, run %d)",
        note.name,
        note.line,
        capitalize(info.season),
        info.day,
        info.run or 1
      )
    else
      text = note.name .. ": not written yet. " .. note.hint .. "."
    end
    Text.draw(text, n.x, infoY, { size = "small", width = n.w })
  else
    Text.draw("Tap a stamp to read it.", n.x, infoY, { size = "small", color = colors.textDim })
  end
end

function JournalScene:drawCard()
  local world, colors = self.world, theme.colors
  local c = self.cardRect
  local id = self.selected
  local def = Journal.node(world, id)
  local status = Journal.status(world, id)
  local kind = Journal.kindOf(world, id)
  local dim = colors.textDim

  love.graphics.setColor(colors.panel)
  love.graphics.rectangle("fill", c.x, c.y, c.w, c.h, 4, 4)
  love.graphics.setColor(status == "known" and COLOR.ink or colors.accent)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", c.x + 0.5, c.y + 0.5, c.w - 1, c.h - 1, 4, 4)

  local iconId = Panel.nodeIcon(world.registry, def)
  if status == "unknown" then
    Panel.icon(iconId, c.x + 8, c.y + 8, 0.55, ICON_SCALE, SILHOUETTE)
  elseif status == "idea" then
    Panel.icon(iconId, c.x + 8, c.y + 8, 0.75, ICON_SCALE, SKETCH)
  else
    Panel.icon(iconId, c.x + 8, c.y + 8, 1, ICON_SCALE)
  end

  local textX = c.x + 38
  local label = ({
    known = kind == "perks" and "Known · perk" or "Known",
    idea = "Idea",
    queued = "Queued",
    studying = "Studying",
    unknown = "Unknown",
  })[status]
  local statusW = 74
  Text.draw(label, c.x + c.w - statusW - 8, c.y + 8, {
    size = "small",
    width = statusW,
    align = "right",
    color = (status == "idea" or status == "studying") and colors.accent or dim,
  })
  Text.draw(
    status == "unknown" and "???" or def.name,
    textX,
    c.y + 7,
    { size = "body", width = c.w - 38 - statusW - 12 }
  )
  -- An unknown node keeps its name hidden but says what to do (D72, #160).
  local line = status == "unknown" and (self:unlockText(id) or "Write the missing notes to learn this.") or def.line
  Text.draw(
    line,
    textX,
    c.y + CARD_TEXT_TOP,
    { size = "small", width = c.w - CARD_TEXT_X - 8, color = status == "unknown" and colors.accent or dim }
  )

  -- Needed note stamps (filled once written), then study time and price.
  for _, stamp in ipairs(self.cardStamps) do
    NodeView.stamp(
      world.registry,
      stamp.note,
      stamp.x,
      stamp.y,
      stamp.w,
      Journal.hasNote(world, stamp.note),
      stamp.note == self.selectedNote
    )
  end
  if status ~= "unknown" then
    local parts = {}
    if def.studyNights and status ~= "known" then
      local progress = Journal.progress(world, id) * def.studyNights
      parts[#parts + 1] = progress > 0 and string.format("%.1f/%s", progress, nights(def.studyNights))
        or nights(def.studyNights)
    end
    if kind == "catalog" then
      parts[#parts + 1] = "$" .. (status == "known" and Market.itemPrice(world, id) or def.price)
    else
      parts[#parts + 1] = "perk"
    end
    local _, th = Text.measure("A", "small")
    Text.draw(table.concat(parts, " · "), (self.cardStampsRight or c.x + 8) + 2, c.y + c.h - 6 - 22 + (22 - th) / 2, {
      size = "small",
      color = dim,
    })
  end
  self.cardButtons:draw()
end

function JournalScene:draw()
  local b, world = self.box, self.world
  Panel.frame(self.app.view, b, "Field Journal", "Notes spark ideas. Study them at night.")
  self.buttons:draw()
  self:drawQueue()
  self:drawMap()
  self:drawNotes()
  if self.selected then
    self:drawCard()
  end
  -- Money matters for Order; the catalog shows it in its subtitle, here it sits beside the title.
  Text.draw(string.format("$%d", Ledger.get(world, "money")), b.x, b.y + 9, {
    size = "small",
    color = theme.colors.textDim,
    width = b.w - (b.hosted and 12 or 70), -- a hosted page has no Close button to leave room for
    align = "right",
  })
end

return JournalScene
