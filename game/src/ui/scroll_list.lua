-- The shared scroll kit for panel lists (D87, #8, #184). One ScrollList per scrolling list: it owns the
-- offset, fits the list into its window (reserving a hint line when content overflows), takes the
-- input actions (drag, two-finger drag, arrow keys and W/S arrive as `pan`; the wheel and +/- as `zoom`),
-- clips drawing to the window and draws the thumb and the "Drag or scroll" hint. The pixel maths live in
-- src/ui/scroll.lua. Panels lay rows out from `origin()` (window top minus the offset), only add buttons
-- for rows in view, and let buttons answer only where `contains` says the window is.

local Scroll = require("src.ui.scroll")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local ScrollList = {}
ScrollList.__index = ScrollList

function ScrollList.new(onMove)
  return setmetatable({ offset = 0, contentH = 0, overflow = false, onMove = onMove, view = { x = 0, y = 0, w = 0, h = 0 } }, ScrollList)
end

--- Fit the list into `rect` ({x, y, w, h}, the whole space the list may use, hint line included) for
--- content `contentH` tall. `hintH` pixels are kept under the window when content overflows. Returns
--- the window rect ({x, y, w, h}); the offset is clamped into range.
function ScrollList:fit(rect, contentH, hintH, minH)
  local viewH = math.max(minH or 1, rect.h)
  self.overflow = Scroll.overflows(contentH, viewH)
  if self.overflow then
    viewH = math.max(minH or 1, viewH - (hintH or 0))
    self.overflow = Scroll.overflows(contentH, viewH)
  end
  self.contentH = contentH
  self.view = { x = rect.x, y = rect.y, w = rect.w, h = viewH }
  self.offset = Scroll.clamp(self.offset, contentH, viewH)
  return self.view
end

--- Where content row 0 sits on screen (rows are laid out downwards from here).
function ScrollList:origin()
  return self.view.y - self.offset
end

--- Is the point inside the window (buttons of half-scrolled rows must not answer outside it)?
function ScrollList:contains(x, y)
  local v = self.view
  return x ~= nil and x >= v.x and x < v.x + v.w and y >= v.y and y < v.y + v.h
end

--- Is the content row spanning [y, y + h) (screen pixels, as laid out from origin()) at all in view?
function ScrollList:visible(y, h)
  return y + h > self.view.y and y < self.view.y + self.view.h
end

--- Scroll so that the content span [top, top + h) (content pixels from the list start) is in view.
function ScrollList:reveal(top, h)
  local v = self.view
  if top < self.offset then
    self.offset = top
  elseif top + h > self.offset + v.h then
    self.offset = top + h - v.h
  end
  self.offset = Scroll.clamp(self.offset, self.contentH, v.h)
end

-- Lists that are being dragged or coasting after a drag (D94, #223). ScrollList.tick(dt, ui) moves them
-- once a frame; a list leaves the set when it has stopped.
local live = {}

--- Feed an input action. Returns true when the offset changed (the panel should lay out again).
--- `ui` is tuning.ui (a bare number is read as tuning.ui.scrollWheelStep, with no page overlap).
--- Actions: pan (drag, arrow keys), zoom (wheel), pageUp / pageDown, listHome / listEnd, press (stops a
--- coast), release (a drag that ends moving lets the list coast, see tick).
function ScrollList:action(name, data, ui)
  local step = type(ui) == "table" and ui.scrollWheelStep or ui
  local overlap = type(ui) == "table" and ui.scrollPageOverlap or 0
  if name == "press" then
    self.coast, self.dragging = nil, false
  elseif name == "release" then
    if self.dragging then
      self.released = true
    end
  end
  if not self.overflow then
    return false
  end
  local before, v = self.offset, self.view
  if name == "pan" then
    self.offset = Scroll.byDrag(self.offset, data.dy, self.contentH, v.h)
    if not data.keys then
      self.coast = nil
      self.dragging = true
      self.dragAcc = (self.dragAcc or 0) + data.dy
      live[self] = true
    end
  elseif name == "zoom" then
    self.offset = Scroll.byWheel(self.offset, data.steps, step, self.contentH, v.h)
  elseif name == "pageUp" or name == "pageDown" then
    local page = math.max(1, v.h - overlap)
    self.offset = Scroll.clamp(self.offset + (name == "pageDown" and page or -page), self.contentH, v.h)
  elseif name == "listHome" then
    self.offset = 0
  elseif name == "listEnd" then
    self.offset = Scroll.max(self.contentH, v.h)
  end
  if self.offset ~= before and name ~= "pan" and name ~= "zoom" then
    self.coast = nil -- a jump ends any coast
  end
  return self.offset ~= before
end

--- Move every list that is being dragged or coasting by `dt` seconds (call once a frame; `ui` is
--- tuning.ui). While a finger drags, the average drag speed is tracked; when it lifts while still moving
--- the list coasts at that speed, slowing by flingFriction, and stops cleanly at an end or under
--- flingStopSpeed. Time comes only from `dt`, so the same input and frames always give the same offsets.
function ScrollList.tick(dt, ui)
  for list in pairs(live) do
    local moved = false
    if list.dragging then
      if (list.dragAcc or 0) ~= 0 and dt > 0 then
        local sample = list.dragAcc / dt
        list.speed = list.speed and (list.speed + (sample - list.speed) * ui.flingBlend) or sample
        list.dragAcc, list.still = 0, 0
      else
        list.still = (list.still or 0) + dt
      end
      if list.released then
        local fast = math.abs(list.speed or 0) >= ui.flingMinSpeed and (list.still or 0) <= ui.flingStaleTime
        list.coast = fast and math.max(-ui.flingMaxSpeed, math.min(ui.flingMaxSpeed, list.speed)) or nil
        list.dragging, list.released, list.speed, list.dragAcc, list.still = false, false, nil, 0, 0
      end
    elseif list.coast then
      local before = list.offset
      list.offset = Scroll.byDrag(list.offset, list.coast * dt, list.contentH, list.view.h)
      moved = list.offset ~= before
      list.coast = list.coast * math.exp(-ui.flingFriction * dt)
      if math.abs(list.coast) < ui.flingStopSpeed or not moved then
        list.coast = nil -- slow enough, or against an end
      end
    end
    if not list.dragging and not list.coast then
      live[list] = nil
    end
    if moved and list.onMove then
      list.onMove(list)
    end
  end
end

--- Clip drawing to the window until finish() (scissor works in screen pixels, so it needs the view scale).
function ScrollList:begin(scale)
  local v = self.view
  love.graphics.setScissor(math.floor(v.x * scale), math.floor(v.y * scale), math.ceil(v.w * scale), math.ceil(v.h * scale))
end

function ScrollList:finish()
  love.graphics.setScissor()
end

--- The thumb down the right edge of the window and the hint line under it (only while overflowing).
--- `ui` is tuning.ui.
function ScrollList:drawCue(ui)
  if not self.overflow then
    return
  end
  local v = self.view
  local at, h = Scroll.thumb(self.offset, self.contentH, v.h, v.h, ui.scrollHintHeight)
  local barW = ui.scrollBarWidth
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", v.x + v.w - barW - 2, v.y, barW, v.h, 1, 1)
  love.graphics.setColor(theme.colors.accent)
  love.graphics.rectangle("fill", v.x + v.w - barW - 2, v.y + at, barW, h, 1, 1)
  local above, below = Scroll.hidden(self.offset, self.contentH, v.h)
  local parts = {}
  if above > 0 then
    parts[#parts + 1] = "^ more above"
  end
  if below > 0 then
    parts[#parts + 1] = "v more below"
  end
  Text.draw("Drag or scroll: " .. table.concat(parts, ", "), v.x + 12, v.y + v.h + 2, {
    size = "small",
    color = theme.colors.textDim,
  })
end

--- Just the thumb, for a window with no room for a hint line (the toolbar palette): drawn inside `track`
--- ({x, y, w, h}, default the window), `barW` wide at its right edge.
function ScrollList:drawThumb(barW, minH, track)
  if not self.overflow then
    return
  end
  local t = track or self.view
  local at, h = Scroll.thumb(self.offset, self.contentH, self.view.h, t.h, minH)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", t.x + t.w - barW, t.y, barW, t.h, 1, 1)
  love.graphics.setColor(theme.colors.accent)
  love.graphics.rectangle("fill", t.x + t.w - barW, t.y + at, barW, h, 1, 1)
end

return ScrollList
