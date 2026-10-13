-- The idle routine's starter field (GDD D61, issue #66): when the routine takes over and nothing is
-- planned, it plans a small default field so an unattended start does not starve.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.farming
local DPS = tun.time.daysPerSeason
local SPRING, WINTER = 1, 3 * DPS + 1

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function planSize(world)
  local n = 0
  for _ in pairs(world.state.fields.plan) do
    n = n + 1
  end
  return n
end

local function planCounts(world)
  local counts = {}
  for _, id in pairs(world.state.fields.plan) do
    counts[id] = (counts[id] or 0) + 1
  end
  return counts
end

local function plannedTiles(world)
  local list = {}
  for i, id in pairs(world.state.fields.plan) do
    list[#list + 1] = i .. ":" .. id
  end
  table.sort(list)
  return table.concat(list, ",")
end

--- Hand over to the routine and run one tick (the takeover).
local function takeOver(world)
  world.control = "idle"
  world:tick(STEP)
end

T.test("starter plan: nothing is planned until the routine takes over", function()
  local world = newWorld()
  T.eq(planSize(world), 0)
  world:tick(STEP) -- the player is in charge
  T.eq(planSize(world), 0)
end)

T.test("starter plan: takeover plans the tuned field near the truck on tillable free ground", function()
  local world = newWorld()
  local events = {}
  world.events:on("crop.starterPlanned", function(e)
    events[#events + 1] = e
  end)
  takeOver(world)
  local want = 0
  for _, entry in ipairs(cfg.starterField) do
    want = want + math.min(entry.tiles, Ledger.get(world, reg:get("crops", entry.crop).seed))
  end
  T.eq(planSize(world), want)
  T.eq(#events, 1)
  T.eq(events[1].tiles, want)
  local grid, truck = world.state.grid, Land.truck(world)
  for i, cropId in pairs(world.state.fields.plan) do
    T.truthy(Grid.terrain(world, i).tillable, "tillable")
    T.truthy(not world.occupancy[i], "free of objects")
    T.truthy(Grid.distance(grid, i, truck) <= cfg.starterRadius, "within the radius of the truck")
    T.truthy(reg:has("crops", cropId))
  end
  local counts = planCounts(world)
  for _, entry in ipairs(cfg.starterField) do
    T.eq(counts[entry.crop], entry.tiles, entry.crop)
  end
end)

-- Number of 8-connected groups among the tiles.
local function components(grid, tiles)
  local left, n = {}, 0
  for _, i in ipairs(tiles) do
    left[i] = true
  end
  for _, i in ipairs(tiles) do
    if left[i] then
      n = n + 1
      local stack = { i }
      left[i] = nil
      while #stack > 0 do
        local x, y = Grid.coords(grid, table.remove(stack))
        for dy = -1, 1 do
          for dx = -1, 1 do
            local j = Grid.inBounds(grid, x + dx, y + dy) and Grid.index(grid, x + dx, y + dy)
            if j and left[j] then
              left[j] = nil
              stack[#stack + 1] = j
            end
          end
        end
      end
    end
  end
  return n
end

local function sortedPlan(world)
  local tiles = {}
  for i in pairs(world.state.fields.plan) do
    tiles[#tiles + 1] = i
  end
  table.sort(tiles)
  return tiles
end

T.test("starter plan: one compact block the homesteader can reach, on every seed (D88, #137)", function()
  local Pathfind = require("src.sim.pathfind")
  local Actors = require("src.sim.systems.actors")
  for seed = 1, 60 do
    local world = newWorld(seed)
    takeOver(world)
    local tiles = sortedPlan(world)
    local grid = world.state.grid
    T.truthy(#tiles > 0, "seed " .. seed .. " planned a field")
    T.eq(components(grid, tiles), 1, "seed " .. seed .. " is one connected block")
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, i in ipairs(tiles) do
      local x, y = Grid.coords(grid, i)
      x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
    end
    T.truthy((x1 - x0 + 1) * (y1 - y0 + 1) <= 2 * #tiles, "seed " .. seed .. " bounding box stays tight")
    T.truthy(math.min(x1 - x0, y1 - y0) >= 1, "seed " .. seed .. " is not a one-tile strip")
    local start = Grid.index(grid, math.floor(Actors.homesteader(world).x + 0.5), math.floor(Actors.homesteader(world).y + 0.5))
    for _, i in ipairs(tiles) do
      T.truthy(Pathfind.toWorkSpot(world, start, i), "seed " .. seed .. " tile " .. i .. " is reachable")
    end
  end
end)

T.test("starter plan: the same seed always lays out the same block", function()
  for seed = 1, 6 do
    local a, b = newWorld(seed), newWorld(seed)
    takeOver(a)
    takeOver(b)
    T.eq(plannedTiles(a), plannedTiles(b), "seed " .. seed)
  end
end)

T.test("starter plan: planned once, then left alone on later days", function()
  local world = newWorld()
  takeOver(world)
  local before = plannedTiles(world)
  for day = 2, 4 do
    setTime(world, day, 8)
    world:tick(STEP)
  end
  T.eq(plannedTiles(world), before)
end)

T.test("starter plan: deterministic for a seed", function()
  local a, b = newWorld(7), newWorld(7)
  takeOver(a)
  takeOver(b)
  T.eq(plannedTiles(a), plannedTiles(b))
  T.truthy(planSize(a) > 0)
end)

T.test("starter plan: never overrides a player's plan", function()
  local world = newWorld()
  local grid = world.state.grid
  local mine
  for i = 1, #grid.terrain do
    if Grid.terrain(world, i).tillable and not world.occupancy[i] then
      mine = i
      break
    end
  end
  T.truthy(Crops.setPlan(world, mine, "potato"))
  takeOver(world)
  T.eq(planSize(world), 1)
  T.eq(world.state.fields.plan[mine], "potato")
  setTime(world, 3, 8)
  world:tick(STEP)
  T.eq(planSize(world), 1, "not on a later day either")
end)

T.test("starter plan: a tilled or growing field counts as decided", function()
  local world = newWorld()
  world.state.crops[1] = { id = "radish", growth = 0.2, moisture = 0.5 }
  takeOver(world)
  T.eq(planSize(world), 0)
end)

T.test("starter plan: frozen ground plans nothing, and the first thaw day does", function()
  local world = newWorld()
  setTime(world, WINTER + 1, 8)
  takeOver(world)
  T.eq(planSize(world), 0)
  setTime(world, SPRING + 4 * DPS, 8) -- next year's spring
  world:tick(STEP)
  T.truthy(planSize(world) > 0)
end)

T.test("starter plan: respects seed stock, one tile per seed", function()
  local world = newWorld()
  Ledger.remove(world, "seed_radish", Ledger.get(world, "seed_radish") - 2)
  Ledger.remove(world, "seed_potato", Ledger.get(world, "seed_potato"))
  takeOver(world)
  T.eq(planSize(world), 2)
  T.eq(planCounts(world).radish, 2)
  local none = newWorld()
  Ledger.remove(none, "seed_radish", Ledger.get(none, "seed_radish"))
  Ledger.remove(none, "seed_potato", Ledger.get(none, "seed_potato"))
  takeOver(none)
  T.eq(planSize(none), 0)
end)

T.test("starter plan: skips a crop that could not ripen before the freeze", function()
  local world = newWorld()
  local autumnDay = 2 * DPS + DPS - 2 -- three days left of autumn: the radish (2 + margin) fits, the potato (5) not
  setTime(world, autumnDay, 8)
  takeOver(world)
  local counts = planCounts(world)
  T.eq(counts.radish, 4)
  T.eq(counts.potato, nil)
  local late = newWorld()
  setTime(late, 3 * DPS, 8) -- the last day of autumn
  takeOver(late)
  T.eq(planSize(late), 0)
end)

T.test("starter plan: the routine then tills, plants and harvests the field unattended", function()
  local world = newWorld(3)
  world.control = "idle"
  local planted = 0
  world.events:on("crop.planted", function()
    planted = planted + 1
  end)
  local harvested = 0
  world.events:on("crop.harvested", function()
    harvested = harvested + 1
  end)
  for _ = 1, math.floor(tun.time.dayLength * 3 / STEP) do
    world:tick(STEP)
  end
  T.truthy(planted >= 4, "planted " .. planted)
  T.truthy(harvested > 0, "harvested " .. harvested)
end)

T.test("starter plan: survives a save round-trip and older saves without the routine day load", function()
  local world = newWorld()
  takeOver(world)
  local state = serialize.decode(serialize.encode(world.state))
  local restored = World.new({ registry = reg, tuning = tun }, state)
  T.eq(plannedTiles(restored), plannedTiles(world))
  restored.control = "idle"
  restored:tick(STEP)
  T.eq(plannedTiles(restored), plannedTiles(world), "no second field")
  state.routine = {}
  local old = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(state)))
  T.eq(old.state.routine.planDay, 0)
  old.control = "idle"
  old:tick(STEP)
  T.eq(plannedTiles(old), plannedTiles(world))
end)
