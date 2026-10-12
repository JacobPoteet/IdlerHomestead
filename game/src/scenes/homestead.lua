-- The homestead: runs the session, draws the world, and turns taps into orders.
--
-- Controls (GDD §5.2, §10): tap a tile and the homesteader walks there and does the obvious
-- thing (clear, till, plant, water, harvest, fill bucket, walk). The seed in hand decides what
-- gets planted. "Plan field" marks a rectangle (two taps) for the idle routine to farm.
-- After tuning.idle.takeoverDelay seconds without input, the routine takes over.

local Camera = require("src.core.camera")
local Session = require("src.session")
local Grid = require("src.sim.grid")
local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Needs = require("src.sim.systems.needs")
local Renderer = require("src.render.world_renderer")
local Assets = require("src.render.assets")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Homestead = { name = "homestead", opaque = true }
Homestead.__index = Homestead

local TOP_H = 24
local BOTTOM_H = 34
local TOAST_TIME = 2.2

function Homestead.new()
  return setmetatable({}, Homestead)
end

function Homestead:enter(slot, data)
  local ctx = self.app.ctx
  local tuning = ctx.tuning
  self.session = Session.new({ store = ctx.store, slot = slot, data = data, registry = ctx.registry, tuning = tuning })
  ctx.session = self.session
  self.session:save() -- a new slot exists on disk as soon as it's started
  self.world = self.session.world

  local grid = self.world.state.grid
  local tile = tuning.display.tileSize
  self.camera = Camera.new({
    tileSize = tile,
    zoomLevels = tuning.camera.zoomLevels,
    zoomIndex = tuning.camera.defaultZoomIndex,
  })
  self.camera:setBounds(grid.w * tile, grid.h * tile)
  local hs = Actors.homesteader(self.world)
  self.camera.x, self.camera.y = (hs.x - 0.5) * tile, (hs.y - 0.5) * tile
  self.renderer = Renderer.new(self.world)
  self.buttons = Buttons.new(tuning.input.minTouchTarget)
  self.mode = "act" -- "act" | "plan"
  self.seed = nil -- crop id in hand, or nil
  self.toast = nil
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
  local s = view.scale
  self.canvas = love.graphics.newCanvas(math.floor(view.w * s + 0.5), math.floor(view.h * s + 0.5))
  self.canvas:setFilter("nearest", "nearest")
  self.camera:clamp(view)
  self:layout()
end

function Homestead:showToast(text)
  self.toast = { text = text, time = TOAST_TIME }
end

-- HUD buttons --------------------------------------------------------------------------

function Homestead:layout()
  local view = self.app.view
  local world = self.world
  self.buttons:clear()
  self.seedButtons = {}
  self.buttons:add({
    x = view.w - 52,
    y = 0,
    w = 50,
    h = TOP_H,
    label = "Menu",
    onPress = function()
      self:openMenu()
    end,
  })
  local y = view.h - BOTTOM_H + 5
  local x = 6
  local function add(b)
    b.x, b.y, b.h = x, y, 24
    self.buttons:add(b)
    x = x + b.w + 4
    return b
  end
  add({
    w = 44,
    label = "Hand",
    selected = self.seed == nil and self.mode == "act",
    onPress = function()
      self.seed, self.mode, self.planStart = nil, "act", nil
      self:layout()
    end,
  })
  for _, crop in ipairs(world.registry:all("crops")) do
    self.seedButtons[crop.id] = add({
      w = 46,
      icon = "icon_" .. crop.seed,
      label = tostring(Ledger.get(world, crop.seed)),
      selected = self.seed == crop.id,
      onPress = function()
        self.seed = (self.seed == crop.id and self.mode == "act") and nil or crop.id
        self:layout()
      end,
    })
  end
  x = x + 6
  add({
    w = 70,
    label = self.mode == "plan" and "Planning" or "Plan field",
    selected = self.mode == "plan",
    onPress = function()
      self.mode = self.mode == "plan" and "act" or "plan"
      self.planStart = nil
      if self.mode == "plan" then
        self:showToast(self.seed and "Tap two corners to plan " .. world.registry:get("crops", self.seed).name
          or "Tap two corners to clear a plan")
      end
      self:layout()
    end,
  })
  add({
    w = 62,
    label = "Routine",
    onPress = function()
      self.app:push(require("src.scenes.routine").new(world))
    end,
  })
end

function Homestead:openMenu()
  self.app:push(require("src.scenes.menu").new(function()
    self.app:switch(require("src.scenes.slots").new())
  end))
end

-- Update ---------------------------------------------------------------------------------

function Homestead:update(dt)
  local ctx = self.app.ctx
  local idle = ctx.input:idleSeconds() >= ctx.tuning.idle.takeoverDelay
  self.session:setControl(idle and "idle" or "active")
  self.session:update(dt)
  self.renderer:update(dt)
  if self.toast then
    self.toast.time = self.toast.time - dt
    if self.toast.time <= 0 then
      self.toast = nil
    end
  end
  -- Seed counts change as you plant and harvest; keep the toolbar labels current.
  for cropId, button in pairs(self.seedButtons) do
    button.label = tostring(Ledger.get(self.world, self.world.registry:get("crops", cropId).seed))
  end
end

-- Input ----------------------------------------------------------------------------------

function Homestead:tileAt(vx, vy)
  local view = self.app.view
  local wx, wy = self.camera:viewToWorld(vx, vy, view)
  local tx, ty = self.camera:worldToTile(wx, wy)
  if Grid.inBounds(self.world.state.grid, tx, ty) then
    return Grid.index(self.world.state.grid, tx, ty)
  end
  return nil
end

function Homestead:inWorldArea(y)
  return y > TOP_H and y < self.app.view.h - BOTTOM_H
end

function Homestead:applyPlan(a, b)
  local grid = self.world.state.grid
  local ax, ay = Grid.coords(grid, a)
  local bx, by = Grid.coords(grid, b)
  local count = 0
  for y = math.min(ay, by), math.max(ay, by) do
    for x = math.min(ax, bx), math.max(ax, bx) do
      if Crops.setPlan(self.world, Grid.index(grid, x, y), self.seed) and self.seed then
        count = count + 1
      end
    end
  end
  if self.seed then
    self:showToast(string.format("Planned %d tiles of %s", count, self.world.registry:get("crops", self.seed).name))
  else
    self:showToast("Plan cleared")
  end
end

function Homestead:tap(i)
  self.selected = i
  if self.mode == "plan" then
    if not self.planStart then
      self.planStart = i
    else
      self:applyPlan(self.planStart, i)
      self.planStart = nil
    end
    return
  end
  local hs = Actors.homesteader(self.world)
  local taskType = Actors.order(self.world, hs, i, { crop = self.seed })
  if taskType then
    if taskType.id ~= "move" then
      self:showToast(taskType.verb)
    end
  else
    self:showToast("Can't do anything there")
  end
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
    self.hover = self:inWorldArea(data.y) and self:tileAt(data.x, data.y) or nil
  elseif name == "select" then
    if self:inWorldArea(data.y) then
      local i = self:tileAt(data.x, data.y)
      if i then
        self:tap(i)
      end
    end
  elseif name == "context" then
    if self:inWorldArea(data.y) then
      self.selected = self:tileAt(data.x, data.y) -- inspect only
    end
  elseif name == "cancel" then
    if self.planStart then
      self.planStart = nil
    elseif self.mode == "plan" then
      self.mode = "act"
      self:layout()
    else
      self:openMenu()
    end
  else
    return false
  end
  return true
end

-- Drawing --------------------------------------------------------------------------------

local function outlineTile(camera, i, grid, color, width)
  local x, y = Grid.coords(grid, i)
  local wx, wy = camera:tileToWorld(x, y)
  love.graphics.setColor(color)
  love.graphics.setLineWidth((width or 1) / camera:zoom())
  love.graphics.rectangle("line", wx + 0.5 / camera:zoom(), wy + 0.5 / camera:zoom(), camera.tileSize - 1 / camera:zoom(), camera.tileSize - 1 / camera:zoom())
end

function Homestead:drawOverlays()
  local grid, camera, tile = self.world.state.grid, self.camera, self.camera.tileSize
  local hs = Actors.homesteader(self.world)
  if hs.job and hs.job.task ~= "move" then
    outlineTile(camera, hs.job.target, grid, { 1, 0.9, 0.55, 0.6 })
  end
  if hs.job and #hs.job.path > 0 then
    love.graphics.setColor(1, 1, 1, 0.35)
    for _, i in ipairs(hs.job.path) do
      local x, y = Grid.coords(grid, i)
      love.graphics.rectangle("fill", (x - 0.5) * tile - 1, (y - 0.5) * tile - 1, 2, 2)
    end
  end
  if self.planStart then
    local target = self.hover or self.planStart
    local ax, ay = Grid.coords(grid, self.planStart)
    local bx, by = Grid.coords(grid, target)
    love.graphics.setColor(0.95, 0.88, 0.6, 0.25)
    love.graphics.rectangle(
      "fill",
      (math.min(ax, bx) - 1) * tile,
      (math.min(ay, by) - 1) * tile,
      (math.abs(ax - bx) + 1) * tile,
      (math.abs(ay - by) + 1) * tile
    )
  end
  if self.hover then
    outlineTile(camera, self.hover, grid, { 1, 1, 1, 0.35 })
  end
  if self.selected then
    outlineTile(camera, self.selected, grid, theme.colors.accent)
  end
end

local function stat(icon, value, x, y)
  local sprite = Assets.sprite(icon)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(sprite.image, sprite.quad, x, y)
  Text.draw(value, x + sprite.w + 3, y + 1, { size = "small" })
  local w = Text.measure(value, "small")
  return x + sprite.w + 3 + w + 10
end

function Homestead:drawTopBar(view)
  local world = self.world
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, 0, view.w, TOP_H)
  local now = Calendar.now(world)
  local hour = math.floor(now.hour)
  local minute = math.floor((now.hour - hour) * 60)
  local season = now.season:gsub("^%l", string.upper)
  Text.draw(string.format("Day %d · %s · %02d:%02d", now.dayOfSeason, season, hour, minute), 8, 7, { size = "body" })
  local x = 168
  x = stat("icon_money", "$" .. Ledger.get(world, "money"), x, 6)
  x = stat("icon_food", string.format("%.1fd", Needs.foodDays(world)), x, 6)
  x = stat("icon_heart", tostring(math.floor(world.state.needs.condition + 0.5)), x, 6)
  x = stat("icon_wood", tostring(Ledger.get(world, "wood")), x, 6)
  x = stat("icon_stone", tostring(Ledger.get(world, "stone")), x, 6)
  stat("icon_scrap", tostring(Ledger.get(world, "scrap")), x, 6)
end

function Homestead:drawBottomBar(view)
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, view.h - BOTTOM_H, view.w, BOTTOM_H)
  local ctx = self.app.ctx
  local remaining = ctx.tuning.idle.takeoverDelay - ctx.input:idleSeconds()
  local text, color
  if self.world.control == "idle" then
    text, color = "Routine running", theme.colors.accent
  else
    text, color = string.format("You're in control · routine in %ds", math.max(0, math.ceil(remaining))), theme.colors.textDim
  end
  Text.draw(text, 0, view.h - BOTTOM_H + 12, { size = "small", width = view.w - 10, align = "right", color = color })
end

function Homestead:tileInfo(i)
  local world = self.world
  local grid = world.state.grid
  local lines = {}
  local terrain = Grid.terrain(world, i)
  lines[#lines + 1] = world.state.fields.tilled[i] and "Tilled soil" or terrain.name
  if terrain.tillable then
    lines[#lines + 1] = string.format("Soil %d%%", math.floor(grid.soil[i] * 100 + 0.5))
  end
  local obj = Grid.object(world, i)
  if obj then
    lines[#lines + 1] = obj.name
  end
  local crop = world.state.crops[i]
  if crop then
    local def = world.registry:get("crops", crop.id)
    if Crops.isMature(crop) then
      lines[#lines + 1] = def.name .. ": ready"
    else
      lines[#lines + 1] = string.format("%s: %d%%%s", def.name, math.floor(crop.growth * 100), crop.moisture > 0 and "" or ", thirsty")
    end
  elseif world.state.fields.plan[i] then
    lines[#lines + 1] = "Planned: " .. world.registry:get("crops", world.state.fields.plan[i]).name
  end
  return lines
end

function Homestead:drawInfo(view)
  if self.selected then
    local lines = self:tileInfo(self.selected)
    local h = #lines * 11 + 8
    local y = view.h - BOTTOM_H - h - 4
    Draw.panel(4, y, 120, h)
    for n, line in ipairs(lines) do
      Text.draw(line, 10, y + 4 + (n - 1) * 11, { size = "small", color = n == 1 and theme.colors.text or theme.colors.textDim })
    end
  end
  if self.toast then
    local w = Text.measure(self.toast.text, "body") + 16
    local x, y = (view.w - w) / 2, view.h - BOTTOM_H - 26
    love.graphics.setColor(0, 0, 0, 0.55 * math.min(1, self.toast.time * 3))
    love.graphics.rectangle("fill", x, y, w, 18, 3, 3)
    Text.draw(self.toast.text, x, y + 4, { size = "body", width = w, align = "center" })
  end
end

function Homestead:draw()
  local view = self.app.view
  local tint, light, daylight = self.renderer:lighting()

  -- World -> canvas -> colour grade -> screen
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 1)
  self.camera:attach(view)
  local x1, y1, x2, y2 = self.camera:visibleTiles(view)
  self.renderer:draw(self.session.clock:alpha(), { x1, y1, x2, y2 }, daylight)
  self:drawOverlays()
  love.graphics.pop()
  love.graphics.setCanvas()
  love.graphics.origin()
  self.renderer:drawGraded(self.canvas, tint, light, view.scale * self.camera:zoom())
  love.graphics.pop()

  -- HUD (not graded)
  self:drawTopBar(view)
  self:drawBottomBar(view)
  self:drawInfo(view)
  self.buttons:draw()
end

function Homestead:debugLines()
  local c = self.camera
  local hs = Actors.homesteader(self.world)
  local job = hs.job and string.format("%s@%d (%.1fs)", hs.job.task, hs.job.target, hs.job.progress) or "-"
  local priorities = {}
  for _, e in ipairs(self.world.state.priorities) do
    priorities[#priorities + 1] = e.category .. (e.enabled and "" or "(off)")
  end
  return {
    string.format("camera: %.0f,%.0f zoom=%dx  control=%s", c.x, c.y, c:zoom(), self.world.control),
    string.format("homesteader: %.1f,%.1f bucket=%d job=%s", hs.x, hs.y, hs.bucket, job),
    "routine: " .. table.concat(priorities, " > "),
  }
end

return Homestead
