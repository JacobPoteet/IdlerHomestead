-- Runtime caches on the grid (#123, #78): the object index behind Grid.anchorsWith and the bank
-- tile lists behind Grid.bankTiles must always match a fresh scan of the state.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")
local Power = require("src.sim.systems.power")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

-- What anchorsWith must return: a full scan, sorted.
local function scan(world, field)
  local list = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    if reg:get("objects", obj.id)[field] then
      list[#list + 1] = anchor
    end
  end
  table.sort(list)
  return list
end

local function freeTile(world, from)
  local grid = world.state.grid
  for i = from or 1, #grid.terrain do
    if Grid.terrain(world, i).walkable and not world.occupancy[i] then
      local x, y = Grid.coords(grid, i)
      if x < grid.w - 2 and y < grid.h - 2 then
        return x, y, i
      end
    end
  end
end

T.test("grid cache: anchorsWith follows placing and removing objects", function()
  local world = newWorld(3)
  for _, field in ipairs({ "source", "sink", "battery", "pump", "drip", "shelter", "stand" }) do
    T.same(Grid.anchorsWith(world, field), scan(world, field), field .. " at start")
  end
  local before = Grid.anchorsWith(world, "source")
  local x, y = freeTile(world, 200)
  local anchor = Grid.placeObject(world, "solar_array", x, y)
  T.truthy(anchor, "placed an array")
  T.same(Grid.anchorsWith(world, "source"), scan(world, "source"), "the new source is listed")
  T.eq(#Grid.anchorsWith(world, "source"), #before + 1)
  T.eq(#before, #scan(world, "source") - 1, "an earlier list is a snapshot, never changed in place")
  Grid.removeObject(world, anchor)
  T.same(Grid.anchorsWith(world, "source"), scan(world, "source"), "the removed source is gone")
  -- A replaced grid (a load, a new run) is noticed even without a call through Grid.
  world.state.grid =
    { w = world.state.grid.w, h = world.state.grid.h, terrain = world.state.grid.terrain, objects = {} }
  T.eq(#Grid.anchorsWith(world, "battery"), 0, "a new objects table is rescanned")
end)

T.test("grid cache: power sees a battery placed mid-run", function()
  local world = newWorld(4)
  local banks = #Grid.anchorsWith(world, "battery")
  local x, y = freeTile(world, 300)
  local anchor = Grid.placeObject(world, "battery_bank", x, y)
  world:tick(1 / tun.time.tickRate)
  T.eq(#Grid.anchorsWith(world, "battery"), banks + 1)
  T.eq(Power.capacity(world, anchor) > 0, true)
end)

T.test("grid cache: bankTiles is rebuilt after a terrain change (#78)", function()
  local world = newWorld(5)
  local grid = world.state.grid
  local list = Grid.bankTiles(world, "water")
  T.truthy(#list > 0, "the creek has a bank")
  local tile = list[1]
  Grid.setTerrain(world, tile, "grass")
  local after = Grid.bankTiles(world, "water")
  for _, i in ipairs(after) do
    T.truthy(i ~= tile, "the filled tile is no longer water")
    T.eq(grid.terrain[i], "water")
  end
  T.errors(function()
    Grid.setTerrain(world, tile, "no_such_terrain")
  end, "no_such_terrain")
end)

T.test("pathfind: the nearest search and A* still agree on a simple map", function()
  local world = newWorld(6)
  local grid = world.state.grid
  local _, _, start = freeTile(world, 400)
  local _, _, goal = freeTile(world, 900)
  local path = Pathfind.toWorkSpot(world, start, goal)
  T.truthy(path, "reachable")
  local nearPath, found = Pathfind.nearest(world, start, { [goal] = false })
  T.eq(found, goal)
  T.truthy(Grid.distance(grid, nearPath[#nearPath] or start, goal) <= 1, "ends beside the goal")
end)
