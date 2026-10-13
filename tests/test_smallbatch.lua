-- The small batch (D76-D78): scrolling power panel and on-demand network numbers (#82), the Plan
-- tool deselecting after a plan (#192), and game time standing still in town (#191).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")
local PowerPanel = require("src.scenes.power")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function place(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

-- Power: on-demand numbers (#82) ----------------------------------------------------------------------

local function withoutFlow(world)
  local copy = serialize.decode(serialize.encode(world.state))
  copy.power.flow = nil
  return serialize.encode(copy)
end

T.test("power refresh: a switch shows its effect without a tick, and nothing else moves", function()
  local world = newWorld()
  local bank = place(world, "battery_bank")
  local freezer = place(world, "chest_freezer")
  Power.add(world, bank, 5)
  world:tick(STEP)
  local demand = Power.flow(world).demand
  T.truthy(demand > 0, "the freezer asks for power")
  Power.setEnabled(world, freezer, false)
  T.eq(Power.flow(world).demand, demand, "stale until refreshed")
  local before = withoutFlow(world)
  Power.refresh(world)
  T.eq(Power.flow(world).demand, 0, "off: nothing is asked for")
  T.eq(Power.sinkState(world, freezer), "off")
  T.eq(withoutFlow(world), before, "refresh changes only the displayed flow")
  Power.setEnabled(world, freezer, true)
  before = withoutFlow(world)
  Power.refresh(world)
  T.near(Power.flow(world).demand, demand, 1e-9)
  T.near(Power.flow(world).served, demand, 1e-9, "served in full")
  T.eq(withoutFlow(world), before, "still nothing else moved")
end)

T.test("power refresh: matches what the next tick computes", function()
  local world = newWorld(3)
  world.state.calendar.elapsed = (0.5 - tun.time.startHour / 24) * tun.time.dayLength -- noon: the sun is steady
  place(world, "battery_bank")
  local freezer = place(world, "chest_freezer")
  place(world, "chest_freezer")
  world:tick(STEP)
  Power.setEnabled(world, freezer, false)
  Power.refresh(world)
  local f = Power.flow(world)
  local demand, served, gen = f.demand, f.served, f.generation
  world:tick(STEP)
  local g = Power.flow(world)
  T.near(g.demand, demand, 1e-9)
  T.near(g.served, served, 1e-9)
  T.near(g.generation, gen, 1e-3, "the sun moves a hair in one tick")
end)

T.test("power refresh: reordering priorities shows at once and does not break determinism", function()
  local a, b = newWorld(5), newWorld(5)
  for _, w in ipairs({ a, b }) do
    place(w, "chest_freezer")
    place(w, "lamp")
    w:tick(STEP)
  end
  Power.moveTier(a, "freezer", -1)
  Power.refresh(a)
  Power.moveTier(b, "freezer", -1)
  for _ = 1, 20 do
    a:tick(STEP)
    b:tick(STEP)
  end
  T.eq(withoutFlow(a), withoutFlow(b), "a refresh in the middle leaves the run identical")
end)

-- Power panel scrolling (#82) -------------------------------------------------------------------------

local function panelFor(world, w, h)
  local panel = PowerPanel.new(world)
  panel.app = { ctx = { tuning = tun }, view = { w = w, h = h, scale = 1 }, pop = function() end }
  panel:enter()
  panel:resize({ w = w, h = h })
  return panel
end

local function manyDevices(world, n)
  place(world, "battery_bank")
  for _ = 1, n do
    place(world, "chest_freezer")
  end
end

local function switchCount(panel)
  return #panel.rowButtons.list
end

local VIEWS = { { 1280, 720 }, { 390, 844 }, { 844, 390 } }

T.test("power panel: a long device list overflows its window and every switch is reachable by scrolling", function()
  for _, v in ipairs(VIEWS) do
    local world = newWorld()
    manyDevices(world, 30)
    world:tick(STEP)
    local panel = panelFor(world, v[1], v[2])
    T.truthy(panel.list.overflow, "30 devices overflow at " .. v[1] .. "x" .. v[2])
    local view = panel.list.view
    T.truthy(view.y + view.h <= panel.box.y + panel.box.h, "the window stays inside the panel")
    local seen = {}
    local offset, guard = 0, 0
    repeat
      panel.list.offset = offset
      panel:layout()
      for _, button in ipairs(panel.rowButtons.list) do
        seen[button.y .. ":" .. offset] = true
      end
      offset = offset + view.h / 2
      guard = guard + 1
    until offset > panel.list.contentH or guard > 200
    -- Scroll to the very end: the last switch sits fully inside the window.
    panel.list.offset = panel.list.contentH
    panel:layout()
    local last = panel.rowButtons.list[#panel.rowButtons.list]
    T.truthy(last, "a switch is visible at the end")
    T.truthy(last.y + last.h <= view.y + view.h + 1, "the last switch is inside the window")
    T.truthy(last.y >= view.y - 1)
  end
end)

T.test("power panel: row buttons answer only inside the window; wheel and drag scroll", function()
  local world = newWorld()
  manyDevices(world, 30)
  world:tick(STEP)
  local panel = panelFor(world, 390, 844)
  T.eq(panel.list.offset, 0)
  panel:action("zoom", { steps = -2 })
  T.truthy(panel.list.offset > 0, "wheel down scrolls")
  local scrolled = panel.list.offset
  panel:action("pan", { dy = -30 })
  T.truthy(panel.list.offset > scrolled, "dragging up shows later rows")
  panel:action("pan", { dy = 10000 })
  T.eq(panel.list.offset, 0, "clamped at the top")
  -- A button half-scrolled above the window must not respond to a tap outside the window.
  panel.list.offset = 30
  panel:layout()
  local outside
  for _, button in ipairs(panel.rowButtons.list) do
    if button.y < panel.list.view.y then
      outside = button
    end
  end
  if outside then
    local before = {}
    for _, s in ipairs(Power.sinkList(world)) do
      before[s.anchor] = s.enabled
    end
    panel:action("select", { x = outside.x + 2, y = panel.list.view.y - 2 })
    for _, s in ipairs(Power.sinkList(world)) do
      T.eq(s.enabled, before[s.anchor], "nothing switched from outside the window")
    end
  end
end)

T.test("power panel: tapping a switch while paused updates the numbers at once", function()
  local world = newWorld()
  manyDevices(world, 3)
  world:tick(STEP)
  local panel = panelFor(world, 1280, 720)
  local demand = Power.flow(world).demand
  T.truthy(demand > 0)
  local button = panel.rowButtons.list[1]
  T.eq(button.label, "On")
  panel:action("select", { x = button.x + 2, y = button.y + 2 })
  T.truthy(Power.flow(world).demand < demand, "demand dropped without a tick")
  T.eq(panel.rowButtons.list[1].label, "Off")
  T.truthy(switchCount(panel) >= 1)
end)

-- Plan tool (#192) ------------------------------------------------------------------------------------

local Homestead = require("src.scenes.homestead")

--- A stand-in for the scene with just what Homestead.tap's plan branch touches.
local function planScene()
  local scene = { mode = "plan", seed = "carrot", planStart = nil, selected = nil, applied = {}, layouts = 0 }
  function scene:applyPlan(a, b)
    self.applied[#self.applied + 1] = { a, b }
  end
  function scene:layout()
    self.layouts = self.layouts + 1
  end
  scene.tap = Homestead.tap
  return scene
end

T.test("plan tool: two taps place a plan and the hand goes back to normal, seed kept", function()
  local scene = planScene()
  scene:tap(10)
  T.eq(scene.mode, "plan", "after the first corner the tool is still on")
  T.eq(scene.planStart, 10)
  scene:tap(25)
  T.eq(#scene.applied, 1)
  T.eq(scene.mode, "act", "one plan per selection")
  T.eq(scene.planStart, nil)
  T.eq(scene.seed, "carrot", "the seed stays in hand")
  T.truthy(scene.layouts >= 1, "the toolbar is rebuilt so Plan is no longer lit")
end)

T.test("plan tool: Shift keeps the tool on for several plans", function()
  local scene = planScene()
  local real = love.keyboard
  love.keyboard = { isDown = function() return true end }
  local ok, err = pcall(function()
    scene:tap(1)
    scene:tap(2)
    T.eq(scene.mode, "plan")
    scene:tap(3)
    scene:tap(4)
    T.eq(#scene.applied, 2)
  end)
  love.keyboard = real
  if not ok then
    error(err, 0)
  end
end)

-- Town pauses game time (#191) ------------------------------------------------------------------------

local Session = require("src.session")
local Actors = require("src.sim.systems.actors")
local Market = require("src.sim.systems.market")
local Calendar = require("src.sim.systems.calendar")

local function newSession(seed, run)
  return Session.new({
    store = { write = function() return true end },
    slot = 1,
    data = { meta = {}, run = run or World.newState(seed or 1), header = {} },
    registry = reg,
    tuning = tun,
  })
end

local function sendToTown(session)
  session.world.state.power.charge[session.world.state.land.truck] = tun.economy.tripCost
  T.truthy(Market.startTrip(session.world))
end

T.test("town: the sim stands still, the chosen speed comes back on the drive home", function()
  local s = newSession()
  s:setSpeed(4)
  s:update(1)
  local elapsed = s.world.state.calendar.elapsed
  T.truthy(elapsed > 0)
  sendToTown(s)
  T.eq(s:effectiveSpeed(), 0)
  s:update(5)
  T.eq(s.world.state.calendar.elapsed, elapsed, "no game time passes in town")
  T.eq(s:speed(), 4, "the player's speed is untouched")
  T.eq(s:cycleSpeed(tun.time.speedSteps), 4, "the speed does not change in town")
  Market.endTrip(s.world)
  T.eq(s:effectiveSpeed(), 4)
  s:update(1)
  T.truthy(s.world.state.calendar.elapsed > elapsed, "time runs again at the old speed")
end)

T.test("town: sleep fast-forward does not engage", function()
  local s = newSession()
  Actors.homesteader(s.world).asleep = true
  T.truthy(s:effectiveSpeed() >= tun.time.sleepSpeed, "asleep at home: fast")
  sendToTown(s)
  T.eq(s:effectiveSpeed(), 0)
  local elapsed = s.world.state.calendar.elapsed
  s:update(3)
  T.eq(s.world.state.calendar.elapsed, elapsed)
end)

T.test("town: a save written in town loads paused in town", function()
  local s = newSession(7)
  sendToTown(s)
  T.truthy(s:save())
  local run = serialize.decode(serialize.encode(s.data.run))
  local loaded = newSession(7, run)
  T.truthy(loaded:inTown())
  T.eq(loaded:effectiveSpeed(), 0)
  local elapsed = loaded.world.state.calendar.elapsed
  loaded:update(3)
  T.eq(loaded.world.state.calendar.elapsed, elapsed)
end)

T.test("town: a trip costs no game time, and the run is the same as one without the wait", function()
  local a, b = newSession(11), newSession(11)
  for _, s in ipairs({ a, b }) do
    s:setSpeed(1)
    s:update(2)
  end
  sendToTown(a)
  sendToTown(b)
  a:update(60) -- a lingers in town
  Market.endTrip(a.world)
  Market.endTrip(b.world)
  for _ = 1, 40 do
    a:update(0.25)
    b:update(0.25)
  end
  T.eq(Calendar.now(a.world).hour, Calendar.now(b.world).hour)
  a.world.state.market.tripReady, b.world.state.market.tripReady = nil, nil
  T.eq(serialize.encode(a.world.state), serialize.encode(b.world.state), "waiting in town changes nothing")
end)

-- Plan latch (#205, D94) -----------------------------------------------------------------------------

--- A stand-in with just what Homestead.pressPlan and the plan branch of tap touch.
local function latchScene()
  local scene = planScene()
  scene.mode, scene.seed = "act", "radish"
  scene.toasts = {}
  scene.app = { ctx = { tuning = tun } }
  scene.world = { registry = reg }
  function scene:showToast(text)
    self.toasts[#self.toasts + 1] = text
  end
  function scene:setHand(seed)
    self.seed, self.mode, self.planStart, self.planLatch, self.planTapAt = seed, "act", nil, false, nil
  end
  scene.pressPlan = Homestead.pressPlan
  return scene
end

T.test("plan latch: a double tap keeps Plan on for several plans; a tap unlatches", function()
  local scene = latchScene()
  scene:pressPlan(10)
  T.eq(scene.mode, "plan")
  T.falsy(scene.planLatch)
  scene:pressPlan(10 + tun.ui.planLatchWindow / 2)
  T.truthy(scene.planLatch, "the second quick tap latches")
  T.eq(scene.mode, "plan")
  scene:tap(1)
  scene:tap(2)
  scene:tap(3)
  scene:tap(4)
  T.eq(#scene.applied, 2)
  T.eq(scene.mode, "plan", "still on after two plans")
  scene:pressPlan(20)
  T.eq(scene.mode, "act", "a tap while latched turns it off")
  T.falsy(scene.planLatch)
end)

T.test("plan latch: a slow second tap just turns Plan off; a latch does not leak into the next use", function()
  local scene = latchScene()
  scene:pressPlan(10)
  scene:pressPlan(10 + tun.ui.planLatchWindow + 1)
  T.eq(scene.mode, "act")
  T.falsy(scene.planLatch)
  scene:pressPlan(30)
  T.eq(scene.mode, "plan")
  scene:pressPlan(30.1)
  T.truthy(scene.planLatch)
  scene:setHand(nil)
  scene:pressPlan(40)
  T.falsy(scene.planLatch, "a fresh Plan starts unlatched")
  scene:tap(1)
  scene:tap(2)
  T.eq(scene.mode, "act", "one plan per selection, as before")
end)

T.test("plan latch: the captions say how to keep it on", function()
  local c = tun.ui.captions
  T.truthy(c.planKept:find("kept on"))
  T.truthy(c.planSeed:find("double%-tap"))
end)
