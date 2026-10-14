-- Picking placed objects up and moving them (GDD D98, issue #15), and the cancel edge case of #227.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Machines = require("src.sim.systems.machines")
local Placement = require("src.sim.systems.placement")
local Power = require("src.sim.systems.power")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.control = "active"
  return world
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP + 0.5) do
    world:tick(STEP)
  end
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

-- Top-left tile of an open w x h block of grass near the spawn (see test_placement.lua).
local function openBlock(world, w, h, dx, dy)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  for r = 0, 25 do
    for oy = -r, r do
      for ox = -r, r do
        if math.max(math.abs(ox), math.abs(oy)) == r then
          local x, y = sx + (dx or 4) + ox, sy + (dy or 3) + oy
          local ok = Grid.inBounds(grid, x, y) and Grid.inBounds(grid, x + w, y + h)
          for yy = y - 1, y + h do
            for xx = x - 1, x + w do
              if ok then
                if not Grid.inBounds(grid, xx, yy) then
                  ok = false
                else
                  local i = Grid.index(grid, xx, yy)
                  ok = Grid.terrain(world, i).buildable == true
                    and not world.occupancy[i]
                    and not Crops.tileInUse(world, i)
                    and i ~= Land.spawn(world)
                end
              end
            end
          end
          if ok then
            return Grid.index(grid, x, y), x, y
          end
        end
      end
    end
  end
  error("no open block")
end

-- Put an object in the inventory and place it at tile i; returns its anchor.
local function build(world, id, i)
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, i), "place " .. id)
  return i
end

-- Pick up -------------------------------------------------------------------------------------------

T.test("pick up: the object returns to the inventory and the ground is free", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  local seen = collect(world, "object.pickedup")
  T.truthy(Placement.pickUp(world, i))
  T.falsy(Grid.object(world, i), "nothing stands there")
  T.eq(Inventory.objectCount(world, "smoker"), 1)
  T.eq(Placement.available(world, "smoker"), 1, "free to place again")
  T.eq(#seen, 1)
  T.truthy(Inventory.canPlace(world, "smoker", i), "and the spot is open ground")
end)

T.test("pick up: tilled soil is tilled again, grass stays grass", function()
  local world = newWorld(1)
  local i = openBlock(world, 2, 1)
  world.state.fields.tilled[i] = true
  build(world, "woodshed", i)
  T.falsy(world.state.fields.tilled[i], "covered while it stands")
  T.truthy(Placement.pickUp(world, i))
  T.truthy(world.state.fields.tilled[i], "the tilled tile comes back")
  T.falsy(world.state.fields.tilled[i + 1], "the grass tile does not become soil")
  T.falsy(world.state.fields.plan[i], "no plan is invented")
end)

T.test("pick up: the truck and other fixed objects stay", function()
  local world = newWorld(1)
  local truck
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "truck" then
      truck = anchor
    end
  end
  local ok, check = Placement.pickUp(world, truck)
  T.falsy(ok)
  T.eq(check.reason, "fixed")
  T.truthy(Grid.object(world, truck), "still there")
end)

T.test("pick up: a running batch refuses, a waiting one asks and is discarded", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  world.state.processing[i] = { recipe = "smoke_fish", count = 3, remaining = 10 }
  local ok, check = Placement.pickUp(world, i)
  T.falsy(ok)
  T.eq(check.reason, "batch")
  T.truthy(Grid.object(world, i))
  world.state.processing[i] = { recipe = "smoke_fish", count = 3, remaining = 0, blocked = true }
  local info = Placement.pickUpCheck(world, i)
  T.truthy(info.ok and info.warn and info.warn.kind == "output" and info.warn.count == 3, "the card must ask")
  local discarded = collect(world, "processing.discarded")
  T.truthy(Placement.pickUp(world, i))
  T.eq(#discarded, 1)
  T.falsy(world.state.processing[i], "no batch is left behind")
end)

T.test("pick up: a coop with hens that would have nowhere to live refuses; with room elsewhere it goes", function()
  local world = newWorld(1)
  local a = openBlock(world, 2, 1)
  build(world, "chicken_coop", a)
  Ledger.add(world, "hen", 4)
  local ok, check = Placement.pickUp(world, a)
  T.falsy(ok)
  T.eq(check.reason, "storage")
  T.eq(check.resource, "hen")
  T.truthy(check.animal)
  local b = openBlock(world, 2, 1, 12, 8)
  build(world, "chicken_coop", b)
  T.truthy(Placement.pickUp(world, a), "the second coop takes the flock")
  T.eq(Ledger.get(world, "hen"), 4)
  T.truthy(Placement.pickUp(world, b) == nil, "but not the last one")
end)

T.test("pick up: storage holding more than would be left refuses until used", function()
  local world = newWorld(1)
  local i = openBlock(world, 2, 1)
  build(world, "woodshed", i)
  local base = reg:get("resources", "wood").capacity
  Ledger.add(world, "wood", base + 5)
  local ok, check = Placement.pickUp(world, i)
  T.falsy(ok)
  T.eq(check.reason, "storage")
  T.eq(check.resource, "wood")
  Ledger.remove(world, "wood", 10)
  T.truthy(Placement.pickUp(world, i))
  T.eq(Ledger.capacity(world, "wood"), base, "capacity is back to the base")
end)

T.test("pick up: the bed the homesteader sleeps in stays put", function()
  local world = newWorld(1)
  local i = openBlock(world, 2, 2)
  build(world, "camp", i)
  Actors.homesteader(world).asleep = true
  local ok, check = Placement.pickUp(world, i)
  T.falsy(ok)
  T.eq(check.reason, "asleep")
  T.eq(Placement.requestMove(world, i, i + 5), nil, "and it cannot be moved either")
  Actors.homesteader(world).asleep = false
  T.truthy(Placement.pickUp(world, i), "fine in the morning")
end)

T.test("pick up: a battery asks first, and the network is recomputed without it", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "battery_bank", i)
  local before = Power.bank(world).capacity
  Power.add(world, i, 5)
  local info = Placement.pickUpCheck(world, i)
  T.truthy(info.ok and info.warn and info.warn.kind == "charge" and info.warn.kwh > 4)
  T.truthy(Placement.pickUp(world, i))
  T.eq(Power.bank(world).capacity, before - 20, "the bank shrinks by the battery")
  T.eq(Power.charge(world, i), 0, "its charge is gone with it")
  run(world, 5) -- the network keeps running
end)

T.test("pick up: a job on the object is dropped", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  local hs = Actors.homesteader(world)
  hs.job = { task = "load_station", target = i, progress = 0, path = {} }
  T.truthy(Placement.pickUp(world, i))
  T.eq(hs.job, nil)
end)

-- Move ----------------------------------------------------------------------------------------------

T.test("move: onto open ground happens at once and keeps the battery's charge and switch", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "battery_bank", i)
  Power.add(world, i, 7)
  Power.setEnabled(world, i, false)
  local to = openBlock(world, 1, 1, 12, 8)
  local moved = collect(world, "object.moved")
  T.eq(Placement.requestMove(world, i, to), "placed")
  T.falsy(Grid.object(world, i), "gone from the old spot")
  T.eq(Grid.object(world, to).id, "battery_bank")
  T.near(Power.charge(world, to), 7, 1e-9)
  T.eq(Power.charge(world, i), 0)
  T.falsy(Power.isEnabled(world, to), "still switched off")
  T.eq(Inventory.objectCount(world, "battery_bank"), 0, "the inventory is not touched")
  T.eq(#moved, 1)
end)

T.test("move: a running batch goes along", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  world.state.processing[i] = { recipe = "smoke_fish", count = 2, remaining = 4 }
  local to = openBlock(world, 1, 1, 12, 8)
  T.eq(Placement.requestMove(world, i, to), "placed")
  T.falsy(world.state.processing[i])
  T.eq(world.state.processing[to].count, 2)
end)

T.test("move: a tilled tile left behind is tilled again and the new one is covered", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  world.state.fields.tilled[i] = true
  build(world, "smoker", i)
  local to = openBlock(world, 1, 1, 12, 8)
  world.state.fields.tilled[to] = true
  T.eq(Placement.requestMove(world, i, to), "placed")
  T.truthy(world.state.fields.tilled[i], "soil returned")
  T.falsy(world.state.fields.tilled[to], "soil covered")
  T.truthy(world.state.grid.objects[to].tilled[to], "and remembered for the next pick up")
end)

T.test("move: a short hop onto its own footprint works, onto itself is refused", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 3, 1)
  build(world, "chicken_coop", i)
  T.eq(Placement.preview(world, "chicken_coop", i, i).reason, "here")
  local to = Grid.index(world.state.grid, x + 1, y)
  T.eq(Placement.requestMove(world, i, to), "placed")
  T.eq(Grid.object(world, to).id, "chicken_coop")
  T.falsy(world.occupancy[i], "the vacated tile is free")
  T.truthy(world.occupancy[to + 1])
end)

T.test(
  "move: the preview names what is cleared and the object stays until the way is clear; cancel keeps it",
  function()
    local world = newWorld(1)
    local i = openBlock(world, 1, 1)
    build(world, "smoker", i)
    local to, tx, ty = openBlock(world, 1, 1, 12, 8)
    Grid.placeObject(world, "tree", tx, ty)
    local preview = Placement.preview(world, "smoker", to, i)
    T.truthy(preview.ok and preview.queue and preview.clear[1].id == "tree")
    T.eq(Placement.requestMove(world, i, to), "queued")
    T.eq(
      Placement.available(world, "smoker"),
      0 + Inventory.objectCount(world, "smoker"),
      "a move takes no inventory item"
    )
    T.truthy(Grid.object(world, i), "still at the old spot while it waits")
    T.truthy(world.state.fields.held[to], "the target is held")
    T.truthy(Placement.cancel(world, to))
    T.eq(Grid.object(world, i).id, "smoker", "cancelled: it stays")
    T.falsy(world.state.fields.held[to])
    T.eq(Grid.object(world, to).id, "tree", "nothing was cleared")
  end
)

T.test("move: completes after the clearing, in order, and the soil is kept", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  local to, tx, ty = openBlock(world, 1, 1, 12, 8)
  Grid.placeObject(world, "rock", tx, ty)
  local done = collect(world, "placement.done")
  Placement.requestMove(world, i, to)
  run(world, 90)
  T.eq(Grid.object(world, to).id, "smoker")
  T.falsy(Grid.object(world, i))
  T.eq(#done, 1)
  T.eq(#Placement.orders(world), 0)
end)

T.test("move: crops under the new spot go last, and picking the object up cancels its move", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  local to = openBlock(world, 1, 1, 12, 8)
  world.state.fields.tilled[to] = true
  world.state.fields.plan[to] = "radish"
  world.state.crops[to] = { id = "radish", growth = 0.3, moisture = 0.5 }
  Placement.requestMove(world, i, to)
  T.truthy(world.state.crops[to] or Grid.object(world, to), "nothing removed at the order")
  T.truthy(Placement.pickUp(world, i))
  T.eq(#Placement.orders(world), 0, "the move went with it")
  T.truthy(world.state.crops[to], "the crop is untouched")
  T.falsy(world.state.fields.held[to])
end)

T.test("move: a machine works from its new spot", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "auto_harvester", i)
  run(world, 1)
  T.truthy(Machines.at(world, i))
  local to = openBlock(world, 1, 1, 12, 8)
  T.eq(Placement.requestMove(world, i, to), "placed")
  run(world, 1)
  T.truthy(Machines.at(world, to))
  T.falsy(Machines.at(world, i))
end)

T.test("move: orders keep working through a save and load", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  build(world, "smoker", i)
  local to, tx, ty = openBlock(world, 1, 1, 12, 8)
  Grid.placeObject(world, "tree", tx, ty)
  Placement.requestMove(world, i, to)
  local loaded = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  loaded.control = "active"
  T.eq(Placement.orders(loaded)[1].from, i)
  run(loaded, 60)
  T.eq(Grid.object(loaded, to).id, "smoker")
end)

T.test("move and pick up are deterministic", function()
  local function play()
    local world = newWorld(5)
    local a = openBlock(world, 1, 1)
    build(world, "battery_bank", a)
    Power.add(world, a, 3)
    local b, bx, by = openBlock(world, 1, 1, 12, 8)
    Grid.placeObject(world, "tree", bx, by)
    Placement.requestMove(world, a, b)
    run(world, 60)
    Placement.pickUp(world, b)
    return serialize.encode(world.state)
  end
  T.eq(play(), play())
end)

-- #227 ----------------------------------------------------------------------------------------------

T.test(
  "placement: crops stay while the homesteader still has to step aside, so a cancel loses nothing (#227)",
  function()
    local world = newWorld(1)
    local i, x, y = openBlock(world, 1, 1)
    world.state.fields.tilled[i] = true
    world.state.fields.plan[i] = "radish"
    world.state.crops[i] = { id = "radish", growth = 0.3, moisture = 0.5 }
    local hs = Actors.homesteader(world)
    hs.x, hs.y = x, y
    Inventory.addObject(world, "smoker")
    T.eq(Placement.request(world, "smoker", i), "queued")
    world:tick(STEP)
    T.truthy(world.state.crops[i], "the crop is still there while the homesteader stands on it")
    T.truthy(Placement.cancel(world, i))
    T.truthy(world.state.crops[i], "cancel restores nothing because nothing was lost")
    T.eq(world.state.fields.plan[i], "radish")
  end
)

T.test("placement: with the homesteader out of the way the crop goes and the building goes up together", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  world.state.fields.tilled[i] = true
  world.state.crops[i] = { id = "radish", growth = 0.3, moisture = 0.5 }
  local hs = Actors.homesteader(world)
  hs.x, hs.y = x, y
  Inventory.addObject(world, "smoker")
  Placement.request(world, "smoker", i)
  run(world, 30)
  T.eq(Grid.object(world, i) and Grid.object(world, i).id, "smoker")
  T.falsy(world.state.crops[i])
end)
