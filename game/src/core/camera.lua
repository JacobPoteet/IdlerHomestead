-- World camera: pan/zoom over the homestead and grid <-> world <-> view conversion.
--
-- Spaces:
--   tile  : 1-based grid coordinates (the sim only knows these)
--   world : pixels in source-art scale (tile * tileSize)
--   view  : virtual pixels on screen (what scenes and input use)
-- Projection lives here and in rendering only, so a different view (e.g. isometric) is a
-- renderer change, not a sim change (GDD §9.1).

local Camera = {}
Camera.__index = Camera

--- opts: { tileSize, zoomLevels, zoomIndex }
function Camera.new(opts)
  return setmetatable({
    x = 0, -- world point at the centre of the view
    y = 0,
    tileSize = opts.tileSize,
    zoomLevels = opts.zoomLevels,
    zoomIndex = opts.zoomIndex,
    boundsW = nil,
    boundsH = nil,
  }, Camera)
end

function Camera:zoom()
  return self.zoomLevels[self.zoomIndex]
end

--- Limit panning to a world rectangle (0,0)-(w,h).
function Camera:setBounds(w, h)
  self.boundsW, self.boundsH = w, h
end

function Camera:clamp(view)
  if not self.boundsW then
    return
  end
  local z = self:zoom()
  local halfW, halfH = view.w / (2 * z), view.h / (2 * z)
  if self.boundsW <= halfW * 2 then
    self.x = self.boundsW / 2
  else
    self.x = math.max(halfW, math.min(self.boundsW - halfW, self.x))
  end
  if self.boundsH <= halfH * 2 then
    self.y = self.boundsH / 2
  else
    self.y = math.max(halfH, math.min(self.boundsH - halfH, self.y))
  end
end

function Camera:centerOn(wx, wy, view)
  self.x, self.y = wx, wy
  self:clamp(view)
end

--- Pan by a view-space delta (the content follows the pointer).
function Camera:pan(dx, dy, view)
  local z = self:zoom()
  self.x = self.x - dx / z
  self.y = self.y - dy / z
  self:clamp(view)
end

--- Step zoom keeping the world point under (vx, vy) fixed on screen.
function Camera:zoomBy(steps, vx, vy, view)
  local newIndex = math.max(1, math.min(#self.zoomLevels, self.zoomIndex + steps))
  if newIndex == self.zoomIndex then
    return
  end
  local wx, wy = self:viewToWorld(vx, vy, view)
  self.zoomIndex = newIndex
  local z = self:zoom()
  self.x = wx - (vx - view.w / 2) / z
  self.y = wy - (vy - view.h / 2) / z
  self:clamp(view)
end

function Camera:viewToWorld(vx, vy, view)
  local z = self:zoom()
  return (vx - view.w / 2) / z + self.x, (vy - view.h / 2) / z + self.y
end

function Camera:worldToView(wx, wy, view)
  local z = self:zoom()
  return (wx - self.x) * z + view.w / 2, (wy - self.y) * z + view.h / 2
end

--- World pixel -> 1-based tile coordinates.
function Camera:worldToTile(wx, wy)
  return math.floor(wx / self.tileSize) + 1, math.floor(wy / self.tileSize) + 1
end

--- Top-left world pixel of a tile.
function Camera:tileToWorld(tx, ty)
  return (tx - 1) * self.tileSize, (ty - 1) * self.tileSize
end

--- Visible tile range (inclusive), for culling.
function Camera:visibleTiles(view)
  local x1, y1 = self:viewToWorld(0, 0, view)
  local x2, y2 = self:viewToWorld(view.w, view.h, view)
  local tx1, ty1 = self:worldToTile(x1, y1)
  local tx2, ty2 = self:worldToTile(x2, y2)
  return tx1, ty1, tx2, ty2
end

--- Apply the camera transform for drawing in world pixels. Rounds the translation to whole
--- screen pixels so pixel art stays crisp. Pair with love.graphics.pop().
function Camera:attach(view)
  local s = view.scale * self:zoom()
  love.graphics.push()
  love.graphics.origin()
  local tx = math.floor(view.w * view.scale / 2 - self.x * s + 0.5)
  local ty = math.floor(view.h * view.scale / 2 - self.y * s + 0.5)
  love.graphics.translate(tx, ty)
  love.graphics.scale(s)
end

return Camera
