-- Keyboard focus over a screen of controls (docs/PLAN_WARDROBE_MENU.md §3.2): the controls are grouped in zones
-- (tabs, tiles, actions ...), in order from the top of the screen down. An arrow moves to the nearest control in
-- that direction inside the zone; at a zone's edge Up and Down jump to the next zone, Left and Right stop (no
-- wrap). Pure (no love.*): the scene lists the controls with their rectangles and draws the ring; this decides
-- where focus goes. Focus is shown only after a key press (`show`) and hidden again by the next pointer press.
--
-- An item is { id, zone, x, y, w, h }. Rectangles may be in content space (a scrolled list's rows before the
-- scroll offset): only their relative places matter.

local FocusGrid = {}
FocusGrid.__index = FocusGrid

--- `zones`: the zone names in order, top of the screen first (for example { "tabs", "tiles", "actions" }).
function FocusGrid.new(zones)
  return setmetatable({ zones = zones, items = {}, byId = {}, now = nil, visible = false }, FocusGrid)
end

--- Replace the controls. The focus stays on its control when that is still there, else it goes to the first one.
function FocusGrid:set(items)
  self.items, self.byId = items, {}
  for _, item in ipairs(items) do
    self.byId[item.id] = item
  end
  if not (self.now and self.byId[self.now]) then
    self.now = self:first()
  end
end

--- The id of the first control of the first zone that has any, or nil.
function FocusGrid:first()
  for _, zone in ipairs(self.zones) do
    for _, item in ipairs(self.items) do
      if item.zone == zone then
        return item.id
      end
    end
  end
  return nil
end

function FocusGrid:current()
  return self.now
end

--- The focused control's item ({ id, zone, x, y, w, h }), or nil.
function FocusGrid:item(id)
  return self.byId[id or self.now]
end

--- Put the focus on a control (no effect for an id that is not listed). It does not show the ring.
function FocusGrid:focus(id)
  if self.byId[id] then
    self.now = id
  end
end

--- Show or hide the focus ring.
function FocusGrid:show(on)
  self.visible = on == true
end

function FocusGrid:shown()
  return self.visible
end

local function centre(item)
  return item.x + item.w / 2, item.y + item.h / 2
end

--- The zone's controls.
function FocusGrid:inZone(zone)
  local out = {}
  for _, item in ipairs(self.items) do
    if item.zone == zone then
      out[#out + 1] = item
    end
  end
  return out
end

local DIRS = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }

-- The control nearest in direction `dir` from `cur` among `list`: it must lie beyond `cur` along the direction's
-- axis, and a sideways offset counts double so the straight neighbour wins over a nearer diagonal one.
local function nearest(list, cur, dir)
  local d = DIRS[dir]
  local cx, cy = centre(cur)
  local best, bestScore
  for _, item in ipairs(list) do
    if item ~= cur then
      local ix, iy = centre(item)
      local along = (ix - cx) * d[1] + (iy - cy) * d[2]
      if along > 0 then
        local across = math.abs((ix - cx) * d[2]) + math.abs((iy - cy) * d[1])
        local score = along + across * 2
        if not bestScore or score < bestScore then
          best, bestScore = item, score
        end
      end
    end
  end
  return best
end

-- The control of `list` nearest `x` among those in the top row (`top` true) or the bottom row.
local function enter(list, x, top)
  local edge
  for _, item in ipairs(list) do
    local _, iy = centre(item)
    if edge == nil or (top and iy < edge) or (not top and iy > edge) then
      edge = iy
    end
  end
  local best, bestDist
  for _, item in ipairs(list) do
    local ix, iy = centre(item)
    if math.abs(iy - edge) < 1 then
      local dist = math.abs(ix - x)
      if not bestDist or dist < bestDist then
        best, bestDist = item, dist
      end
    end
  end
  return best
end

--- Move the focus one step in `dir` ("left" | "right" | "up" | "down") and return the focused id. `prefer` maps a
--- zone name to the id to land on when Up or Down jumps into that zone (else the control nearest across).
function FocusGrid:move(dir, prefer)
  local cur = self.byId[self.now]
  if not cur then
    self.now = self:first()
    return self.now
  end
  local near = nearest(self:inZone(cur.zone), cur, dir)
  if near then
    self.now = near.id
    return self.now
  end
  if dir == "up" or dir == "down" then
    local at
    for n, zone in ipairs(self.zones) do
      if zone == cur.zone then
        at = n
      end
    end
    local step = dir == "down" and 1 or -1
    local n = at + step
    while self.zones[n] do
      local list = self:inZone(self.zones[n])
      if #list > 0 then
        local want = prefer and prefer[self.zones[n]]
        local target = want and self.byId[want] and self.byId[want].zone == self.zones[n] and self.byId[want]
        local x = centre(cur)
        self.now = (target or enter(list, x, dir == "down")).id
        return self.now
      end
      n = n + step
    end
  end
  return self.now
end

return FocusGrid
