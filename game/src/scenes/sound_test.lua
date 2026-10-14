-- Sound test (GDD D100, #48): lists every cue in data/content/sounds.lua with a Play button, so the
-- placeholders and any replacement files can be auditioned. Opened from Settings and with F7.
-- Touch-sized rows on the shared ScrollList kit; loops toggle Loop / Stop.

local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Layout = require("src.ui.settings_layout")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local SoundTest = { name = "soundtest", opaque = true }
SoundTest.__index = SoundTest

local ROW_GAP = 6 -- virtual pixels between rows
local PLAY_W = 56 -- virtual pixels; width of the Play / Stop button
local HEADING_H = 20 -- virtual pixels per bus heading

function SoundTest.new()
  return setmetatable({ list = ScrollList.new() }, SoundTest)
end

function SoundTest:enter()
  local minSize = self.app.ctx.tuning.input.minTouchTarget
  self.buttons = Buttons.new(minSize)
  self.rowButtons = Buttons.new(minSize)
  self.list.onMove = function()
    self:layout()
  end
end

function SoundTest:resize()
  self:layout()
end

function SoundTest:exit()
  local audio = self.app.ctx.audio
  if audio.audition then
    audio:toggleLoop(audio.audition)
  end
end

function SoundTest:layout()
  local app = self.app
  local tuning = app.ctx.tuning
  local audio = app.ctx.audio
  local minTouch = tuning.input.minTouchTarget
  local P = Layout.panel(app.view, tuning.settings, minTouch)
  self.box = P.box
  self.buttons:clear()
  self.rowButtons:clear()
  self.items = {}
  local ctrlH = Layout.controlH(minTouch)
  local innerW = P.list.w - 2 * Layout.PAD - tuning.ui.scrollBarWidth - 4
  local x0 = P.list.x + Layout.PAD
  local textW = innerW - PLAY_W - 6

  local y, lastBus = 0, nil
  for _, id in ipairs(audio.library:ids()) do
    local def = audio.sounds.cues[id]
    if def.bus ~= lastBus then
      lastBus = def.bus
      self.items[#self.items + 1] = { heading = def.bus, y = y, h = HEADING_H }
      y = y + HEADING_H
    end
    local detail = string.format("%s: %s", audio.library:describe(id), def.where)
    local h = math.max(ctrlH, 14 + Text.wrappedHeight(detail, "small", textW))
    self.items[#self.items + 1] = { id = id, def = def, detail = detail, y = y, h = h }
    y = y + h + ROW_GAP
  end

  self.window = self.list:fit(P.list, y, tuning.ui.scrollHintHeight, ctrlH)
  local top = self.list:origin()
  for _, item in ipairs(self.items) do
    item.ay = top + item.y
    item.visible = self.list:visible(item.ay, item.h)
    if item.id and item.visible then
      local id, def = item.id, item.def
      local playing = def.loop and audio.audition == id
      self.rowButtons:add({
        x = x0 + innerW - PLAY_W,
        y = item.ay,
        w = PLAY_W,
        h = ctrlH,
        label = def.loop and (playing and "Stop" or "Loop") or "Play",
        selected = playing,
        onPress = function()
          if def.loop then
            audio:toggleLoop(id)
          else
            audio:play(id, { force = true })
          end
          self:layout()
        end,
      })
    end
  end
  self.buttons:add({
    x = P.done.x,
    y = P.done.y,
    w = P.done.w,
    h = P.done.h,
    label = "Done",
    style = "accent",
    onPress = function()
      self.app:pop()
    end,
  })
end

function SoundTest:action(name, data)
  if name == "press" or name == "release" then
    self.list:action(name, data)
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
  elseif name == "cancel" then
    self.app:pop()
  elseif self.list:action(name, data, self.app.ctx.tuning.ui) then
    self:layout()
  end
  return true
end

function SoundTest:draw()
  local ctx = self.app.ctx
  local b = self.box
  Draw.panel(b.x, b.y, b.w, b.h)
  Text.draw("Sound test", b.x + Layout.PAD, b.y + 8, { size = "heading" })
  self.list:begin(self.app.view.scale)
  local x0 = b.x + Layout.PAD
  local innerW = b.w - 2 * Layout.PAD - ctx.tuning.ui.scrollBarWidth - 4
  for _, item in ipairs(self.items) do
    if item.visible then
      if item.heading then
        Text.draw(item.heading, x0, item.ay + 4, { size = "body", color = theme.colors.accent })
      else
        Text.draw(item.id, x0, item.ay, { size = "body", width = innerW - PLAY_W - 6 })
        Text.draw(
          item.detail,
          x0,
          item.ay + 14,
          { size = "small", width = innerW - PLAY_W - 6, color = theme.colors.textDim }
        )
      end
    end
  end
  self.rowButtons:draw()
  self.list:finish()
  self.list:drawCue(ctx.tuning.ui)
  self.buttons:draw()
end

return SoundTest
