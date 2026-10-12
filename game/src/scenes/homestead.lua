-- The homestead: runs the session, draws the world, and turns taps into orders.
--
-- Controls (GDD §5.2, §10): tap a tile and the homesteader walks there and does the obvious
-- thing (clear, till, plant, water, harvest, fill bucket, load the smoker, walk). What's "in hand"
-- decides the rest: a seed tills/plants, the rod fishes. "Plan field" marks a rectangle (two taps)
-- for the routine to farm; "Place" puts down equipment from the inventory. Tapping the truck opens
-- the truck panel. After tuning.idle.takeoverDelay seconds without input (less with habits perks),
-- the routine takes over; "Start routine" does it at once (D43). The speed button cycles the sim
-- speed (paused/1x/2x/4x, D42); panels and the camera keep working while paused.

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
local Land = require("src.sim.systems.land")
local Water = require("src.sim.systems.water")
local Processing = require("src.sim.systems.processing")
local Renderer = require("src.render.world_renderer")
local ActionRing = require("src.render.action_ring")
local Assets = require("src.render.assets")
local Buttons = require("src.ui.buttons")
local Draw = require("src.ui.draw")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Homestead = { name = "homestead", opaque = true }
Homestead.__index = Homestead

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
      -- The fishing mini-game plays in real time: don't let the world race past it.
      self.session:setSpeed(self.app.ctx.tuning.time.defaultSpeed)
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
    events:on("market.held", function(e)
      self:showToast(name("catalog", e.item) .. " is waiting at the gate: no room in storage")
    end),
    events:on("processing.blocked", function(e)
      self:showToast(string.format("%d %s waiting: no room in storage", e.count, name("resources", e.output)))
    end),
    events:on("ledger.overflow", function(e)
      self:showToast(string.format("Storage full: lost %d %s", e.lost, name("resources", e.id)))
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
    events:on("water.dry", function()
      self:queueToast("A drip line is dry. Fill the cistern or the crops need hand watering.")
    end),
    events:on("water.restored", function()
      self:queueToast("Drip lines are watering again.")
    end),
    events:on("power.brownout", function(e)
      self:queueToast(string.format("Power short: %s at %d%%", Power.tierName(world, e.tier), math.floor(e.ratio * 100)))
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
  local w, h = math.floor(view.w * s + 0.5), math.floor(view.h * s + 0.5)
  -- Dragging the window edge fires many resizes: reuse the canvas when the pixel size is
  -- unchanged and free the old one's GPU memory right away when it has to be replaced.
  if not (self.canvas and self.canvas:getWidth() == w and self.canvas:getHeight() == h) then
    if self.canvas then
      self.canvas:release()
    end
    self.canvas = love.graphics.newCanvas(w, h)
    self.canvas:setFilter("nearest", "nearest")
  end
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

-- Top-bar stats, in order: { icon, text }. Big numbers are abbreviated so the strip stays short.
local function count(n)
  if n >= 10000 then
    return string.format("%dk", math.floor(n / 1000))
  end
  return tostring(n)
end

function Homestead:stats()
  local world = self.world
  local truck = world.state.land.truck
  -- Warmth in stock, in nights of this season's need (or the raw amount when no fire is needed).
  local warmth, need = Needs.warmthInStock(world), Needs.warmthNeeded(world)
  local stats = {
    { "icon_money", "$" .. count(Ledger.get(world, "money")) },
    { "icon_food", string.format("%.1fd", Needs.foodDays(world)) },
    { "icon_heart", tostring(math.floor(world.state.needs.condition + 0.5)) },
    { "icon_battery", string.format("%d%%", math.floor(Power.charge(world, truck) / Power.capacity(world, truck) * 100)) },
    { "icon_crate", count(Food.crateCount(world)) },
    { "icon_wood", count(Ledger.get(world, "wood")) },
    { "icon_firewood", need > 0 and string.format("%.1fn", warmth / need) or string.format("%.0f", warmth) },
  }
  if Water.hasCistern(world) then
    -- Cistern stock, once there is a cistern to hold it.
    stats[#stats + 1] = { "icon_water", string.format("%d%%", math.floor(Water.fraction(world) * 100 + 0.5)) }
  end
  return stats
end

-- Width of the stat strip with `gap` between stats.
function Homestead:statsWidth(gap)
  local ui = self.app.ctx.tuning.ui
  local total = 0
  for _, s in ipairs(self:stats()) do
    total = total + Assets.sprite(s[1]).w + ui.statIconGap + Text.measure(s[2], "small")
  end
  return total + gap * (#self:stats() - 1)
end

-- True when the stats don't fit beside the date and need their own row under it.
function Homestead:wantsStatRow()
  local ui = self.app.ctx.tuning.ui
  local room = self.app.view.w - ui.menuWidth - ui.statsAfterDate - ui.barPadding
  return self:statsWidth(ui.statMinGap) > room
end

function Homestead:layout()
  local view = self.app.view
  local world = self.world
  local ui = self.app.ctx.tuning.ui
  local compact = view.w < ui.compactWidth
  local btnH = compact and ui.compactButtonHeight or ui.buttonHeight
  self.btnH = btnH
  self.statRow = self:wantsStatRow()
  self.topRowH = compact and ui.compactTopBarHeight or ui.topBarHeight
  self.topH = self.topRowH + (self.statRow and ui.statRowHeight or 0)
  self.buttons:clear()
  self.seedButtons = {}
  self.buttons:add({
    x = view.w - ui.menuWidth - 2,
    y = 0,
    w = ui.menuWidth,
    h = self.topRowH,
    label = "Menu",
    onPress = function()
      self:openMenu()
    end,
  })
  -- Toolbar buttons are collected first and placed afterwards: they wrap onto extra rows
  -- when the view is too narrow for one.
  local bw = ui.buttonWidths
  local left, right = {}, {}
  local function add(b)
    left[#left + 1] = b
    return b
  end
  local inHand = self.mode == "act"
  add({
    w = bw.hand,
    label = "Hand",
    selected = inHand and not self.seed and not self.tool,
    onPress = function()
      self:setHand(nil, nil)
    end,
  })
  for _, crop in ipairs(world.registry:all("crops")) do
    self.seedButtons[crop.id] = add({
      w = bw.seed,
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
    w = bw.rod,
    icon = "icon_rod",
    label = "",
    selected = inHand and self.tool == "rod",
    onPress = function()
      self:setHand(nil, self.tool ~= "rod" and "rod" or nil)
    end,
  })
  local placeable = self:nextPlaceable()
  if placeable then
    local def = world.registry:get("objects", placeable)
    local label = "Place " .. def.name:lower()
    add({
      gapBefore = ui.groupGap,
      w = math.max(bw.placeMin, math.ceil(Text.measure(label, "body")) + 12),
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
    gapBefore = not placeable and ui.groupGap or nil,
    w = bw.plan,
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
    w = bw.routine,
    label = "Routine",
    onPress = function()
      self.app:push(require("src.scenes.routine").new(world))
    end,
  })
  -- Books and lists, left to right
  local function addRight(b)
    right[#right + 1] = b
  end
  self.journalPrompt = Journal.needsChoice(world)
  addRight({
    w = bw.pantry,
    label = "Pantry",
    onPress = function()
      self.app:push(require("src.scenes.pantry").new(world))
    end,
  })
  addRight({
    w = bw.catalog,
    label = "Catalog",
    onPress = function()
      self.app:push(require("src.scenes.catalog").new(world, self:toaster()))
    end,
  })
  addRight({
    w = bw.fish,
    label = "Fish",
    onPress = function()
      self.app:push(require("src.scenes.guide").new(world))
    end,
  })
  addRight({
    w = bw.journal,
    label = "Journal",
    style = self.journalPrompt and "accent" or nil,
    onPress = function()
      self.app:push(require("src.scenes.journal").new(world, self:toaster()))
    end,
  })
  self:placeToolbar(view, left, right)
  self:layoutControls(view)
end

-- Place the toolbar buttons. On a wide view the tools sit left and the books right on one row;
-- when that doesn't fit, each group flows left to right and wraps, with the books starting a
-- fresh row, and the bar grows upward to hold the extra rows.
function Homestead:placeToolbar(view, left, right)
  local ui = self.app.ctx.tuning.ui
  local pad, gap, h = ui.barPadding, ui.buttonGap, self.btnH
  local avail = view.w - 2 * pad
  local function span(items)
    local w = 0
    for i, b in ipairs(items) do
      w = w + b.w + (i > 1 and gap + (b.gapBefore or 0) or 0)
    end
    return w
  end
  local rows, rightOnRow1 = {}, span(left) + gap + span(right) <= avail
  local function flow(items)
    local row, rowW = {}, 0
    for _, b in ipairs(items) do
      local need = b.w + (#row > 0 and gap + (b.gapBefore or 0) or 0)
      if #row > 0 and rowW + need > avail then
        rows[#rows + 1] = row
        row, rowW, need = {}, 0, b.w
      end
      row[#row + 1] = b
      rowW = rowW + need
    end
    if #row > 0 then
      rows[#rows + 1] = row
    end
  end
  flow(left)
  if not rightOnRow1 then
    flow(right)
  end
  self.bottomH = 2 * ui.barMargin + #rows * h + (#rows - 1) * gap
  local top = view.h - self.bottomH + ui.barMargin
  for r, row in ipairs(rows) do
    local x, y = pad, top + (r - 1) * (h + gap)
    for i, b in ipairs(row) do
      x = x + (i > 1 and gap + (b.gapBefore or 0) or 0)
      b.x, b.y, b.h = x, y, h
      self.buttons:add(b)
      x = x + b.w
    end
  end
  if rightOnRow1 then
    local x = view.w - pad
    for i = #right, 1, -1 do
      local b = right[i]
      x = x - b.w
      b.x, b.y, b.h = x, top, h
      self.buttons:add(b)
      x = x - gap
    end
  end
end

-- Speed and routine buttons: a column under the top bar, away from the (crowded) toolbar.
function Homestead:speedLabel()
  local speed = self.session:speed()
  return speed == 0 and "Paused" or string.format("%gx", speed)
end

function Homestead:routineLabel()
  if not self.session:canStartRoutine() then
    return "Resting"
  end
  return self.world.control == "idle" and "Routine on" or "Start routine"
end

function Homestead:controlsKey()
  return self:speedLabel() .. "|" .. self:routineLabel() .. "|" .. tostring(Power.satisfaction(self.world) < 1)
end

function Homestead:openPower()
  self.app:push(require("src.scenes.power").new(self.world, self:toaster()))
end

function Homestead:cycleSpeed()
  self.session:cycleSpeed(self.app.ctx.tuning.time.speedSteps)
  self:layout()
end

--- Hand over to the routine now (D43). Says why when it can't.
function Homestead:startRoutine()
  if self.world.control == "idle" then
    return true -- already running
  end
  local ok = self.session:startRoutineNow()
  if not ok then
    self:showToast("The routine rests at night")
  end
  self:layout()
  return ok
end

function Homestead:layoutControls(view)
  local ui = self.app.ctx.tuning.ui
  local x2, y = view.w - ui.buttonGap, self.topH + ui.buttonGap
  local speedLabel, routineLabel = self:speedLabel(), self:routineLabel()
  local function addCol(label, b)
    b.label = label
    b.w = math.max(ui.controlMinWidth, math.ceil(Text.measure(label, "body")) + ui.controlTextPadding)
    b.x, b.y, b.h = x2 - b.w, y, self.btnH
    self.buttons:add(b)
    y = y + b.h + ui.buttonGap
  end
  addCol(speedLabel, {
    style = self.session:speed() == 0 and "accent" or nil,
    onPress = function()
      self:cycleSpeed()
    end,
  })
  addCol(routineLabel, {
    enabled = routineLabel == "Start routine",
    onPress = function()
      self:startRoutine()
    end,
  })
  addCol("Power", {
    style = Power.satisfaction(self.world) < 1 and "danger" or nil, -- lit while the homestead is short of power
    onPress = function()
      self:openPower()
    end,
  })
  self.controlsKeyShown = self:controlsKey()
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
  self.session:update(dt) -- (also ends a hand-started routine at bedtime)
  local idle = self.session:routineForced() or ctx.input:idleSeconds() >= self:takeoverDelay()
  self.session:setControl(idle and "idle" or "active")
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
  if self:controlsKey() ~= self.controlsKeyShown or self:wantsStatRow() ~= self.statRow then
    self:layout()
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
  return y > self.topH and y < self.app.view.h - self.bottomH
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
    elseif world.registry:get("objects", self.placing).placeOn == "waterTable" and not Land.hasWaterTable(world, i) then
      self:showToast("Needs a high water table (blue tiles)")
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
  if obj and (obj.source or obj.sink or obj.battery) then
    self:openPower() -- panels, batteries and powered devices open the power panel
    return
  end
  local hs = Actors.homesteader(world)
  local taskType = Actors.order(world, hs, i, { crop = self.seed, tool = self.tool })
  if taskType then
    self.session:cancelRoutine() -- any order hands control back (D43)
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
  elseif name == "speed" then
    self:cycleSpeed()
  elseif name == "routine" then
    self:startRoutine()
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
  local visuals = world.tuning.visuals
  if self.mode == "place" and world.registry:get("objects", self.placing).placeOn == "waterTable" then
    -- Wells and pumps only go where the water table is high: tint those tiles while placing one.
    love.graphics.setColor(visuals.waterSpots)
    for i = 1, #grid.terrain do
      if Grid.terrain(world, i).tillable and not world.occupancy[i] and Land.hasWaterTable(world, i) then
        local x, y = Grid.coords(grid, i)
        local wx, wy = camera:tileToWorld(x, y)
        love.graphics.rectangle("fill", wx, wy, tile, tile)
      end
    end
  end
  -- Drip zones: the selected line's, or the one being placed under the pointer.
  local zoneAnchor
  if self.selected then
    local obj, anchor = Grid.object(world, self.selected)
    zoneAnchor = obj and obj.drip and anchor or nil
  end
  if zoneAnchor then
    love.graphics.setColor(visuals.waterZone[Water.dripState(world, zoneAnchor) == "dry" and "dry" or "ok"])
    for _, i in ipairs(Water.dripTiles(world, zoneAnchor)) do
      local x, y = Grid.coords(grid, i)
      local wx, wy = camera:tileToWorld(x, y)
      love.graphics.rectangle("fill", wx, wy, tile, tile)
    end
  elseif self.mode == "place" and self.hover and world.registry:get("objects", self.placing).drip then
    local radius = world.registry:get("objects", self.placing).drip.radius
    local hx, hy = Grid.coords(grid, self.hover)
    love.graphics.setColor(visuals.waterZone.ok)
    for y = hy - radius, hy + radius do
      for x = hx - radius, hx + radius do
        if Grid.inBounds(grid, x, y) then
          local wx, wy = camera:tileToWorld(x, y)
          love.graphics.rectangle("fill", wx, wy, tile, tile)
        end
      end
    end
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

function Homestead:drawTopBar(view)
  local world = self.world
  local ui = self.app.ctx.tuning.ui
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, 0, view.w, self.topH)
  local now = Calendar.now(world)
  local hour = math.floor(now.hour)
  local minute = math.floor((now.hour - hour) * 60)
  local season = now.season:gsub("^%l", string.upper)
  local date = string.format("Day %d · %s · %02d:%02d", now.dayOfSeason, season, hour, minute)
  local _, th = Text.measure(date, "body")
  Text.draw(date, 8, math.floor((self.topRowH - th) / 2), { size = "body" })
  -- Stats sit beside the date, or on their own row under it when the view is too narrow.
  local x, rowTop, room
  if self.statRow then
    x, rowTop, room = ui.barPadding, self.topRowH, view.w - 2 * ui.barPadding
  else
    x, rowTop, room = ui.statsAfterDate, 0, view.w - ui.menuWidth - ui.statsAfterDate - ui.barPadding
  end
  local rowH = self.statRow and ui.statRowHeight or self.topRowH
  local gap = self:statsWidth(ui.statGap) <= room and ui.statGap or ui.statMinGap
  for _, s in ipairs(self:stats()) do
    local sprite = Assets.sprite(s[1])
    local y = rowTop + math.floor((rowH - sprite.h) / 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sprite.image, sprite.quad, x, y)
    Text.draw(s[2], x + sprite.w + ui.statIconGap, y + 1, { size = "small" })
    x = x + sprite.w + ui.statIconGap + Text.measure(s[2], "small") + gap
  end
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
  love.graphics.rectangle("fill", 4, self.topH + 4, w, 14, 3, 3)
  Text.draw(text, 4, self.topH + 6, { size = "small", width = w, align = "center", color = color })
end

function Homestead:drawBottomBar(view)
  love.graphics.setColor(theme.colors.panel)
  love.graphics.rectangle("fill", 0, view.h - self.bottomH, view.w, self.bottomH)
end

function Homestead:drawControlBadge(view)
  local ctx = self.app.ctx
  local text, color
  if Actors.homesteader(self.world).asleep then
    text, color = "Sleeping", theme.colors.textDim
  elseif self.session:speed() == 0 then
    text, color = "Paused", theme.colors.accent
  elseif self.world.control == "idle" then
    text, color = "Routine running", theme.colors.accent
  elseif not self.session:canStartRoutine() then
    -- Bedtime (D35): the routine rests too, so a countdown would never finish.
    text, color = "Resting hours", theme.colors.textDim
  else
    local remaining = self:takeoverDelay() - ctx.input:idleSeconds()
    text, color = string.format("Routine in %ds", math.max(0, math.ceil(remaining))), theme.colors.textDim
  end
  local w = Text.measure(text, "small") + 12
  local x, y = view.w - w - 4, view.h - self.bottomH - 18 -- 14 px badge + 4 px gap
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
    if Land.hasWaterTable(world, i) and not world.occupancy[i] then
      local shallow = Land.waterTable(world, i) >= world.tuning.water.table.shallow
      lines[#lines + 1] = shallow and "Water table high: dig here" or "Water table: wells work"
    end
  end
  local obj, anchor = Grid.object(world, i)
  if obj then
    lines[#lines + 1] = obj.name
    if obj.battery then
      lines[#lines + 1] = string.format("Battery %.1f / %d kWh", Power.charge(world, anchor), obj.battery)
    end
    if obj.source then
      lines[#lines + 1] = string.format("Making %.2f / %g kW", Power.outputOf(world, anchor), obj.source.peak)
    end
    if obj.sink then
      local state = Power.sinkState(world, anchor)
      local ratio = math.floor(Power.sinkRatio(world, anchor) * 100 + 0.5)
      lines[#lines + 1] = state == "ok" and "Powered" or state == "short" and string.format("Short of power (%d%%)", ratio) or state == "off" and "Switched off" or "Idle"
    end
    if obj.waterSource then
      if obj.waterSource.stored then
        local units, capacity = Water.stored(world)
        local low = Water.fraction(world) < world.tuning.water.lowFraction
        lines[#lines + 1] = string.format("Water %d / %d%s", math.floor(units), capacity, low and " (low)" or "")
      else
        lines[#lines + 1] = "Fills the bucket here"
      end
    end
    if obj.placeOn == "waterTable" then
      lines[#lines + 1] = string.format("Water table %d%%", math.floor(Land.waterTable(world, anchor) * 100 + 0.5))
    end
    if obj.pump then
      local mode = Water.pumpState(world, anchor)
      local text = {
        pumping = string.format("Pumping %g/h", obj.pump.rate),
        slow = "Pumping slowly",
        nopower = "No power: not pumping",
        full = "Cistern full",
        nocistern = "Needs a cistern",
      }
      lines[#lines + 1] = text[mode]
    end
    if obj.drip then
      local mode = Water.dripState(world, anchor)
      local thirsty = Water.dripThirsty(world, anchor)
      if mode == "dry" then
        lines[#lines + 1] = "DRY: cistern empty"
      elseif mode == "frozen" then
        lines[#lines + 1] = "Frozen ground: idle"
      else
        lines[#lines + 1] = "Watering its zone"
      end
      if thirsty > 0 then
        lines[#lines + 1] = string.format("%d thirsty crops in zone", thirsty)
      end
    end
    if obj.station then
      local batch = Processing.batch(world, anchor)
      if batch and batch.blocked then
        local recipe = world.registry:get("recipes", batch.recipe)
        lines[#lines + 1] = string.format("%s done · %d waiting for storage room", recipe.name, batch.count)
      elseif batch then
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
    local y = view.h - self.bottomH - h - 4
    Draw.panel(4, y, 132, h)
    for n, line in ipairs(lines) do
      Text.draw(line, 10, y + 4 + (n - 1) * 11, { size = "small", color = n == 1 and theme.colors.text or theme.colors.textDim })
    end
  end
  if self.toast then
    local w = Text.measure(self.toast.text, "body") + 16
    local x, y = (view.w - w) / 2, view.h - self.bottomH - 26
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
  ActionRing.draw(self.world, self.camera, view, { top = self.topH, bottom = view.h - self.bottomH })
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
