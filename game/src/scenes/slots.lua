-- Save slot selection (GDD §7.11): play, create, rename, or delete one of the slots.

local Save = require("src.core.save")
local Run = require("src.meta.run")
local Ftue = require("src.sim.systems.ftue")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Slots = { name = "slots", opaque = true }
Slots.__index = Slots

local CARD_H = 56
local CARD_GAP = 8
local TOP = 48

function Slots.new()
  return setmetatable({}, Slots)
end

function Slots:enter()
  self.buttons = Buttons.new(self.app.ctx.tuning.input.minTouchTarget)
  self:refresh()
end

function Slots:resume()
  self:refresh()
end

function Slots:refresh()
  self.slots = self.app.ctx.store:list()
  if self.app.view.w > 0 then
    self:resize(self.app.view)
  end
end

local function capitalize(s)
  return (s:gsub("^%l", string.upper))
end

local function describe(slot)
  if slot.state == "empty" then
    return "Empty slot", ""
  elseif slot.state == "corrupt" then
    return "Unreadable save", tostring(slot.error)
  elseif slot.state == "outdated" then
    return string.format("From %s version: can't be loaded", slot.compat == "newer" and "a newer" or "an older"), ""
  end
  local h = slot.header
  local when = "New homestead"
  if h.recovering then
    when = "Recovering in town"
  elseif h.year and h.season then
    when = string.format("Year %d · %s", h.year, capitalize(h.season))
  end
  return when, "Played " .. Draw.formatPlaytime(h.playtime)
end

--- The words of the out-of-date prompt (D74) for a slot summary or its data: title, message.
function Slots.outdatedText(name, compat)
  local which = compat == "newer" and "a newer" or "an older"
  return "Can't load " .. (name or "this save"),
    "This save is from " .. which .. " version and can't be loaded. Delete it to use the slot again, "
      .. "or keep it: the file stays exactly as it is."
end

--- An out-of-date slot: say so, then Delete save (asks again) or Keep it (nothing is touched). Never
--- deletes by itself (D74, #183).
function Slots:outdated(index, name, compat)
  local title, message = Slots.outdatedText(name, compat)
  self.app:push(require("src.scenes.confirm").new({
    title = title,
    message = message,
    confirmLabel = "Delete save",
    cancelLabel = "Keep it",
    danger = true,
    onConfirm = function()
      self:delete(index, name)
    end,
  }))
end

function Slots:play(index, data)
  local compat = Save.compatibility(data)
  if compat ~= "ok" then
    self:outdated(index, data.name, compat)
    return
  end
  if Run.isRecovering(data) then
    self.app:switch(require("src.scenes.recovery").new(), index, data)
    return
  end
  self.app:switch(require("src.scenes.homestead").new(), index, data)
end

function Slots:newSlot(index)
  local tuning = self.app.ctx.tuning
  self.app:push(require("src.scenes.prompt").new({
    title = "Name your homestead",
    initial = tuning.save.defaultSlotName,
    maxLength = tuning.save.maxNameLength,
    confirmLabel = "Start",
    onConfirm = function(name)
      local data = Save.newSlotData(name)
      Ftue.begin(data.meta, self.app.ctx.tips ~= false) -- a new slot gets the tip cards (D69); tools may turn them off
      self:play(index, data)
    end,
  }))
end

function Slots:rename(index)
  local store = self.app.ctx.store
  local data = store:read(index)
  if not data then
    return
  end
  self.app:push(require("src.scenes.prompt").new({
    title = "Rename homestead",
    initial = data.name,
    maxLength = self.app.ctx.tuning.save.maxNameLength,
    onConfirm = function(name)
      data.name = name
      store:write(index, data)
      self:refresh()
    end,
  }))
end

function Slots:delete(index, name)
  self.app:push(require("src.scenes.confirm").new({
    title = "Delete " .. (name or "this slot") .. "?",
    message = "This erases the homestead and everything learned in its Field Journal.",
    confirmLabel = "Delete",
    danger = true,
    onConfirm = function()
      self.app.ctx.store:delete(index)
      self:refresh()
    end,
  }))
end

function Slots:resize(view)
  if not self.slots then
    return
  end
  self.buttons:clear()
  self.buttons:add({
    x = 8,
    y = 8,
    w = 56,
    h = 24,
    label = "Back",
    onPress = function()
      self.app:switch(require("src.scenes.title").new())
    end,
  })
  local cardW = math.min(440, view.w - 24)
  local cardX = (view.w - cardW) / 2
  self.cards = {}
  for i, slot in ipairs(self.slots) do
    local y = TOP + (i - 1) * (CARD_H + CARD_GAP)
    self.cards[i] = { x = cardX, y = y, w = cardW, h = CARD_H, slot = slot }
    local bw, bh = 60, 24
    local by = y + (CARD_H - bh) / 2
    local right = cardX + cardW - 10
    local function add(label, style, onPress)
      right = right - bw
      self.buttons:add({ x = right, y = by, w = bw, h = bh, label = label, style = style, onPress = onPress })
      right = right - 6
    end
    if slot.state == "ok" then
      add("Delete", "danger", function()
        self:delete(i, slot.name)
      end)
      add("Rename", nil, function()
        self:rename(i)
      end)
      add("Play", "accent", function()
        local data = self.app.ctx.store:read(i)
        if data then
          self:play(i, data)
        end
      end)
    elseif slot.state == "outdated" then
      add("Play", "accent", function()
        self:outdated(i, slot.name, slot.compat)
      end)
    elseif slot.state == "empty" then
      add("New", "accent", function()
        self:newSlot(i)
      end)
    else
      add("Delete", "danger", function()
        self:delete(i)
      end)
    end
  end
end

function Slots:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  if name == "cancel" then
    self.app:switch(require("src.scenes.title").new())
    return true
  end
  return false
end

function Slots:draw()
  local view = self.app.view
  Text.draw("Choose a homestead", 0, 14, { size = "heading", width = view.w, align = "center" })
  for _, card in ipairs(self.cards or {}) do
    Draw.panel(card.x, card.y, card.w, card.h)
    local slot = card.slot
    local line1, line2 = describe(slot)
    local title = slot.name or ("Slot " .. slot.index)
    Text.draw(title, card.x + 12, card.y + 10, {
      size = "heading",
      color = slot.state == "ok" and theme.colors.text or theme.colors.textDim,
    })
    Text.draw(line1 .. (line2 ~= "" and ("   " .. line2) or ""), card.x + 12, card.y + 34, {
      size = "small",
      color = theme.colors.textDim,
    })
  end
  self.buttons:draw()
end

return Slots
