-- Tools do their own work (GDD §9.4, D138, #294): an order can carry a set of task categories, so a tap
-- with the Pail only waters and a tap with the Axe only clears, while the Hand still does the obvious thing.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")
local Actors = require("src.sim.systems.actors")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed))
end

-- A reachable clutter object near the spawn (brush, rock, log or junk).
local function clutter(world)
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id ~= "truck" and obj.id ~= "tree" and Pathfind.toWorkSpot(world, world.state.land.spawn, anchor) then
      return anchor
    end
  end
end

T.test("tools: the Axe clears what the Hand would clear", function()
  local world = newWorld(8)
  local hs = Actors.homesteader(world)
  local tile = clutter(world)
  T.eq(Tasks.taskForTile(world, hs, tile, { categories = { clear = true } }).id, "clear")
end)

T.test("tools: the Pail does not clear, and an empty field does nothing for it", function()
  local world = newWorld(8)
  local hs = Actors.homesteader(world)
  local tile = clutter(world)
  T.eq(Tasks.taskForTile(world, hs, tile, { categories = { water = true } }), nil, "no clearing with the pail")
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local open
  for r = 1, 6 do
    for x = sx - r, sx + r do
      local i = Grid.index(grid, x, sy + r)
      if not open and Grid.inBounds(grid, x, sy + r) and not grid.objects[i] and Grid.terrain(world, i).tillable then
        open = i
      end
    end
  end
  T.truthy(open, "an open tile near the spawn")
  T.eq(Tasks.taskForTile(world, hs, open, { categories = { water = true } }), nil, "the pail does not walk")
  T.truthy(Tasks.taskForTile(world, hs, open, {}), "the hand walks there")
end)

T.test("tools: an order without categories is the old smart tap", function()
  local world = newWorld(8)
  local hs = Actors.homesteader(world)
  local tile = clutter(world)
  T.eq(Tasks.taskForTile(world, hs, tile, {}).id, "clear")
  T.eq(Tasks.taskForTile(world, hs, tile, nil).id, "clear")
end)
