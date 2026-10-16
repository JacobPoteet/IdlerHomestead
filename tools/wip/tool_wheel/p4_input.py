def edit(p, pairs):
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert old in s, (p, old[:70])
        s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8", newline="\n").write(s)


edit("game/src/core/input.lua", [
    ('''--   cancel  {}            Escape / Android back
--   speed   {}            Space: cycle the game speed (the on-screen button does the same)
--   routine {}            R: start the idle routine now
''', '''--   cancel  {}            Escape / Android back
--   speed   {}            Space: cycle the game speed (the on-screen button does the same)
--   routine {}            R: start the idle routine now
--   wheelOpen {x, y}      hold right click, a right drag, or a long-press, where the top scene wants the
--                         tool wheel there (scene:wantsWheel(x, y), D138); a quick right click is still `context`
--   wheelMove {x, y}      the pointer moved while the wheel is held open
--   wheelRelease {x, y}   the pointer let go of a held wheel (the scene equips what it points at)
--   toolWheel, tool1..tool6 {}   keys: open the wheel, equip a tool directly
'''),
    ('''  if button == 1 then
    self:emit("press", { x = x, y = y })
  end
end''', '''  local top = self.app.top and self.app:top()
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
end'''),
    ('''  local x, y = self.app:toVirtual(px, py)
  if not p.dragging then
    local dx, dy = x - p.startX, y - p.startY
    if dx * dx + dy * dy >= self.tuning.input.dragThreshold ^ 2 then
      p.dragging = true
    end
  end
  if p.dragging then''', '''  local x, y = self.app:toVirtual(px, py)
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
  if p.dragging then'''),
    ('''  local x, y = self.app:toVirtual(px, py)
  if p.button == 1 then
    self:emit("release", { x = x, y = y })
  end
  if p.dragging or p.longFired then''', '''  local x, y = self.app:toVirtual(px, py)
  if p.button == 1 then
    self:emit("release", { x = x, y = y })
  end
  if p.wheel then
    self:emit("wheelRelease", { x = x, y = y })
    return
  end
  if p.dragging or p.longFired then'''),
    ('''  local p = self.pointer
  if p and p.button == 1 and not p.dragging and not p.longFired then
    if love.timer.getTime() - p.startTime >= self.tuning.input.longPressTime then
      p.longFired = true
      self:emit("context", { x = p.x, y = p.y })
    end
  end''', '''  local p = self.pointer
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
  end'''),
])

edit("game/data/tuning/input.lua", [
    ('''    ["end"] = "listEnd", -- jump to the bottom of the open panel list
  },
  rebindable = { "speed", "routine", "pageUp", "pageDown", "listHome", "listEnd" },''', '''    ["end"] = "listEnd", -- jump to the bottom of the open panel list
    q = "toolWheel", -- open the tool wheel at the middle of the view (D138; Tab is kept for text fields)
    ["1"] = "tool1", -- equip the Hand (the tool wheel's wedges, in tuning.ui.wheel.wedges order)
    ["2"] = "tool2", -- equip the Hoe
    ["3"] = "tool3", -- equip the Pail
    ["4"] = "tool4", -- equip the Axe
    ["5"] = "tool5", -- equip the Rod
    ["6"] = "tool6", -- equip the Hammer
  },
  rebindable = {
    "speed",
    "routine",
    "toolWheel",
    "tool1",
    "tool2",
    "tool3",
    "tool4",
    "tool5",
    "tool6",
    "pageUp",
    "pageDown",
    "listHome",
    "listEnd",
  },'''),
])
print("input ok")

edit("game/src/ui/controls_text.lua", [
    ('''  routine = { "Start routine", "Start the idle routine now" },
''', '''  routine = { "Start routine", "Start the idle routine now" },
  toolWheel = { "Tool wheel", "Open the tool wheel" },
  tool1 = { "Hand", "Take the Hand" },
  tool2 = { "Hoe", "Take the Hoe" },
  tool3 = { "Pail", "Take the Pail" },
  tool4 = { "Axe", "Take the Axe" },
  tool5 = { "Rod", "Take the Rod" },
  tool6 = { "Hammer", "Take the Hammer" },
'''),
])
print("controls ok")
