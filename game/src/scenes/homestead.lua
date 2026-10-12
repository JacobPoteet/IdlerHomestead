-- The homestead: runs the session, draws the world, and turns taps into orders.
--
-- Controls (GDD §5.2, §10): tap a tile and the homesteader walks there and does the obvious
-- thing (clear, till, plant, water, harvest, fill bucket, load the smoker, walk). What's "in hand"
-- decides the rest: a seed tills/plants, the rod fishes. "Plan field" marks a rectangle (two taps)
-- for the routine to farm; "Place" puts down equipment from the inventory. Tapping the truck opens
-- the truck panel. After tuning.idle.takeoverDelay seconds without input (less with habits perks),
-- the routine takes over.

local Camera = require("src.core.camera")
local Session = require("src.session")
local Grid = require("src.sim.grid")
local Calendar = require("src.sim.systems.calendar")
local Ledger = require("src.sim.systems.ledger")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Needs = require("src.sim.systems.needs")
local Food = require("src.sim.systems.food")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Weather = require("src.sim.systems.weather")
local Forecast = require("src.ui.forecast")
local Run = require("src.meta.run")
local Stats = require("src.sim.stats")
local Power = require("src.sim.systems.power")
local Processing = require("src.sim.systems.processing")
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
local TOAST_TIME = 2.6

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
  self.mode = "act" -- "act" | "plan" | "place"
  self.seed = nil -- crop id in hand
  self.tool = nil -- "rod" in hand
  self.placing = nil -- object id being placed
  self.toast = nil
  self.toastQueue = {}
  self:subscribe()
end

-- World events the player should hear about.
function Homestead:subscribe()
  local events, world = self.world.events, self.world
  local function name(kind, id)
    return world.registry:get(kind, id).name
  end
  self.unsubscribe = {
    events:on("fishing.ready", function()
      self.app:push(require("src.scenes.fishing").new(world, function(fish, size, first)
        self:showToast(string.format("%s%s, %d cm", first and "New! " or "", fish.name, size))
      end))
    end),
    events:on("fish.caught", function(e)
      if e.mode == "idle" then
        self:showToast("Caught a " .. name("fish", e.fish) .. (e.first and " (new!)" or ""))
      end
    end),
    events:on("market.delivered", function(e)
      self:showToast("Delivered: " .. name("catalog", e.item))
      self:layout()
    end),
    events:on("processing.done", function(e)
      self:showToast(string.format("%d %s ready", e.count, name("resources", e.output)))
    end),
    events:on("food.spoiled", function(e)
      self:showToast(string.format("%d %s spoiled", e.amount, name("resources", e.resource)))
    end),
    -- Journal news waits its turn so a note and the idea it sparks are both seen.
    events:on("journal.note", function(e)
      self:queueToast("New note: " .. world.registry:get("notes", e.note).line)
    end),
    events:on("journal.idea", function(e)
      self:queueToast("New idea: " .. Journal.node(world, e.item).name .. " · see the Journal")
    end),
    events:on("needs.depleted", function()
      self.failed = true
    end),
    events:on("weather.forecast", function(e)
      self:queueToast(Forecast.news(world, e.piece))
    end),
    events:on("weather.froze", function()
      self:queueToast("The creek froze. Cut a hole to fish or fetch water.")
    end),
    events:on("weather.coldSnap", function(e)
      self:queueToast(e.active and "Cold snap! Fires need far more wood." or "The cold snap broke.")
    end),
    events:on("journal.learned", function(e)
      local where = Journal.kindOf(world, e.item) == "perks" and "from your next run" or "now in the catalog"
      self:queueToast("Learned: " .. Journal.node(world, e.item).name .. " · " .. where)
    end),
  }
end

function Homestead:exit()
  self:saveNow()
  for _, off in ipairs(self.unsubscribe or {}) do
    off()
  end
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

--- Show after the current toast (and any already waiting) instead of replacing it.
function Homestead:queueToast(text)
  if not self.toast then
    self:showToast(text)
    return
  end
  self.toastQueue[#self.toastQueue + 1] = text
end

function Homestead:toaster()
  return function(text)
    self:showToast(text)
  end
end

-- HUD buttons --------------------------------------------------------------------------

function Homestead:setHand(seed, tool)
  self.seed, self.tool, self.mode, self.planStart, self.placing = seed, tool, "act", nil, nil
  self:layout()
end

-- First object waiting in the inventory (sorted for stability), or nil.
function Homestead:nextPlaceable()
  local ids = {}
  for id, count in pairs(self.world.state.inventory.objects) do
    if count > 0 then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids[1]
end

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
  local inHand = self.mode == "act"
  add({
    w = 40,
    label = "Hand",
    selected = inHand and not self.seed and not self.tool,
    onPress = function()
      self:setHand(nil, nil)
    end,
  })
  for _, crop in ipairs(world.registry:all("crops")) do
    self.seedButtons[crop.id] = add({
      w = 40,
      icon = "icon_" .. crop.seed,
      label = tostring(Ledger.get(world, crop.seed)),
      selected = self.seed == crop.id and self.mode ~= "place",
      onPress = function()
        if self.seed == crop.id and inHand then
          self:setHand(nil, nil)
        else
          self:setHand(crop.id, nil)
        end
      end,
    })
  end
  add({
    w = 30,
    icon = "icon_rod",
    label = "",
    selected = inHand and self.tool == "rod",
    onPress = function()
      self:setHand(nil, self.tool ~= "rod" and "rod" or nil)
    end,
  })
  x = x + 4
  local placeable = self:nextPlaceable()
  if placeable then
    local def = world.registry:get("objects", placeable)
    local label = "Place " .. def.name:lower()
    add({
      w = math.max(80, math.ceil(Text.measure(label, "body")) + 12),
      label = label,
      style = "accent",
      selected = self.mode == "place",
      onPress = function()
        if self.mode == "place" then
          self:setHand(nil, nil)
        else
          self.mode, self.placing, self.planStart = "place", placeable, nil
          self:showToast("Tap where the " .. def.name:lower() .. " should go")
          self:layout()
        end
      end,
    })
  end
  add({
    w = 46,
    label = "Plan",
    selected = self.mode == "plan",
    onPress = function()
      if self.mode == "plan" then
        self:setHand(self.seed, nil)
        return
      end
      self.mode, self.planStart, self.tool, self.placing = "plan", nil, nil, nil
      self:showToast(self.seed and "Tap two corners to plan " .. world.registry:get("crops", self.seed).name
        or "Tap two corners to clear a plan")
      self:layout()
    end,
  })
  add({
    w = 54,
    label = "Routine",
    onPress = function()
      self.app:push(require("src.scenes.routine").new(world))
    end,
  })
  -- Right side: books and lists
  local rx = view.w - 6
  local function addRight(b)
    rx = rx - b.w
    b.x, b.y, b.h = rx, y, 24
    rx = rx - 4
    self.buttons:add(b)
  end
  self.journalPrompt = Journal.needsChoice(world)
  addRight({
    w = 56,
    label = "Journal",
    style = self.journalPrompt and "accent" or nil,
    onPress = function()
      self.app:push(require("src.scenes.journal").new(world))
    end,
  })
  addRight({
    w = 42,
    label = "Fish",
    onPress = function()
      self.app:push(require("src.scenes.guide").new(world))
    end,
  })
  addRight({
    w = 56,
    label = "Catalog",
    onPress = function()
      self.app:push(require("src.scenes.catalog").new(world, self:toaster()))
    end,
  })
  addRight({
    w = 52,
    label = "Pantry",
    onPress = function()
      self.app:push(require("src.scenes.pantry").new(world))
    end,
  })
end

function Homestead:openMenu()
  self.app:push(require("src.scenes.menu").new(function()
    self.app:switch(require("src.scenes.slots").new())
  end))
end

-- Update ---------------------------------------------------------------------------------

--- Seconds without input before the routine takes over (shortened by habits perks).
function Homestead:takeoverDelay()
  local idle = self.app.ctx.tuning.idle
  return math.max(idle.minTakeoverDelay, idle.takeoverDelay - Stats.modifier(self.world, "idleTakeover"))
end

function Homestead:update(dt)
  local ctx = self.app.ctx
  local idle = ctx.input:idleSeconds() >= self:takeoverDelay()
  self.session:setControl(idle and "idle" or "active")
  self.session:update(dt)
  if self.failed then
    -- Condition hit zero: the run is over (GDD §4.3). Record it, then search & rescue.
    local slot, data = self.session.slot, self.session.data
    Run.fail(data, self.world)
    self.app:switch(require("src.scenes.rescue").new(), slot, data)
    return
  end
  self.renderer:update(dt)
  if self.toast then
    self.toast.time = self.toast.time - dt
    if self.toast.time <= 0 then
      self.toast = nil
      if #self.toastQueue > 0 then
        self:showToast(table.remove(self.toastQueue, 1))
      end
    end
  end
  -- The Journal button lights up while there's an idea to pick and nothing queued (GDD §8.1).
  if Journal.needsChoice(self.world) ~= self.journalPrompt then
    self:layout()
  end
  -- Seed counts change as you plant and harvest; keep the toolbar labels current.
  for cropId, button in pairs(self.seedButtons) do
    button.label = tostring(Ledger.get(self.world, self.world.registry:get("crops", cropId).seed))
  end
  if self.mode == "place" and Inventory.objectCount(self.world, self.placing) <= 0 then
    self:setHand(nil, nil)
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
  local world = self.world
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
  if self.mode == "place" then
    if Inventory.place(world, self.placing, i) then
      self:showToast("Placed " .. world.registry:get("objects", self.placing).name:lower())
      self:setHand(nil, nil)
    else
      self:showToast("Can't place it there")
    end
    return
  end
  local obj = Grid.object(world, i)
  if obj and obj.id == "truck" then
    self.app:push(require("src.scenes.truck").new(world, self:toaster()))
    return
  end
  local hs = Actors.homesteader(world)
  local taskType = Actors.order(world, hs, i, { crop = self.seed, tool = self.tool })
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
    elseif self.mode ~= "act" then
      self:setHand(self.seed, nil)
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
  local z = camera:zoom()
  love.graphics.setColor(color)
  love.graphics.setLineWidth((width or 1) / z)
  love.graphics.rectangle("line", wx + 0.5 / z, wy + 0.5 / z, camera.tileSize - 1 / z, camera.tileSize - 1 / z)
end

function Homestead:drawOverlays()
  local world = self.world
  local grid, camera, tile = world.state.grid, self.camera, self.camera.tileSize
  local hs = Actors.homesteader(world)
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
  if self.mode == "place" and self.hover then
    -- Ghost of the object being placed: tinted green where it fits, red where it doesn't.
    local def = world.registry:get("objects", self.placing)
    local sprite = Assets.sprite(self.placing)
    local x, y = Grid.coords(grid, self.hover)
    local ok = Inventory.canPlace(world, self.placing, self.hover)
    love.graphics.setColor(ok and 0.6 or 1, ok and 1 or 0.45, ok and 0.6 or 0.45, 0.7)
    local bottom = (y - 1 + (def.footprintH or 1)) * tile
    love.graphics.draw(sprite.image, sprite.quad, (x - 1) * tile, bottom - sprite.h)
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
  return x + sprite.w + 3 + w + 9
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
  local truck = world.state.land.truck
  local x = 162
  x = stat("icon_money", "$" .. Ledger.get(world, "money"), x, 6)
  x = stat("icon_food", string.format("%.1fd", Needs.foodDays(world)), x, 6)
  x = stat("icon_heart", tostring(math.floor(world.state.needs.condition + 0.5)), x, 6)
  x = stat("icon_battery", string.format("%d%%", math.floor(Power.charge(world, truck) / Power.capacity(world, truck) * 100)), x, 6)
  x = stat("icon_crate", tostring(Food.crateCount(world)), x, 6)
  x = stat("icon_wood", tostring(Ledger.get(world, "wood")), x, 6)
  -- Warmth in stock, in nights of this season's need (or the raw amount when no fire is needed).
  local warmth, need = Needs.warmthInStock(world), Needs.warmthNeeded(world)
  stat("icon_firewood", need > 0 and string.format("%.1fn", warmth / need) or string.format("%.0f", warmth), x, 6)
end

-- Winter forecast under the top bar, from autumn on (GDD §4.1); loud during the cold snap.
function Homestead:drawForecast()
  local world = self.world
  local text, color
  if Weather.isColdSnap(world) then
    text, color = "Cold snap", theme.colors.danger
  else
    local summary = Forecast.summary(world)
    if not summary then
      return
    end
    local frozen = Weather.isFrozen(world)
    text = (frozen and "This winter: " or "Forecast: ") .. summary
    color = theme.colors.accent
  end
  local w = Text.measure(text, "small") + 12
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 4, TOP_H + 4, w, 14, 3, 3)
  Text.draw(text, 4, TOP_H + 6, { size = "small", width = w, align = "center", color = color })
end

function Homestead:drawBottomBar(view)
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, view.h - BOTTOM_H, view.w, BOTTOM_H)
end

function Homestead:drawControlBadge(view)
  local ctx = self.app.ctx
  local text, color
  if Actors.homesteader(self.world).asleep then
    text, color = "Sleeping", theme.colors.textDim
  elseif self.world.control == "idle" then
    text, color = "Routine running", theme.colors.accent
  else
    local remaining = self:takeoverDelay() - ctx.input:idleSeconds()
    text, color = string.format("Routine in %ds", math.max(0, math.ceil(remaining))), theme.colors.textDim
  end
  local w = Text.measure(text, "small") + 12
  local x, y = view.w - w - 4, view.h - BOTTOM_H - 18
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", x, y, w, 14, 3, 3)
  Text.draw(text, x, y + 2, { size = "small", width = w, align = "center", color = color })
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
  local obj, anchor = Grid.object(world, i)
  if obj then
    lines[#lines + 1] = obj.name
    if obj.battery then
      lines[#lines + 1] = string.format("Battery %.1f / %d kWh", Power.charge(world, anchor), obj.battery)
    end
    if obj.powerOutput then
      lines[#lines + 1] = string.format("Solar %.2f kW now", obj.powerOutput * Power.sun(world))
    end
    if obj.station then
      local batch = Processing.batch(world, anchor)
      if batch then
        local hours = batch.remaining / (world.tuning.time.dayLength / 24)
        local recipe = world.registry:get("recipes", batch.recipe)
        lines[#lines + 1] = string.format("%s %d · %.1fh left", recipe.name, batch.count, hours)
      else
        lines[#lines + 1] = "Idle"
      end
    end
    if obj.heatSource then
      lines[#lines + 1] = string.format("Heat x%.1f · needs %d a night", obj.heatSource, Needs.warmthNeeded(world))
    end
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
    Draw.panel(4, y, 132, h)
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
  self:drawForecast()
  self:drawBottomBar(view)
  self:drawControlBadge(view)
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
    string.format("camera: %.0f,%.0f zoom=%dx  control=%s mode=%s", c.x, c.y, c:zoom(), self.world.control, self.mode),
    string.format("homesteader: %.1f,%.1f bucket=%d job=%s", hs.x, hs.y, hs.bucket, job),
    "routine: " .. table.concat(priorities, " > "),
  }
end

return Homestead
