-- The homestead view: runs the session and shows the map.
-- M0: a placeholder grid you can pan/zoom and tap tiles on. Land, actors and tasks arrive in M1.

local Camera = require("src.core.camera")
local Rng = require("src.core.rng")
local Session = require("src.session")
local Ledger = require("src.sim.systems.ledger")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Homestead = { name = "homestead", opaque = true }
Homestead.__index = Homestead

local HUD_H = 28

function Homestead.new()
  return setmetatable({}, Homestead)
end

function Homestead:enter(slot, data)
  local ctx = self.app.ctx
  local tuning = ctx.tuning
  self.session = Session.new({ store = ctx.store, slot = slot, data = data, registry = ctx.registry, tuning = tuning })
  ctx.session = self.session
  self.session:save() -- a new slot exists on disk as soon as it's started

  local tile = tuning.display.tileSize
  self.mapW, self.mapH = tuning.world.mapWidth, tuning.world.mapHeight
  self.camera = Camera.new({
    tileSize = tile,
    zoomLevels = tuning.camera.zoomLevels,
    zoomIndex = tuning.camera.defaultZoomIndex,
  })
  self.camera:setBounds(self.mapW * tile, self.mapH * tile)
  self.camera.x, self.camera.y = self.mapW * tile / 2, self.mapH * tile / 2
  self.ground = self:buildPlaceholderGround()
  self.buttons = Buttons.new(tuning.input.minTouchTarget)
end

-- Placeholder ground: subtly varied grass, seeded from the run so each run looks different.
-- Visual only; uses its own generator so it never consumes the sim's random streams.
function Homestead:buildPlaceholderGround()
  local tile = self.camera.tileSize
  local canvas = love.graphics.newCanvas(self.mapW * tile, self.mapH * tile)
  local rng = Rng.new(Rng.deriveSeed(self.session.world.state.seed, "placeholder-ground"))
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.25, 0.42, 0.22, 1)
  for ty = 1, self.mapH do
    for tx = 1, self.mapW do
      local v = rng:range(-0.035, 0.035)
      local checker = ((tx + ty) % 2 == 0) and 0.012 or 0
      love.graphics.setColor(0.27 + v + checker, 0.45 + v + checker, 0.24 + v, 1)
      love.graphics.rectangle("fill", (tx - 1) * tile, (ty - 1) * tile, tile, tile)
    end
  end
  love.graphics.pop()
  return canvas
end

function Homestead:exit()
  self:saveNow()
  if self.app.ctx.session == self.session then
    self.app.ctx.session = nil
  end
end

function Homestead:saveNow()
  local ok, err = self.session:save()
  if not ok then
    print("Save failed: " .. tostring(err))
  end
end

function Homestead:focus(hasFocus)
  if not hasFocus then
    self:saveNow()
  end
end

function Homestead:quit()
  self:saveNow()
end

function Homestead:resize(view)
  self.camera:clamp(view)
  self.buttons:clear()
  self.buttons:add({
    x = view.w - 64,
    y = 2,
    w = 60,
    h = 24,
    label = "Menu",
    onPress = function()
      self:openMenu()
    end,
  })
end

function Homestead:openMenu()
  self.app:push(require("src.scenes.menu").new(function()
    self.app:switch(require("src.scenes.slots").new())
  end))
end

function Homestead:update(dt)
  self.session:update(dt)
end

function Homestead:tileAt(vx, vy)
  local view = self.app.view
  local wx, wy = self.camera:viewToWorld(vx, vy, view)
  local tx, ty = self.camera:worldToTile(wx, wy)
  if tx >= 1 and ty >= 1 and tx <= self.mapW and ty <= self.mapH then
    return tx, ty
  end
  return nil
end

function Homestead:action(name, data)
  if self.buttons:action(name, data) then
    return true
  end
  local view = self.app.view
  if name == "pan" then
    self.camera:pan(data.dx, data.dy, view)
  elseif name == "zoom" then
    self.camera:zoomBy(data.steps, data.x, data.y, view)
  elseif name == "hover" then
    self.hoverX, self.hoverY = self:tileAt(data.x, data.y)
  elseif name == "select" then
    if data.y > HUD_H then
      self.selX, self.selY = self:tileAt(data.x, data.y)
    end
  elseif name == "cancel" then
    self:openMenu()
  else
    return false
  end
  return true
end

local function outlineTile(camera, tx, ty, color)
  local wx, wy = camera:tileToWorld(tx, ty)
  love.graphics.setColor(color)
  love.graphics.setLineWidth(1 / camera:zoom())
  love.graphics.rectangle("line", wx, wy, camera.tileSize, camera.tileSize)
end

function Homestead:draw()
  local view = self.app.view
  self.camera:attach(view)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.ground, 0, 0)
  if self.hoverX then
    outlineTile(self.camera, self.hoverX, self.hoverY, { 1, 1, 1, 0.35 })
  end
  if self.selX then
    outlineTile(self.camera, self.selX, self.selY, theme.colors.accent)
  end
  love.graphics.pop()

  -- HUD
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, 0, view.w, HUD_H)
  local data = self.session.data
  local world = self.session.world
  Text.draw(data.name, 8, 8, { size = "body" })
  local money = Ledger.get(world, "money")
  Text.draw(string.format("$%d   ·   %s", money, Draw.formatPlaytime(data.header.playtime)), 0, 9, {
    size = "small",
    width = view.w,
    align = "center",
    color = theme.colors.textDim,
  })
  if self.selX then
    Text.draw(string.format("Tile %d, %d", self.selX, self.selY), 8, view.h - 16, {
      size = "small",
      color = theme.colors.textDim,
    })
  end
  self.buttons:draw()
end

function Homestead:debugLines()
  local c = self.camera
  return {
    string.format("camera: %.0f,%.0f zoom=%dx", c.x, c.y, c:zoom()),
    string.format("hover: %s  selected: %s", self.hoverX and (self.hoverX .. "," .. self.hoverY) or "-", self.selX and (self.selX .. "," .. self.selY) or "-"),
  }
end

return Homestead
