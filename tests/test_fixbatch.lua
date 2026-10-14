-- Small-fix UX bundle (D93): the "nothing to do" nudge (#119), the held/persistent nudge (#120),
-- Pantry row pitch (#174), and discarding a station's waiting output (#135).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Inventory = require("src.sim.systems.inventory")
local Processing = require("src.sim.systems.processing")
local Routine = require("src.sim.systems.routine")
local Tasks = require("src.sim.systems.tasks")
local Actors = require("src.sim.systems.actors")
local PantryLayout = require("src.ui.pantry_layout")
local Panel = require("src.ui.panel")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((hour / 24) - t.startHour / 24) * t.dayLength
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

local function freeTileNearSpawn(world, objectId)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        if Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if Inventory.canPlace(world, objectId, i) then
            return i
          end
        end
      end
    end
  end
end

--- Keep the homesteader on a player order (a walk to a nearby tile) so it always has a job in hand.
local function keepBusy(world)
  local hs = Actors.homesteader(world)
  if not hs.job and not hs.order then
    Actors.order(world, hs, freeTileNearSpawn(world, "smoker"), {})
  end
end

--- Every priority category off: the routine has nothing to find.
local function nothingEnabled(world)
  for _, e in ipairs(world.state.priorities) do
    e.enabled = false
  end
end

local function run(world, seconds, control, busy)
  for _ = 1, math.floor(seconds / STEP) do
    world.control = control or world.control
    if busy then
      keepBusy(world)
    end
    world:tick(STEP)
    setTime(world, 10) -- keep it daytime
  end
end

-- #119: routine on, no job found -------------------------------------------------------------------

T.test("nothing to do: fires after nothingAfter seconds with the routine on, then is rate limited", function()
  local world = newWorld(3)
  nothingEnabled(world)
  setTime(world, 10)
  local hints = collect(world, "routine.nothingToDo")
  local idleHints = collect(world, "routine.idleHint")
  run(world, 1, "idle") -- settle (wake, first rechecks)
  world.state.routine.noJobFor = 0
  world.state.routine.cooldown = 0
  run(world, tun.idle.nothingAfter - 3, "idle")
  T.eq(#hints, 0, "not yet")
  T.eq(Routine.hintKind(world), nil)
  run(world, 6, "idle")
  T.eq(#hints, 1, "fired")
  T.eq(Routine.hintKind(world), "nothing", "the HUD marker holds")
  run(world, tun.idle.hintInterval - 8, "idle")
  T.eq(#hints, 1, "rate limited")
  run(world, 10, "idle")
  T.eq(#hints, 2, "fires again after the interval")
  T.eq(#idleHints, 0, "the routine-off hint stays silent while the routine runs")
end)

T.test("nothing to do: silent while the routine has a job, and the counter resets", function()
  local world = newWorld(3)
  setTime(world, 10)
  local hints = collect(world, "routine.nothingToDo")
  for _ = 1, math.floor(tun.idle.nothingAfter * 3 / STEP) do
    world.control = "idle"
    keepBusy(world) -- any order or job in hand counts as work (planned tiles included, D92)
    world:tick(STEP)
    setTime(world, 10)
  end
  T.eq(#hints, 0)
  T.eq(world.state.routine.noJobFor or 0, 0)
end)

T.test("idle hint kind: routine off reads idle after hintAfter, nil while busy", function()
  local world = newWorld(3)
  nothingEnabled(world)
  setTime(world, 10)
  run(world, tun.idle.hintAfter + 2, "active")
  T.eq(Routine.hintKind(world), "idle")
  run(world, 2, "active", true)
  T.eq(Routine.hintKind(world), nil, "a job in hand clears it")
end)

T.test("nothing to do: deterministic", function()
  local function play()
    local world = newWorld(4)
    nothingEnabled(world)
    local seen = {}
    world.events:on("routine.nothingToDo", function()
      seen[#seen + 1] = world.state.tick
    end)
    run(world, tun.idle.hintInterval * 2, "idle")
    return table.concat(seen, ","), serialize.encode(world.state)
  end
  local a, sa = play()
  local b, sb = play()
  T.eq(a, b)
  T.eq(sa, sb)
end)

-- #174: Pantry row pitch -----------------------------------------------------------------------------

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

T.test("pantry layout: buttons never overlap, in a row or between rows, at every view size", function()
  local sizes = { { 1280, 720 }, { 390, 844 }, { 844, 390 } }
  for _, minTouch in ipairs({ tun.input.minTouchTarget, 32, 44 }) do
    for _, sz in ipairs(sizes) do
      local box = Panel.box({ w = sz[1], h = sz[2] }, 400, sz[2] - 16)
      local right = box.x + box.w
      local rows, y = {}, 0
      -- A mix like the real list: a perishable with a note, then plain rows with and without a stand button.
      local pattern = { { true, true }, { false, true }, { false, true }, { false, false }, { true, true }, { false, true } }
      for _, p in ipairs(pattern) do
        rows[#rows + 1] = PantryLayout.buttons(right, y, minTouch, p[2])
        y = y + PantryLayout.rowHeight(minTouch) + (p[1] and PantryLayout.NOTE_H or 0)
      end
      T.truthy(PantryLayout.rowHeight(minTouch) >= minTouch, "pitch is at least a touch target")
      local all = {}
      for r, row in ipairs(rows) do
        for name, rect in pairs(row) do
          T.truthy(rect.h >= minTouch and rect.w >= minTouch, "touch size " .. name)
          T.truthy(rect.x >= box.x, "inside the panel")
          all[#all + 1] = { r = r, name = name, rect = rect }
        end
      end
      for a = 1, #all do
        for b = a + 1, #all do
          T.falsy(overlaps(all[a].rect, all[b].rect), string.format("%dx%d min %d: row %d %s vs row %d %s", sz[1], sz[2], minTouch, all[a].r, all[a].name, all[b].r, all[b].name))
        end
      end
    end
  end
end)

-- #135: discard a station's waiting output ------------------------------------------------------------


local function blockedSmoker(world)
  world.control = "idle"
  for _, e in ipairs(world.state.priorities) do
    e.enabled = e.category == "process"
  end
  Inventory.addObject(world, "smoker")
  local tile = freeTileNearSpawn(world, "smoker")
  T.truthy(Inventory.place(world, "smoker", tile))
  Ledger.add(world, "creek_chub", 6)
  Ledger.add(world, "wood", 10)
  for _ = 1, math.floor(30 / STEP) do
    world:tick(STEP)
  end
  Ledger.setCapacity(world, "smoked_fish", 0)
  for _ = 1, math.floor((reg:get("recipes", "smoke_fish").hours * HOUR + 1) / STEP) do
    world:tick(STEP)
  end
  local _, anchor = Grid.object(world, tile)
  return anchor
end

T.test("discard: clears the blocked batch and frees the station", function()
  local world = newWorld(6)
  local anchor = blockedSmoker(world)
  T.eq(#Processing.blockedBatches(world), 1)
  local discarded = collect(world, "processing.discarded")
  T.eq(Processing.discard(world, anchor), 4)
  T.eq(#discarded, 1)
  T.eq(discarded[1].output, "smoked_fish")
  T.falsy(Processing.batch(world, anchor), "station is free")
  T.eq(#Processing.blockedBatches(world), 0)
  T.eq(Ledger.get(world, "smoked_fish"), 0, "nothing reached stock")
  T.eq(Processing.discard(world, anchor), nil, "nothing left to discard")
end)

T.test("discard: refuses a batch that is still running", function()
  local world = newWorld(6)
  world.control = "idle"
  Inventory.addObject(world, "smoker")
  local tile = freeTileNearSpawn(world, "smoker")
  Inventory.place(world, "smoker", tile)
  local _, anchor = Grid.object(world, tile)
  world.state.processing[anchor] = { recipe = "smoke_fish", count = 3, remaining = 100 }
  T.eq(Processing.discard(world, anchor), nil)
  T.truthy(Processing.batch(world, anchor), "a running batch is untouched")
end)

T.test("full pill: only stores that are holding something back are blocking", function()
  local world = newWorld(5)
  local hs = Actors.homesteader(world)
  -- A full store with nothing waiting on it is not blocking.
  Ledger.setCapacity(world, "radish", 0)
  T.falsy(Tasks.blockedResources(world, hs).radish, "a quiet full store")
  -- A mature crop that cannot be harvested for lack of room is.
  local tile = freeTileNearSpawn(world, "smoker")
  world.state.crops[tile] = { id = "radish", growth = 1, moisture = 1 }
  T.truthy(Tasks.blockedResources(world, hs).radish, "a harvest is held back")
  Ledger.setCapacity(world, "radish", nil)
  T.falsy(Tasks.blockedResources(world, hs).radish, "room again")
end)
