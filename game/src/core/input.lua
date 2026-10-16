-- Input abstraction (GDD §10): turns raw mouse/touch/keyboard events into actions so gameplay
-- code never cares which device is used. Coordinates in action data are virtual pixels.
--
-- Actions sent to app:action(name, data):
--   press   {x, y}        pointer went down (left mouse / single touch)
--   release {x, y}        pointer went up
--   select  {x, y}        tap / left click that didn't turn into a drag or long-press
--   context {x, y}        right click / long-press
--   pan     {dx, dy}      drag, two-finger drag, middle/right drag, or arrow keys / WASD
--   zoom    {steps, x, y} mouse wheel, pinch, or +/- keys (x, y = anchor point)
--   hover   {x, y}        mouse moved with no button (desktop only; never required by UI)
--   cancel  {}            Escape / Android back
--   speed   {}            Space: cycle the game speed (the on-screen button does the same)
--   routine {}            R: start the idle routine now
--   wheelOpen {x, y}      hold right click, a right drag, or a long-press, where the top scene wants the
--                         tool wheel there (scene:wantsWheel(x, y), D138); a quick right click is still `context`
--   wheelMove {x, y}      the pointer moved while the wheel is held open
--   wheelRelease {x, y}   the pointer let go of a held wheel (the scene equips what it points at)
--   toolWheel, tool1..tool6 {}   keys: open the wheel, equip a tool directly
--
-- Also tracks the time of the last real input for idle takeover (GDD §5.2).

local strict = require("src.core.strict")
local KeyBindings = require("src.core.key_bindings")

local Input = {}
Input.__index = Input

-- Key bindings (keyActions, panKeys, zoomKeys) live in data/tuning/input.lua. The player's rebinds
-- (settings file) are merged over keyActions by src/core/key_bindings.lua into `keyMap`.

function Input.new(app, tuning)
  return setmetatable({
    app = app,
    tuning = tuning,
    pointer = nil, -- { x, y, startX, startY, startTime, dragging, longFired, button }
    touches = {}, -- id -> { x, y }
    touchOrder = {},
    pinch = nil, -- { refDist, midX, midY }
    lastActivity = love.timer.getTime(),
    keyMap = KeyBindings.keyMap(tuning.input, nil), -- key -> action name actually in force
    capture = nil, -- function(key) taking the next key press instead of the game (rebinding)
  }, Input)
end

--- Use these key overrides ({ action = key }, from the settings) from now on.
function Input:setKeyOverrides(overrides)
  self.keyMap = KeyBindings.keyMap(self.tuning.input, overrides)
end

--- Capture mode (Settings > Controls): the next key press goes to fn(key) and does nothing else, so
--- pressing a key to bind it never fires its action. Cancelled by Input:endCapture().
function Input:beginCapture(fn)
  self.capture = fn
end

function Input:endCapture()
  self.capture = nil
end

--- Record real input for the idle takeover timer. Input while a browse panel (catalog, journal ...)
--- is on top is not directing the homesteader, so it does not count (GDD D54).
function Input:activity(px, py)
  local top = self.app.top and self.app:top()
  if top and px and top.ignoresActivityAt then
    -- A tip card tap is reading, not directing the homesteader (D69).
    local vx, vy = self.app:toVirtual(px, py)
    if top:ignoresActivityAt(vx, vy) then
      return
    end
  end
  if top then
    for _, name in ipairs(self.tuning.idle.browsePanels) do
      if top.name == name then
        return
      end
    end
  end
  self.lastActivity = love.timer.getTime()
end

--- Stop the idle clock for `dt` seconds (game time stands still in town, D78): the idle seconds stay
--- where they were.
function Input:holdIdle(dt)
  self.lastActivity = math.min(love.timer.getTime(), self.lastActivity + dt)
end

--- Seconds since the player last gave any input.
function Input:idleSeconds()
  return love.timer.getTime() - self.lastActivity
end

function Input:emit(name, data)
  return self.app:action(name, data or {})
end

-- Pointer gestures (shared by mouse button 1 and single touch) -------------------------

function Input:pointerDown(px, py, button)
  local x, y = self.app:toVirtual(px, py)
  self.pointer = {
    x = x,
    y = y,
    startX = x,
    startY = y,
    startTime = love.timer.getTime(),
    dragging = false,
    longFired = false,
    button = button,
  }
  local top = self.app.top and self.app:top()
  -- A right press or a long-press on a scene that hosts the tool wheel can open it (D138).
  self.pointer.wheelable = top ~= nil and top.wantsWheel ~= nil and top:wantsWheel(x, y) == true
  if button == 1 then
    self:emit("press", { x = x, y = y })
  end
end

--- Open the tool wheel for the held pointer (D138), at the point where it went down.
function Input:openWheel(p)
  p.wheel = true
  p.longFired = true
  self:emit("wheelOpen", { x = p.startX, y = p.startY })
end

function Input:pointerMove(px, py)
  local p = self.pointer
  if not p then
    return
  end
  local x, y = self.app:toVirtual(px, py)
  if p.wheel then
    p.x, p.y = x, y
    self:emit("wheelMove", { x = x, y = y })
    return
  end
  if not p.dragging then
    local dx, dy = x - p.startX, y - p.startY
    if dx * dx + dy * dy >= self.tuning.input.dragThreshold ^ 2 then
      if p.button == 2 and p.wheelable then
        -- A right drag is a flick on the wheel: it opens at once and chooses by direction (D138).
        self:openWheel(p)
        p.x, p.y = x, y
        self:emit("wheelMove", { x = x, y = y })
        return
      end
      p.dragging = true
    end
  end
  if p.dragging then
    self:emit("pan", { dx = x - p.x, dy = y - p.y })
  end
  p.x, p.y = x, y
end

function Input:pointerUp(px, py)
  local p = self.pointer
  if not p then
    return
  end
  self.pointer = nil
  local x, y = self.app:toVirtual(px, py)
  if p.button == 1 then
    self:emit("release", { x = x, y = y })
  end
  if p.wheel then
    self:emit("wheelRelease", { x = x, y = y })
    return
  end
  if p.dragging or p.longFired then
    return
  end
  if p.button == 1 then
    self:emit("select", { x = x, y = y })
  elseif p.button == 2 then
    self:emit("context", { x = x, y = y })
  end
end

-- Mouse ------------------------------------------------------------------------------

function Input:mousepressed(x, y, button, istouch)
  if istouch then
    return -- handled by the touch callbacks
  end
  self:activity(x, y)
  if not self.pointer then
    self:pointerDown(x, y, button)
  end
end

function Input:mousemoved(x, y, _, _, istouch)
  if istouch then
    return
  end
  self:activity(x, y)
  if self.pointer then
    self:pointerMove(x, y)
  else
    local vx, vy = self.app:toVirtual(x, y)
    self:emit("hover", { x = vx, y = vy })
  end
end

function Input:mousereleased(x, y, button, istouch)
  if istouch then
    return
  end
  self:activity(x, y)
  if self.pointer and self.pointer.button == button then
    self:pointerUp(x, y)
  end
end

function Input:wheelmoved(_, wy)
  self:activity()
  if wy ~= 0 then
    local mx, my = self.app:toVirtual(love.mouse.getPosition())
    self:emit("zoom", { steps = wy > 0 and 1 or -1, x = mx, y = my })
  end
end

-- Touch ------------------------------------------------------------------------------

local function distance(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

function Input:touchpressed(id, x, y)
  self:activity(x, y)
  self.touches[id] = { x = x, y = y }
  self.touchOrder[#self.touchOrder + 1] = id
  local count = #self.touchOrder
  if count == 1 then
    self:pointerDown(x, y, 1)
  elseif count == 2 then
    -- Second finger: abandon the tap/drag and start a pinch.
    self.pointer = nil
    local a, b = self.touches[self.touchOrder[1]], self.touches[self.touchOrder[2]]
    self.pinch = { refDist = math.max(1, distance(a, b)), midX = (a.x + b.x) / 2, midY = (a.y + b.y) / 2 }
  end
end

function Input:touchmoved(id, x, y)
  self:activity(x, y)
  local t = self.touches[id]
  if not t then
    return
  end
  t.x, t.y = x, y
  if self.pinch and #self.touchOrder >= 2 then
    local a, b = self.touches[self.touchOrder[1]], self.touches[self.touchOrder[2]]
    local midX, midY = (a.x + b.x) / 2, (a.y + b.y) / 2
    local scale = self.app.view.scale
    self:emit("pan", { dx = (midX - self.pinch.midX) / scale, dy = (midY - self.pinch.midY) / scale, pinch = true })
    self.pinch.midX, self.pinch.midY = midX, midY
    local ratio = distance(a, b) / self.pinch.refDist
    local step = self.tuning.camera.pinchStepRatio
    if ratio >= step or ratio <= 1 / step then
      local vx, vy = self.app:toVirtual(midX, midY)
      self:emit("zoom", { steps = ratio > 1 and 1 or -1, x = vx, y = vy })
      self.pinch.refDist = distance(a, b)
    end
  elseif self.pointer then
    self:pointerMove(x, y)
  end
end

function Input:touchreleased(id, x, y)
  self:activity(x, y)
  if not self.touches[id] then
    return
  end
  self.touches[id] = nil
  for i, tid in ipairs(self.touchOrder) do
    if tid == id then
      table.remove(self.touchOrder, i)
      break
    end
  end
  if self.pinch then
    if #self.touchOrder == 0 then
      self.pinch = nil
    end
  elseif self.pointer then
    self:pointerUp(x, y)
  end
end

-- Keyboard ---------------------------------------------------------------------------

function Input:keypressed(key)
  self:activity()
  if self.capture then
    local fn = self.capture
    self.capture = nil -- one key per capture; fn may begin another
    fn(key)
    return
  end
  local keys = self.tuning.input
  local action = strict.get(self.keyMap, key)
  local zoom = strict.get(keys.zoomKeys, key)
  if action then
    self:emit(action)
  elseif zoom then
    local view = self.app.view
    self:emit("zoom", { steps = zoom, x = view.w / 2, y = view.h / 2 })
  end
end

function Input:update(dt)
  local p = self.pointer
  local held = p and love.timer.getTime() - p.startTime or 0
  if p and p.button == 1 and not p.dragging and not p.longFired then
    if held >= self.tuning.input.longPressTime then
      if p.wheelable then
        self:openWheel(p) -- a long-press on the world opens the tool wheel (D138)
      else
        p.longFired = true
        self:emit("context", { x = p.x, y = p.y })
      end
    end
  elseif p and p.button == 2 and p.wheelable and not p.wheel and not p.dragging then
    if held >= self.tuning.ui.wheel.holdTime then
      self:openWheel(p) -- a held right click opens the tool wheel; a quicker one inspects
    end
  end
  local dx, dy = 0, 0
  for key, dir in pairs(self.tuning.input.panKeys) do
    if love.keyboard.isDown(key) then
      dx, dy = dx + dir[1], dy + dir[2]
    end
  end
  if dx ~= 0 or dy ~= 0 then
    self:activity()
    local speed = self.tuning.camera.keyPanSpeed * dt
    -- Content moves opposite to the view, like dragging it.
    self:emit("pan", { dx = -dx * speed, dy = -dy * speed, keys = true })
  end
end

return Input
