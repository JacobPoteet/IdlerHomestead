-- Axe and Pail area marks (GDD §9.4, D138, D147, #299): orders on the task board, shared by the hand and the routine,
-- saved with the run.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local Session = require("src.session")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")
local Actors = require("src.sim.systems.actors")
local Marks = require("src.sim.systems.marks")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(control)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(8))
  world.control = control or "active" -- "active": the player is directing, the routine is off
  return world
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

-- Daylight, so nobody is asleep.
local function noon(world)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((12 / 24) - t.startHour / 24) * t.dayLength
end

-- Reachable anchors of objects with this id (any id when nil), ascending.
local function anchorsOf(world, id)
  local out = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if (id == nil or obj.id == id) and Pathfind.toWorkSpot(world, world.state.land.spawn, anchor) then
      out[#out + 1] = anchor
    end
  end
  table.sort(out)
  return out
end

-- `n` dry crops on tilled open ground near the spawn.
local function dryCrops(world, n)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local out = {}
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and #out < n
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and i ~= world.state.land.spawn
        then
          if not world.state.crops[i] then
            world.state.fields.tilled[i] = true
            world.state.crops[i] = { id = "radish", growth = 0, moisture = 0 }
            out[#out + 1] = i
          end
        end
      end
    end
  end
  return out
end

T.test("marks: the Axe marks what a tap would clear, once, and nothing else", function()
  local world = newWorld()
  local clutter = anchorsOf(world, "brush")
  T.truthy(#clutter >= 2, "brush near the spawn")
  T.eq(Marks.add(world, "clear", clutter), #clutter)
  T.eq(Marks.add(world, "clear", clutter), 0, "a second drag over the same tiles adds none")
  T.eq(Marks.count(world, "clear"), #clutter)
  T.eq(Marks.kindAt(world, clutter[1]), "clear")
  local truck = anchorsOf(world, "truck")
  T.eq(Marks.add(world, "clear", truck), 0, "the truck is not clearable")
  T.eq(Marks.add(world, "clear", { world.state.land.spawn }), 0, "bare ground has nothing to mark")
  T.eq(Marks.add(world, "water", clutter), 0, "the Pail marks crops, not brush")
end)

T.test("marks: a mark is cancelled by dragging over it again, and a tile elsewhere is left alone", function()
  local world = newWorld()
  local clutter = anchorsOf(world, "brush")
  Marks.add(world, "clear", clutter)
  T.eq(Marks.remove(world, "clear", { clutter[1] }), 1)
  T.falsy(Marks.has(world, "clear", clutter[1]))
  T.truthy(Marks.has(world, "clear", clutter[2]))
  T.eq(Marks.remove(world, "clear", { clutter[1] }), 0)
  T.eq(Marks.kindAt(world, clutter[1]), nil)
end)

T.test("marks: the Pail marks only crops that are dry", function()
  local world = newWorld()
  local crops = dryCrops(world, 4)
  world.state.crops[crops[4]].moisture = 0.8
  T.eq(Marks.add(world, "water", crops), 3)
  T.falsy(Marks.has(world, "water", crops[4]))
  world.state.crops[crops[1]].moisture = 1 -- rain, or a sprinkler, got there first
  Marks.prune(world)
  T.eq(Marks.count(world, "water"), 2, "a watered crop drops its mark")
end)

T.test("marks: the hand works marked clutter through the task board, in any control mode", function()
  local world = newWorld("active")
  noon(world)
  local clutter = anchorsOf(world, "brush")
  Marks.add(world, "clear", { clutter[1], clutter[2] })
  local cleared = 0
  world.events:on("object.cleared", function()
    cleared = cleared + 1
  end)
  run(world, 120)
  T.eq(cleared, 2)
  T.eq(Marks.count(world, "clear"), 0, "doing a mark removes it")
  T.falsy(world.state.grid.objects[clutter[1]])
end)

T.test("marks: a marked tree is felled although the routine's tree category is off", function()
  local world = newWorld("idle")
  noon(world)
  local trees = anchorsOf(world, "tree")
  T.truthy(#trees > 0, "a tree near the spawn")
  Marks.add(world, "clear", { trees[1] })
  run(world, 150)
  T.falsy(world.state.grid.objects[trees[1]], "the marked tree is down")
  T.eq(Marks.count(world, "clear"), 0)
  -- With nothing marked, the other trees stand: the routine's "Clear trees" is still off (D109).
  T.truthy(world.state.grid.objects[trees[2]] or #trees == 1)
end)

T.test("marks: the Pail's marks are watered with the bucket's waterings, and an empty bucket is refilled", function()
  local world = newWorld("active")
  noon(world)
  local crops = dryCrops(world, 3)
  local hs = Actors.homesteader(world)
  hs.bucket = 2
  T.eq(Marks.add(world, "water", crops), 3)
  run(world, 240)
  T.eq(Marks.count(world, "water"), 0, "every mark was worked")
  for _, i in ipairs(crops) do
    T.truthy(world.state.crops[i].moisture > 0, "crop watered")
  end
end)

T.test("marks: they use the single-tile tasks' rules (room, bucket)", function()
  local world = newWorld("active")
  noon(world)
  local crops = dryCrops(world, 1)
  local hs = Actors.homesteader(world)
  hs.bucket = 0
  Marks.add(world, "water", crops)
  local task = Tasks.get(world, "water_marked")
  T.falsy(task.canDo(world, hs, crops[1]), "an empty bucket cannot water")
  hs.bucket = 1
  T.truthy(task.canDo(world, hs, crops[1]))
  T.falsy(task.canDo(world, hs, crops[1] + 1), "an unmarked tile is not a mark's job")
end)

T.test("marks: the routine and the hand share the same marks", function()
  local hand, auto = newWorld("active"), newWorld("idle")
  for _, world in ipairs({ hand, auto }) do
    noon(world)
    local clutter = anchorsOf(world, "brush")
    Marks.add(world, "clear", { clutter[1] })
  end
  T.eq(Marks.list(hand, "clear")[1], Marks.list(auto, "clear")[1])
  run(hand, 90)
  run(auto, 90)
  T.eq(Marks.count(hand, "clear"), 0)
  T.eq(Marks.count(auto, "clear"), 0)
end)

T.test("marks: they survive a save and a load, and the loaded world still works them", function()
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local session = Session.new({
    store = store,
    slot = 1,
    data = Save.newSlotData("Marks"),
    registry = reg,
    tuning = tun,
    seed = 8,
  })
  local world = session.world
  noon(world)
  local clutter = anchorsOf(world, "brush")
  local crops = dryCrops(world, 2)
  Marks.add(world, "clear", { clutter[1], clutter[2] })
  Marks.add(world, "water", crops)
  local clearList, waterList = Marks.list(world, "clear"), Marks.list(world, "water")
  T.truthy(session:save())
  local loaded = store:read(1)
  local restored = World.new({ registry = reg, tuning = tun }, loaded.run)
  restored.control = "active"
  T.eq(table.concat(Marks.list(restored, "clear"), ","), table.concat(clearList, ","))
  T.eq(table.concat(Marks.list(restored, "water"), ","), table.concat(waterList, ","))
  Actors.homesteader(restored).bucket = 2
  run(restored, 150)
  T.eq(Marks.count(restored, "clear"), 0, "the loaded marks were worked")
  T.eq(Marks.count(restored, "water"), 0)
end)
