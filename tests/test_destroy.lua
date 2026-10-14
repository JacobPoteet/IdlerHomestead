-- Destroying placed objects and crops (D110, #255) and planning over growing crops (D110, #257).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Placement = require("src.sim.systems.placement")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.control = "active"
  return world
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

-- A row of n tillable, free tiles near the spawn.
local function row(world, n)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  for r = 3, 30 do
    for dy = -r, r do
      local x, y = sx + r, sy + dy
      local ok = Grid.inBounds(grid, x + n, y)
      local tiles = {}
      for k = 0, n - 1 do
        if ok then
          local i = Grid.index(grid, x + k, y)
          ok = Grid.terrain(world, i).buildable == true
            and Grid.terrain(world, i).tillable
            and not world.occupancy[i]
            and not Crops.tileInUse(world, i)
          tiles[#tiles + 1] = i
        end
      end
      if ok then
        return tiles
      end
    end
  end
  error("no open row")
end

local function build(world, id, i)
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, i), "place " .. id)
end

T.test("destroy: an object is removed with no refund", function()
  local world = newWorld(1)
  local i = row(world, 3)[1]
  build(world, "smoker", i)
  local seen = collect(world, "object.destroyed")
  T.truthy(Placement.destroy(world, i))
  T.falsy(Grid.object(world, i))
  T.eq(Inventory.objectCount(world, "smoker"), 0, "nothing comes back")
  T.eq(#seen, 1)
end)

T.test("destroy: the truck stays", function()
  local world = newWorld(1)
  local truck
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "truck" then
      truck = anchor
    end
  end
  local ok, check = Placement.destroy(world, truck)
  T.falsy(ok)
  T.eq(check.reason, "fixed")
  T.truthy(Grid.object(world, truck))
end)

T.test("destroy: a store with goods over the new capacity loses them, and the check says so", function()
  local world = newWorld(1)
  local i = row(world, 3)[1]
  build(world, "woodshed", i)
  local cap = Ledger.capacity(world, "wood")
  Ledger.add(world, "wood", cap)
  local check = Placement.destroyCheck(world, i)
  T.truthy(check.ok and check.lose.goods, "warns about the wood")
  T.eq(check.lose.goods[1].resource, "wood")
  T.truthy(check.lose.goods[1].count > 0)
  local seen = collect(world, "object.destroyed")
  T.truthy(Placement.destroy(world, i))
  T.truthy(Ledger.get(world, "wood") <= Ledger.capacity(world, "wood"), "stock fits the smaller store")
  T.eq(seen[1].lost.wood, check.lose.goods[1].count)
end)

T.test("destroy: a store with room to spare loses nothing", function()
  local world = newWorld(1)
  local i = row(world, 3)[1]
  build(world, "woodshed", i)
  local before = Ledger.get(world, "wood")
  T.falsy(Placement.destroyCheck(world, i).lose.goods)
  T.truthy(Placement.destroy(world, i))
  T.eq(Ledger.get(world, "wood"), before)
end)

T.test("destroy: a station's batch goes with it and tilled soil returns", function()
  local world = newWorld(1)
  local i = row(world, 3)[1]
  world.state.fields.tilled[i] = true
  build(world, "smoker", i)
  world.state.processing[i] = { recipe = "smoke_fish", count = 3, remaining = 10 }
  T.eq(Placement.destroyCheck(world, i).lose.batch.count, 3)
  T.truthy(Placement.destroy(world, i))
  T.falsy(world.state.processing[i])
  T.truthy(world.state.fields.tilled[i])
end)

T.test("destroy crop: gone with no refund, soil stays tilled, plan dropped, cause destroy", function()
  local world = newWorld(1)
  local i = row(world, 1)[1]
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = "radish"
  world.state.crops[i] = { id = "radish", growth = 1, moisture = 0.5 }
  local seen = collect(world, "crop.removed")
  local before = Ledger.get(world, "seed_radish")
  T.truthy(Crops.remove(world, i))
  T.falsy(world.state.crops[i])
  T.falsy(world.state.fields.plan[i])
  T.truthy(world.state.fields.tilled[i])
  T.eq(Ledger.get(world, "seed_radish"), before)
  T.eq(seen[1].cause, "destroy")
  T.truthy(seen[1].mature)
  T.falsy(Crops.remove(world, i), "nothing left to destroy")
end)

T.test("plan over crops: any crop on the tiles is replaced, the same kind too", function()
  local world = newWorld(1)
  local tiles = row(world, 3)
  for _, i in ipairs(tiles) do
    world.state.fields.tilled[i] = true
  end
  world.state.crops[tiles[1]] = { id = "potato", growth = 0.4, moisture = 0.5 }
  world.state.crops[tiles[2]] = { id = "radish", growth = 1, moisture = 0.5 }
  local preview = Crops.replacePreview(world, tiles, "radish")
  T.eq(#preview.tiles, 2, "the same crop is marked too")
  T.eq(preview.ripe, 1)
  local seen = collect(world, "crop.removed")
  local result = Crops.planReplacing(world, tiles, "radish")
  T.eq(result.replaced, 2)
  T.eq(result.planned, 3)
  T.falsy(world.state.crops[tiles[1]])
  T.falsy(world.state.crops[tiles[2]])
  for _, i in ipairs(tiles) do
    T.eq(world.state.fields.plan[i], "radish")
    T.truthy(world.state.fields.tilled[i], "soil stays tilled")
  end
  T.eq(#seen, 2)
  T.eq(seen[1].cause, "replace")
end)

T.test("plan over crops: clearing the plan never pulls a crop, held tiles keep theirs", function()
  local world = newWorld(1)
  local tiles = row(world, 2)
  world.state.crops[tiles[1]] = { id = "potato", growth = 0.4, moisture = 0.5 }
  world.state.crops[tiles[2]] = { id = "potato", growth = 0.4, moisture = 0.5 }
  Crops.planReplacing(world, tiles, nil)
  T.truthy(world.state.crops[tiles[1]], "clear plan leaves crops")
  Crops.hold(world, { tiles[2] }, true)
  T.eq(#Crops.replacePreview(world, tiles, "radish").tiles, 1)
  Crops.planReplacing(world, tiles, "radish")
  T.truthy(world.state.crops[tiles[2]], "a held tile is left alone")
  T.falsy(world.state.crops[tiles[1]])
end)

T.test("plan over crops: the routine's starter plan never replaces a crop", function()
  local world = newWorld(1)
  local tiles = row(world, 1)
  world.state.crops[tiles[1]] = { id = "potato", growth = 0.4, moisture = 0.5 }
  local before = Crops.hasAnyPlan(world)
  T.truthy(before)
  Crops.planStarter(world) -- plans nothing once a layout exists
  T.eq(world.state.crops[tiles[1]].id, "potato")
end)
