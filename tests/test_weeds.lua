-- Weeds (PLAN_DEPTH 8.3, D180, issue #366): they sprout and grow on field tiles on a timer, cut yield, are pulled by
-- a routine-able task, and straw mulch holds them back.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Gridpack = require("src.core.gridpack")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Save = require("src.core.save")
local Soil = require("src.sim.systems.soil")
local Tasks = require("src.sim.systems.tasks")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.soil
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SUMMER, WINTER = DPS + 1, 3 * DPS + 1

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function newDay(world)
  world.events:emit("calendar.newDay", { day = 1, season = "spring", year = 1 })
end

--- `n` free tillable tiles near the spawn, tilled (a field), nearest first.
local function field(world, n)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local tiles = {}
  for r = 1, 12 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and #tiles < n
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and not Crops.tileInUse(world, i)
          and i ~= world.state.land.spawn
        then
          world.state.fields.tilled[i] = true
          tiles[#tiles + 1] = i
        end
      end
    end
  end
  T.eq(#tiles, n, "room for the field")
  return tiles
end

local function weedCount(world)
  return #Soil.weedTiles(world)
end

-- Sprouting and growing ------------------------------------------------------------------------------

T.test("weeds: field tiles sprout on a timer, grass never does, and a sprout grows by weedRate a day", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local tiles = field(world, 30)
  local grass
  for i = 1, #world.state.grid.terrain do
    if Grid.terrain(world, i).tillable and not Crops.tileInUse(world, i) and not world.occupancy[i] then
      grass = i
      break
    end
  end
  local sprouted = {}
  world.events:on("soil.weeds", function(e)
    if e.cause == "sprout" then
      sprouted[#sprouted + 1] = e.tile
    end
  end)
  for _ = 1, 10 do
    newDay(world)
  end
  T.truthy(#sprouted > 0, "ten days over thirty tiles sprout some")
  T.eq(Soil.weeds(world, grass), 0, "open ground grows none")
  local inField = {}
  for _, i in ipairs(tiles) do
    inField[i] = true
  end
  for _, i in ipairs(Soil.weedTiles(world)) do
    T.truthy(inField[i], "weeds only on the field")
    T.truthy(Soil.weeds(world, i) >= cfg.weedStart, "at least a sprout")
  end
  -- one tile on its own: a sprout then grows by weedRate each day, capped at 1
  local lone = newWorld()
  setTime(lone, SUMMER + 2)
  local i = field(lone, 1)[1]
  lone.state.soil.weeds[i] = cfg.weedStart
  newDay(lone)
  T.near(Soil.weeds(lone, i), cfg.weedStart + cfg.weedRate, 0.001)
  lone.state.soil.weeds[i] = 0.98
  newDay(lone)
  T.eq(Soil.weeds(lone, i), 1, "capped at full")
end)

T.test("weeds: the same seed grows the same weeds, on their own stream", function()
  local function run(seed)
    local world = newWorld(seed)
    setTime(world, SUMMER + 2)
    field(world, 20)
    for _ = 1, 8 do
      newDay(world)
    end
    return serialize.encode(world.state.soil.weeds), world
  end
  local a, world = run(6)
  local b = run(6)
  T.eq(a, b)
  T.truthy(world.state.rng.weeds ~= nil, "the weeds stream exists")
  T.truthy(a ~= run(7), "another seed, other weeds")
end)

T.test(
  "weeds: nothing sprouts or grows while the ground is frozen, and a tile that leaves the field drops its weeds",
  function()
    local world = newWorld()
    setTime(world, WINTER + 2)
    local tiles = field(world, 20)
    world.state.soil.weeds[tiles[1]] = 0.3
    for _ = 1, 10 do
      newDay(world)
    end
    T.eq(weedCount(world), 1, "frozen: no new weeds")
    T.near(Soil.weeds(world, tiles[1]), 0.3, 0.001, "and none grow")
    world.state.fields.tilled[tiles[1]] = nil -- untilled
    newDay(world)
    T.eq(Soil.weeds(world, tiles[1]), 0, "back to grass, the weeds go")
  end
)

-- Yield and quality -----------------------------------------------------------------------------------

T.test("weeds: they cut the yield by weedCut x level, never to zero, and the harvest reports them", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = field(world, 1)[1]
  T.eq(Soil.weedFactor(world, i), 1, "clean ground: no cut")
  local clean = Soil.yieldMultiplier(world, i)
  world.state.soil.weeds[i] = 1
  T.near(Soil.yieldMultiplier(world, i), clean * (1 - cfg.weedCut), 1e-9)
  T.truthy(Soil.yieldMultiplier(world, i) > 0, "never zero")
  world.state.crops[i] = { id = "potato", growth = 1, moisture = 1 }
  Ledger.add(world, "potato", 0)
  local seen
  world.events:on("crop.harvested", function(e)
    seen = e
  end)
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
  T.eq(seen.weeds, 1)
  T.truthy(seen.amount >= 1, "a harvest still gives something")
end)

-- Pulling ---------------------------------------------------------------------------------------------

T.test(
  "weeds: the weed task is routine-able above weedPullAt, any weedy tile by hand, and it clears the tile",
  function()
    local world = newWorld()
    setTime(world, SUMMER + 2)
    local tiles = field(world, 2)
    local weed = Tasks.get(world, "weed")
    local hs = Actors.homesteader(world)
    T.eq(weed.category, "maintenance")
    T.eq(world.registry:get("task_categories", "maintenance").id, "maintenance")
    world.state.soil.weeds[tiles[1]] = cfg.weedPullAt - 0.1
    world.state.soil.weeds[tiles[2]] = cfg.weedPullAt
    local offered = {}
    weed.candidates(world, hs, function(i)
      offered[#offered + 1] = i
    end)
    T.same(offered, { tiles[2] }, "the routine only goes to tiles from weedPullAt")
    T.falsy(weed.canDo(world, hs, tiles[1], nil), "the routine leaves a light sprout")
    T.truthy(weed.canDo(world, hs, tiles[1], {}), "a tap pulls any weedy tile")
    T.falsy(weed.canDo(world, hs, tiles[1] + 1000, {}), "nothing to pull on a clean tile")
    local pulled
    world.events:on("weed.pulled", function(e)
      pulled = e
    end)
    weed.complete(world, hs, tiles[2])
    T.eq(Soil.weeds(world, tiles[2]), 0)
    T.eq(pulled.tile, tiles[2])
    T.eq(weedCount(world), 1)
  end
)

T.test(
  "weeds: a tap on a weedy tile picks Weed after Harvest and Water, and the category sits after Till & plant",
  function()
    local world = newWorld()
    setTime(world, SUMMER + 2)
    local i = field(world, 1)[1]
    world.state.soil.weeds[i] = 0.5
    local hs = Actors.homesteader(world)
    T.eq(Tasks.taskForTile(world, hs, i, {}).id, "weed")
    world.state.crops[i] = { id = "radish", growth = 0.5, moisture = 0 }
    hs.bucket = 1
    T.eq(Tasks.taskForTile(world, hs, i, {}).id, "water_crop", "a dry crop is watered first")
    local order = {}
    for n, entry in ipairs(world.state.priorities) do
      order[entry.category] = n
    end
    T.truthy(order.maintenance > order.harvest and order.maintenance > order.water, "after harvest and water")
    T.truthy(order.maintenance < order.clear, "before clearing")
    T.truthy(world.state.priorities[order.maintenance].enabled, "on by default")
  end
)

T.test("weeds: the idle routine keeps a field clean at the base idle rate", function()
  local function run(control)
    local world = newWorld(3)
    world.control = control
    setTime(world, SUMMER + 2, 6)
    local tiles = field(world, 12)
    for _, i in ipairs(tiles) do
      world.state.fields.plan[i] = "radish" -- planned, so the routine does not untill them as leftovers
    end
    Ledger.remove(world, "seed_radish", Ledger.get(world, "seed_radish"), "test") -- and has nothing to plant
    local worst = 0
    local dayTicks = math.floor(tun.time.dayLength / STEP)
    for _ = 1, 6 do
      for _ = 1, dayTicks do
        world:tick(STEP)
      end
      for _, i in ipairs(tiles) do
        worst = math.max(worst, Soil.weeds(world, i))
      end
    end
    return worst
  end
  T.truthy(run("active") >= cfg.weedHigh, "left alone, a field grows overgrown within six days")
  T.truthy(run("idle") < cfg.weedHigh, "the routine pulled them as they came")
end)

-- Mulch -----------------------------------------------------------------------------------------------

T.test("weeds: straw mulch (weedGuard) cuts sprouting and growth, and the rolls do not change", function()
  local function run(mulched)
    local world = newWorld(5)
    setTime(world, SUMMER + 2)
    field(world, 40)
    if mulched then
      Inventory.addEquipment(world, "straw_mulch")
    end
    for _ = 1, 12 do
      newDay(world)
    end
    local total = 0
    for _, i in ipairs(Soil.weedTiles(world)) do
      total = total + Soil.weeds(world, i)
    end
    return total, weedCount(world), world:rng("weeds"):float()
  end
  local total0, count0, next0 = run(false)
  local total1, count1, next1 = run(true)
  T.truthy(count0 > 0 and total0 > 0, "weeds grew without it")
  T.truthy(count1 <= count0 and total1 < total0 * 0.5, "mulch holds most of them back")
  T.eq(next0, next1, "the stream advances the same with or without mulch")
  T.truthy(reg:get("catalog", "straw_mulch").modifiers.weedGuard > 0, "the catalog item carries the guard")
end)

-- Saving ----------------------------------------------------------------------------------------------

T.test("weeds: they survive a save", function()
  local world = newWorld()
  local i = field(world, 1)[1]
  world.state.soil.weeds[i] = 0.4
  local data = Save.newSlotData("Weeds")
  data.run = world.state
  local disk = serialize.decode(serialize.encode(Save.forDisk(data)))
  Gridpack.unpack(disk.run.grid)
  local loaded = World.new({ registry = reg, tuning = tun }, disk.run)
  T.eq(Soil.weeds(loaded, i), 0.4)
end)
