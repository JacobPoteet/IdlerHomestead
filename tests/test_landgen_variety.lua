local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Pathfind = require("src.sim.pathfind")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local SEEDS = 24
local POND_MAX = 150 -- tiles; a pond with its marsh shallows is smaller, the creek (80 rows of 2+) larger

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed))
end

local function isWater(grid, i)
  return grid.terrain[i] == "water" or grid.terrain[i] == "ford"
end

-- Connected groups of water and ford tiles (8-way), each as a list of tile indices.
local function waterBodies(grid)
  local seen, bodies = {}, {}
  for start = 1, #grid.terrain do
    if isWater(grid, start) and not seen[start] then
      local body, stack = {}, { start }
      seen[start] = true
      while #stack > 0 do
        local i = table.remove(stack)
        body[#body + 1] = i
        local x, y = Grid.coords(grid, i)
        for dy = -1, 1 do
          for dx = -1, 1 do
            if Grid.inBounds(grid, x + dx, y + dy) then
              local n = Grid.index(grid, x + dx, y + dy)
              if isWater(grid, n) and not seen[n] then
                seen[n] = true
                stack[#stack + 1] = n
              end
            end
          end
        end
      end
      bodies[#bodies + 1] = body
    end
  end
  return bodies
end

local function count(world, id)
  local n = 0
  for _, obj in pairs(world.state.grid.objects) do
    if obj.id == id then
      n = n + 1
    end
  end
  return n
end

T.test("landgen variety: every plot has ponds apart from the creek", function()
  for seed = 1, SEEDS do
    local grid = newWorld(seed).state.grid
    local ponds = 0
    for _, body in ipairs(waterBodies(grid)) do
      if #body < POND_MAX then -- the creek (and its tributary) is far bigger than any pond
        ponds = ponds + 1
      end
    end
    T.truthy(ponds >= 1, "seed " .. seed .. " has a pond")
  end
end)

T.test("landgen variety: ponds keep their distance from the truck", function()
  for seed = 1, SEEDS do
    local world = newWorld(seed)
    local grid = world.state.grid
    for _, body in ipairs(waterBodies(grid)) do
      if #body < POND_MAX then
        for _, i in ipairs(body) do
          T.truthy(
            Grid.distance(grid, i, world.state.land.truck) >= tun.landgen.pondTruckMin - tun.landgen.pondMaxRadius,
            "seed " .. seed .. " pond too close to the truck"
          )
        end
      end
    end
  end
end)

T.test("landgen variety: a tributary joins the creek on most plots", function()
  local joined = 0
  for seed = 1, SEEDS do
    local grid = newWorld(seed).state.grid
    local trunk
    for _, body in ipairs(waterBodies(grid)) do
      if #body > (trunk and #trunk or 0) then
        trunk = body
      end
    end
    local perRow, top, bottom = {}, math.huge, 0
    for _, i in ipairs(trunk) do
      local _, y = Grid.coords(grid, i)
      perRow[y] = (perRow[y] or 0) + 1
      top, bottom = math.min(top, y), math.max(bottom, y)
    end
    T.truthy(top == 1 and bottom == grid.h, "seed " .. seed .. " the creek spans the map")
    for _, n in pairs(perRow) do
      if n > tun.landgen.creekMaxWidth + 4 then -- a horizontal run: the tributary
        joined = joined + 1
        break
      end
    end
  end
  T.truthy(joined >= SEEDS / 2, "most plots have a tributary (" .. joined .. " of " .. SEEDS .. ")")
end)

T.test("landgen variety: every tree species, clearings of open ground, and boulders appear", function()
  local totals = { tree = 0, pine = 0, birch = 0, rock = 0 }
  for seed = 1, SEEDS do
    local world = newWorld(seed)
    for id in pairs(totals) do
      totals[id] = totals[id] + count(world, id)
    end
  end
  for id, n in pairs(totals) do
    T.truthy(n > 0, id .. " appears across the seeds")
  end
  -- No single species takes over the woods.
  local trees = totals.tree + totals.pine + totals.birch
  for _, id in ipairs({ "tree", "pine", "birch" }) do
    T.truthy(totals[id] / trees > 0.1, id .. " is a real share of the trees")
  end
end)

T.test("landgen variety: maps differ in how wooded they are", function()
  local lo, hi = math.huge, 0
  for seed = 1, SEEDS do
    local world = newWorld(seed)
    local n = count(world, "tree") + count(world, "pine") + count(world, "birch")
    lo, hi = math.min(lo, n), math.max(hi, n)
  end
  T.truthy(hi > lo * 1.3, "tree counts range from " .. lo .. " to " .. hi)
end)

T.test("landgen variety: water and the road stay reachable and the plot stays walkable", function()
  for seed = 1, SEEDS do
    local world = newWorld(seed)
    local grid = world.state.grid
    local targets = {}
    for i = 1, #grid.terrain do
      if grid.terrain[i] == "water" then
        targets[i] = false
      end
    end
    T.truthy(Pathfind.nearest(world, world.state.land.spawn, targets), "seed " .. seed .. " water")
    -- The deliveries' drop-off is on the road and walkable from the spawn.
    T.truthy(
      Pathfind.find(world, world.state.land.spawn, function(i)
        return i == world.state.land.dropoff
      end, world.state.land.dropoff),
      "seed " .. seed .. " road"
    )
  end
end)

T.test("landgen variety: the same seed makes the same plot", function()
  local a, b = newWorld(77), newWorld(77)
  for i = 1, #a.state.grid.terrain do
    T.eq(a.state.grid.terrain[i], b.state.grid.terrain[i])
    T.eq(a.state.grid.soil[i], b.state.grid.soil[i])
  end
  for anchor, obj in pairs(a.state.grid.objects) do
    T.eq(b.state.grid.objects[anchor].id, obj.id)
  end
end)

T.test("trees: every species is a felled tree for notes, sounds and shade", function()
  for _, id in ipairs({ "tree", "pine", "birch" }) do
    local def = reg:get("objects", id)
    T.eq(def.kind or def.id, "tree", id)
    T.truthy(def.fell and def.chop and def.blocks, id .. " is chopped like a tree")
  end
end)
