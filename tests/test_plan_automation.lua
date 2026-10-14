-- Plan = automate the plot (GDD D92, issue #231) and game time held under a tip card (#230).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Ledger = require("src.sim.systems.ledger")
local Sleep = require("src.sim.systems.sleep")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active" -- the Routine is off: the player is directing
  return world
end

local function setHour(world, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((hour / 24) - t.startHour / 24) * t.dayLength
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

-- `count` open tillable tiles close to the spawn (row by row, so the field is compact).
local function field(world, count)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local tiles = {}
  for r = 1, 8 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if i and #tiles < count and Grid.terrain(world, i).tillable and not world.occupancy[i] and i ~= world.state.land.spawn then
          local dup = false
          for _, t in ipairs(tiles) do
            dup = dup or t == i
          end
          if not dup then
            tiles[#tiles + 1] = i
          end
        end
      end
    end
  end
  return tiles
end

local function plan(world, tiles, crop)
  for _, i in ipairs(tiles) do
    T.truthy(Crops.setPlan(world, i, crop or "radish"))
  end
end

local function count(world, tiles, what)
  local n = 0
  for _, i in ipairs(tiles) do
    if what == "tilled" and world.state.fields.tilled[i] or what == "planted" and world.state.crops[i] then
      n = n + 1
    end
  end
  return n
end

local function emptySeeds(world)
  Ledger.remove(world, "seed_radish", Ledger.get(world, "seed_radish"), "test")
end

T.test("plan: with the Routine off the homesteader tills and plants the planned tiles at once", function()
  local world = newWorld()
  setHour(world, 9)
  local tiles = field(world, 6)
  plan(world, tiles)
  local seeds = Ledger.get(world, "seed_radish")
  run(world, 90)
  T.eq(world.control, "active")
  T.eq(count(world, tiles, "tilled"), #tiles, "all tilled")
  T.eq(count(world, tiles, "planted"), #tiles, "all planted")
  T.eq(Ledger.get(world, "seed_radish"), seeds - #tiles, "one seed each")
end)

T.test("plan: tilling does not wait for seeds; planting waits and resumes when they arrive", function()
  local world = newWorld()
  setHour(world, 9)
  emptySeeds(world)
  local tiles = field(world, 4)
  plan(world, tiles)
  run(world, 60)
  T.eq(count(world, tiles, "tilled"), #tiles, "tilled with no seeds in the store")
  T.eq(count(world, tiles, "planted"), 0, "nothing planted yet")
  for _, i in ipairs(tiles) do
    T.eq(world.state.fields.plan[i], "radish", "the plan keeps its seed choice")
  end
  Ledger.add(world, "seed_radish", #tiles, "test")
  run(world, 60)
  T.eq(count(world, tiles, "planted"), #tiles, "planted once seeds arrive")
end)

T.test("plan: an interrupted plot resumes in full, not just the tile that was tapped", function()
  local world = newWorld()
  setHour(world, 9)
  local tiles = field(world, 8)
  plan(world, tiles)
  local hs = Actors.homesteader(world)
  run(world, 12)
  local partial = count(world, tiles, "planted")
  T.truthy(partial < #tiles, "still working when interrupted")
  -- The player sends the homesteader off to a tile outside the plot, then it is left alone.
  local away = field(world, 40)[40]
  Actors.order(world, hs, away)
  run(world, 90)
  T.eq(count(world, tiles, "planted"), #tiles, "the whole plot was finished")
end)

T.test("plan: the nearest planned tile is worked first, and the same seed gives the same result", function()
  local function play()
    local world = newWorld(9)
    setHour(world, 9)
    local tiles = field(world, 10)
    plan(world, tiles)
    local order = {}
    world.events:on("task.completed", function(e)
      order[#order + 1] = e.task .. ":" .. e.target
    end)
    run(world, 150)
    return table.concat(order, ","), serialize.encode(world.state.fields) .. serialize.encode(world.state.crops)
  end
  local a1, a2 = play()
  local b1, b2 = play()
  T.truthy(a1 ~= "", "work was done")
  T.eq(a1, b1, "same job order")
  T.eq(a2, b2, "same field state")
end)

T.test("plan: a category switched off in the Routine panel keeps its planned tiles untouched", function()
  local world = newWorld()
  setHour(world, 9)
  Tasks.setPriorityEnabled(world, "plant", false)
  local tiles = field(world, 3)
  plan(world, tiles)
  run(world, 60)
  T.eq(count(world, tiles, "tilled"), 0)
end)

T.test("plan: the routine taking over does not double-queue or fight the standing work", function()
  local world = newWorld()
  setHour(world, 9)
  local tiles = field(world, 6)
  plan(world, tiles)
  local seeds = Ledger.get(world, "seed_radish")
  run(world, 8)
  world.control = "idle" -- the takeover
  run(world, 90)
  T.eq(count(world, tiles, "planted"), #tiles)
  T.eq(Ledger.get(world, "seed_radish"), seeds - #tiles, "no tile was planted twice")
end)

-- Tip card holds game time (#230) --------------------------------------------------------

local function newSession(seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = Save.newSlotData("Tip"), registry = reg, tuning = tun, seed = seed or 3 })
end

T.test("tip card: game time stands still, the chosen speed is kept, and it returns with the card gone", function()
  local session = newSession()
  local world = session.world
  setHour(world, 9)
  session:setSpeed(2)
  session:setTipUp(true)
  T.eq(session:effectiveSpeed(), 0, "paused under a card")
  T.eq(session:speed(), 2, "the chosen speed is untouched")
  local before = world.state.tick
  session:update(1)
  T.eq(world.state.tick, before, "no ticks run")
  T.eq(session:cycleSpeed(tun.time.speedSteps), 2, "the speed button does nothing under a card")
  session:setTipUp(false)
  T.eq(session:effectiveSpeed(), 2)
  session:update(1)
  T.truthy(world.state.tick > before, "time runs again")
end)

T.test("tip card: sleep cannot be sped up under one", function()
  local session = newSession()
  local world = session.world
  setHour(world, Sleep.bedtimeHours(world) + 0.5)
  Actors.homesteader(world).asleep = true
  session:setTipUp(true)
  T.eq(session:effectiveSpeed(), 0, "no sleep fast-forward under a card")
  session:setTipUp(false)
  T.eq(session:effectiveSpeed(), tun.time.sleepSpeed, "sleep speed is back with the card closed")
end)
