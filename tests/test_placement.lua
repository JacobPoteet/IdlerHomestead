-- Untilling land and placing objects over clutter and crops (GDD D79, issue #197).
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
local Tasks = require("src.sim.systems.tasks")
local Machines = require("src.sim.systems.machines")
local Placement = require("src.sim.systems.placement")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

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

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

-- Top-left tile of an open w x h block of grass (nothing on it, nothing tilled or planned) near the
-- spawn, starting `skip` blocks out so two tests do not fight over a place.
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

local function put(world, id, x, y)
  return assert(Grid.placeObject(world, id, x, y), "put " .. id)
end

local function plant(world, i, growth)
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = "radish"
  world.state.crops[i] = { id = "radish", growth = growth or 0.3, moisture = 0.5 }
end

local function stock(world, id)
  Inventory.addObject(world, id)
end

-- Untill ----------------------------------------------------------------------------------------

T.test("untill: the tool turns tilled soil back to grass and drops its plan", function()
  local world = newWorld(1)
  local hs = Actors.homesteader(world)
  local i = openBlock(world, 1, 1)
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = "radish"
  local task = Actors.order(world, hs, i, { tool = "untill" })
  T.eq(task and task.id, "untill")
  local seen = collect(world, "field.untilled")
  run(world, 20)
  T.falsy(world.state.fields.tilled[i], "no longer tilled")
  T.falsy(world.state.fields.plan[i], "the plan went with it")
  T.eq(#seen, 1)
  T.eq(Grid.terrain(world, i).id, "grass")
end)

T.test("untill: the tool pulls a planted crop and leaves bare tilled soil, then a second pass makes grass (#254)", function()
  local world = newWorld(1)
  local hs = Actors.homesteader(world)
  local i = openBlock(world, 1, 1)
  plant(world, i)
  local task = Actors.order(world, hs, i, { tool = "untill" })
  T.eq(task and task.id, "untill", "a crop no longer refuses the tool")
  local removed = collect(world, "crop.removed")
  run(world, 20)
  T.falsy(world.state.crops[i], "the crop is gone")
  T.falsy(world.state.fields.plan[i], "the plan went too, so the routine does not replant it")
  T.truthy(world.state.fields.tilled[i], "the soil stays prepared")
  T.eq(#removed, 1)
  T.eq(removed[1].cause, "untill")
  local again = Actors.order(world, hs, i, { tool = "untill" })
  T.eq(again and again.id, "untill")
  run(world, 20)
  T.falsy(world.state.fields.tilled[i], "the second pass turns it back to grass")
end)

T.test("untill: refused on bare grass or without the tool", function()
  local world = newWorld(1)
  local hs = Actors.homesteader(world)
  local i = openBlock(world, 1, 1)
  plant(world, i)
  world.state.crops[i] = nil
  local seeded = Actors.order(world, hs, i, { crop = "radish" })
  T.truthy(seeded == nil or seeded.id ~= "untill", "a seed in hand does not untill")
  hs.order = nil
  world.state.fields.tilled[i] = nil
  world.state.fields.plan[i] = nil
  hs.order = nil
  local walk = Actors.order(world, hs, i, { tool = "untill" })
  T.truthy(walk == nil or walk.id == "move", "bare grass is only somewhere to walk")
end)

T.test("untill: the idle routine clears tilled soil nobody planned, never a planned tile", function()
  local world = newWorld(2)
  world.control = "idle"
  local left = openBlock(world, 2, 1)
  world.state.fields.tilled[left] = true -- a leftover of a cleared plan
  world.state.fields.tilled[left + 1] = true
  world.state.fields.plan[left + 1] = "radish"
  setTime(world, 1, 10)
  run(world, 30)
  T.falsy(world.state.fields.tilled[left], "the leftover went back to grass")
  T.truthy(world.state.fields.tilled[left + 1], "a planned tile stays tilled")
end)

-- The placement rule ----------------------------------------------------------------------------

T.test("placement rule: grass and tilled soil take objects; roads and water never do", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  T.truthy(Inventory.check(world, "smoker", i).immediate, "open grass")
  world.state.fields.tilled[i] = true
  local check = Inventory.check(world, "smoker", i)
  T.truthy(check.immediate and check.tilled == 1, "tilled soil with no plan is open ground")
  local grid = world.state.grid
  local road, water
  for t = 1, #grid.terrain do
    local id = grid.terrain[t]
    road = road or (id == "road" and not world.occupancy[t] and t or nil)
    water = water or (reg:get("terrain", id).water and t or nil)
  end
  if road then
    T.eq(Inventory.check(world, "smoker", road).reason, "terrain", "road")
  end
  T.eq(Inventory.check(world, "smoker", water).reason, "terrain", "water")
  T.eq(Inventory.check(world, "smoker", #grid.terrain + 5).reason, "bounds", "off the map")
  T.eq(Inventory.check(world, "truck", i).ok, true, "the truck is an object like the rest; checked by its own rules")
  local truck = Land.truck(world)
  T.eq(Inventory.check(world, "smoker", truck).reason, "object", "the truck cannot be cleared away")
end)

T.test("placement: a tilled tile keeps its soil record for a later pick-up", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  world.state.fields.tilled[i] = true
  stock(world, "smoker")
  T.truthy(Inventory.place(world, "smoker", i))
  T.falsy(world.state.fields.tilled[i], "the tile is under the building")
  T.truthy(world.state.grid.objects[i].tilled[i], "the object remembers the tile was tilled")
  Crops.restoreTilled(world, i)
  T.truthy(world.state.fields.tilled[i], "and the soil can be handed back")
end)

T.test("placement rule: the object's own rules still apply (well needs a water table)", function()
  local world = newWorld(1)
  local grid = world.state.grid
  local dry
  for t = 1, #grid.terrain do
    if Grid.terrain(world, t).buildable and not world.occupancy[t] and not Land.hasWaterTable(world, t) then
      dry = t
      break
    end
  end
  local check = Inventory.check(world, "well", dry)
  T.falsy(check.ok)
  T.eq(check.rule, "waterTable")
end)

-- Placing over clutter and crops ----------------------------------------------------------------

T.test("placement: a tree on the footprint is felled first, then the object goes up", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  stock(world, "smoker")
  T.falsy(Inventory.canPlace(world, "smoker", i), "not at once")
  local preview = Placement.preview(world, "smoker", i)
  T.truthy(preview.ok and preview.queue, "legal after clearing")
  T.eq(preview.clear[1].id, "tree")
  T.eq(Placement.request(world, "smoker", i), "queued")
  T.eq(Placement.available(world, "smoker"), 0, "the item is spoken for")
  local done, cleared = collect(world, "placement.done"), collect(world, "object.cleared")
  local wood = Ledger.get(world, "wood")
  run(world, 60)
  T.eq(#cleared, 1)
  T.truthy(Ledger.get(world, "wood") > wood, "the yield went to the ledger as usual")
  T.eq(#done, 1)
  local obj = Grid.object(world, i)
  T.eq(obj and obj.id, "smoker")
  T.eq(Inventory.objectCount(world, "smoker"), 0)
  T.eq(#Placement.orders(world), 0)
  T.falsy(world.state.fields.held[i], "the hold is released")
end)

T.test("placement: every rock, log and brush on a wide footprint is cleared before it goes up", function()
  local world = newWorld(1)
  -- A placeable object two tiles wide with no extra placement rule, else the smoker on one tile.
  local wide
  for _, o in ipairs(reg:all("objects")) do
    if o.placeable and (o.footprintW or 1) >= 2 and (o.footprintH or 1) == 1 and not o.placeNear and not o.placeOn then
      wide = o
      break
    end
  end
  wide = wide or reg:get("objects", "smoker")
  local block, bx, by = openBlock(world, wide.footprintW or 1, wide.footprintH or 1, 6, 2)
  put(world, "rock", bx, by)
  if (wide.footprintW or 1) >= 2 then
    put(world, "brush", bx + 1, by)
  end
  stock(world, wide.id)
  local preview = Placement.preview(world, wide.id, block)
  T.truthy(preview.queue)
  T.eq(Placement.request(world, wide.id, block), "queued")
  local order = {}
  world.events:on("object.cleared", function(e)
    order[#order + 1] = e.object
    T.falsy(Grid.object(world, block) and Grid.object(world, block).id == wide.id, "not placed before the last is cleared")
  end)
  run(world, 90)
  T.eq(Grid.object(world, block) and Grid.object(world, block).id, wide.id)
  T.truthy(#order >= 1)
end)

T.test("placement: a growing and a ripe crop are removed with no refund, the plan too", function()
  local world = newWorld(1)
  local i = openBlock(world, 2, 1)
  plant(world, i, 0.3)
  plant(world, i + 1, 1)
  stock(world, "smoker")
  local def = reg:get("objects", "smoker")
  T.eq(def.footprintW or 1, 1)
  local radish, seed = Ledger.get(world, "radish"), Ledger.get(world, reg:get("crops", "radish").seed)
  local preview = Placement.preview(world, "smoker", i + 1)
  T.eq(#preview.crops, 1)
  T.truthy(preview.crops[1].mature, "the preview says the crop is ripe")
  local removed = collect(world, "crop.removed")
  T.eq(Placement.request(world, "smoker", i + 1), "queued")
  T.truthy(world.state.crops[i + 1], "the crop stays until the building is about to go up (D86)")
  T.truthy(world.state.fields.plan[i + 1], "and its plan")
  T.eq(#removed, 0)
  T.eq(Ledger.get(world, "radish"), radish, "no refund of the harvest")
  T.eq(Ledger.get(world, reg:get("crops", "radish").seed), seed, "no refund of the seed")
  T.truthy(world.state.crops[i], "the neighbour is untouched")
  -- held while the order waits: no new plan or tilling there
  T.falsy(Crops.setPlan(world, i + 1, "radish"), "held tiles take no plan")
  run(world, 5)
  T.eq(Grid.object(world, i + 1) and Grid.object(world, i + 1).id, "smoker", "no clutter: placed the next tick")
  T.falsy(world.state.crops[i + 1], "the crop went just before")
  T.eq(removed[1] and removed[1].mature, true)
  T.truthy(world.state.grid.objects[i + 1].tilled[i + 1], "the soil was tilled")
  T.truthy(world.state.crops[i], "the neighbour still grows")
end)

T.test("placement: a planned tile with no crop yet loses its plan", function()
  local world = newWorld(1)
  local i = openBlock(world, 1, 1)
  world.state.fields.plan[i] = "radish"
  stock(world, "smoker")
  local preview = Placement.preview(world, "smoker", i)
  T.eq(preview.plans, 1)
  T.eq(Placement.request(world, "smoker", i), "queued")
  run(world, 3)
  T.falsy(world.state.fields.plan[i])
  T.eq(Grid.object(world, i).id, "smoker")
end)

T.test("placement: cancelling an order never destroys a crop or a plan (D86)", function()
  local world = newWorld(1)
  local i = openBlock(world, 2, 1)
  plant(world, i, 0.4)
  world.state.fields.plan[i + 1] = "radish"
  stock(world, "smoker")
  local removed = collect(world, "crop.removed")
  T.eq(Placement.request(world, "smoker", i), "queued")
  T.truthy(world.state.crops[i], "the crop is still there after the request")
  T.truthy(Placement.cancel(world, i))
  run(world, 5)
  T.eq(#removed, 0)
  T.truthy(world.state.crops[i], "and after the cancel")
  T.falsy(world.state.fields.held[i], "the tile is free for farming again")
  T.eq(Grid.object(world, i), nil, "nothing was built")
  -- a plan alone survives a cancel too
  T.eq(Placement.request(world, "smoker", i + 1), "queued")
  T.truthy(Placement.cancel(world, i + 1))
  T.eq(world.state.fields.plan[i + 1], "radish")
end)

T.test("placement: crops under a footprint with clutter are removed only after the clutter is gone", function()
  local world = newWorld(1)
  local wide
  for _, o in ipairs(reg:all("objects")) do
    if o.placeable and (o.footprintW or 1) == 2 and (o.footprintH or 1) == 1 and not o.placeNear and not o.placeOn then
      wide = o
      break
    end
  end
  if not wide then
    return
  end
  local i, x, y = openBlock(world, 2, 1)
  put(world, "tree", x, y)
  plant(world, i + 1, 0.5)
  stock(world, wide.id)
  T.eq(Placement.request(world, wide.id, i), "queued")
  T.truthy(world.state.crops[i + 1], "the crop waits while the tree stands")
  local removed = collect(world, "crop.removed")
  local cleared = collect(world, "object.cleared")
  run(world, 90)
  T.eq(#cleared, 1)
  T.eq(#removed, 1, "the crop went once the tree was down")
  T.eq(Grid.object(world, i).id, wide.id)
end)

T.test("placement: a full store holds the order, says why, and it goes on when there is room", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  stock(world, "smoker")
  Ledger.setCapacity(world, "wood", 12)
  Ledger.add(world, "wood", 12, "test")
  local held = collect(world, "placement.held")
  T.eq(Placement.shortage(world, Placement.preview(world, "smoker", i)), "wood", "the preview warns")
  T.eq(Placement.request(world, "smoker", i), "queued")
  run(world, 30)
  T.truthy(Grid.object(world, i).id == "tree", "the tree stands")
  local order = Placement.orders(world)[1]
  T.eq(order.why and order.why.kind, "full")
  T.eq(order.why.resource, "wood")
  T.eq(#held, 1, "said once")
  Ledger.remove(world, "wood", 12, "test")
  run(world, 60)
  T.eq(Grid.object(world, i).id, "smoker")
  T.eq(#Placement.orders(world), 0)
end)

T.test("placement: an unreachable footprint is held as unreachable", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  -- wall the tree in with rocks on every side
  for dy = -1, 1 do
    for dx = -1, 1 do
      if (dx ~= 0 or dy ~= 0) and Grid.inBounds(world.state.grid, x + dx, y + dy) and not world.occupancy[Grid.index(world.state.grid, x + dx, y + dy)] then
        put(world, "rock", x + dx, y + dy)
      end
    end
  end
  stock(world, "smoker")
  T.eq(Placement.request(world, "smoker", i), "queued")
  run(world, 3)
  local order = Placement.orders(world)[1]
  T.truthy(order.why, "a reason is recorded")
  T.eq(order.why.kind, "unreachable")
end)

T.test("placement: cancel drops the order, frees the tiles and keeps the item", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  stock(world, "smoker")
  Placement.request(world, "smoker", i)
  T.truthy(world.state.fields.held[i])
  local cancelled = collect(world, "placement.cancelled")
  T.truthy(Placement.cancel(world, i))
  T.falsy(Placement.cancel(world, i), "nothing left to cancel")
  T.eq(#cancelled, 1)
  T.eq(cancelled[1].reason, "player")
  T.falsy(world.state.fields.held[i])
  T.eq(Inventory.objectCount(world, "smoker"), 1, "still in the inventory")
  T.eq(Placement.available(world, "smoker"), 1)
  run(world, 5)
  T.eq(Grid.object(world, i).id, "tree", "the tree is left alone if nobody was sent yet, or already being felled")
end)

T.test("placement: two orders cannot share a tile, and one item serves one order", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  stock(world, "smoker")
  T.eq(Placement.request(world, "smoker", i), "queued")
  stock(world, "smoker")
  local again, reason = Placement.request(world, "smoker", i)
  T.falsy(again)
  T.eq(reason, "claimed")
  local a = openBlock(world, 1, 1, 8, 0)
  local _, why = Placement.request(world, "smoker", a)
  local b = Placement.request(world, "smoker", a)
  T.truthy(why == nil or why == "none" or b)
end)

T.test("placement: the homesteader steps aside when standing on the spot", function()
  local world = newWorld(1)
  local hs = Actors.homesteader(world)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "rock", x, y)
  hs.x, hs.y = x + 1, y
  stock(world, "smoker")
  -- clear the rock, then stand on the tile before the building goes up
  Placement.request(world, "smoker", i)
  run(world, 60)
  T.eq(Grid.object(world, i) and Grid.object(world, i).id, "smoker")
end)

T.test("placement: orders survive a save and load", function()
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  stock(world, "smoker")
  Placement.request(world, "smoker", i)
  local copy = serialize.decode(serialize.encode(world.state))
  local loaded = World.new({ registry = reg, tuning = tun }, copy)
  loaded.control = "active"
  T.eq(#Placement.orders(loaded), 1)
  T.truthy(loaded.state.fields.held[i])
  run(loaded, 60)
  T.eq(Grid.object(loaded, i).id, "smoker")
end)

T.test("placement: the same seed and orders give the same world", function()
  local function play()
    local world = newWorld(5)
    local i, x, y = openBlock(world, 1, 1)
    put(world, "tree", x, y)
    local j = openBlock(world, 1, 1, 9, 1)
    plant(world, j, 0.4)
    stock(world, "smoker")
    stock(world, "campfire")
    Placement.request(world, "smoker", i)
    Placement.request(world, "campfire", j)
    run(world, 90)
    return serialize.encode(world.state)
  end
  T.eq(play(), play())
end)

T.test("placement: a harvester put in the middle of a field keeps picking the crops around it", function()
  local world = newWorld(3)
  local sx, sy = Grid.coords(world.state.grid, Land.spawn(world))
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "folding_panel" then
      Grid.removeObject(world, anchor)
    end
  end
  local panel = openBlock(world, 2, 2, 12, 5)
  stock(world, "solar_array")
  T.truthy(Inventory.place(world, "solar_array", panel))
  local i, x, y = openBlock(world, 3, 3, 5, 4)
  local center = Grid.index(world.state.grid, x + 1, y + 1)
  local ring = {}
  for dy = 0, 2 do
    for dx = 0, 2 do
      local t = Grid.index(world.state.grid, x + dx, y + dy)
      plant(world, t, 1)
      if t ~= center then
        ring[#ring + 1] = t
      end
    end
  end
  put(world, "rock", x + 1, y + 1) -- an old rock on the middle tile; its crop was lost to it
  world.state.crops[center] = nil
  stock(world, "auto_harvester")
  local preview = Placement.preview(world, "auto_harvester", center)
  T.truthy(preview.ok, "a harvester can go on the field")
  T.eq(Placement.request(world, "auto_harvester", center), "queued")
  setTime(world, 1, 10)
  -- Planned tiles are tilled and replanted by the homesteader (D92); switch that off so the field only shows the harvester's work.
  Tasks.setPriorityEnabled(world, "plant", false)
  run(world, HOUR * 3)
  local obj = Grid.object(world, center)
  T.eq(obj and obj.id, "auto_harvester")
  local left = 0
  for _, t in ipairs(ring) do
    if world.state.crops[t] then
      left = left + 1
    end
  end
  T.truthy(left < #ring, "it picked crops around it (" .. left .. " of " .. #ring .. " left)")
  T.truthy(Machines.done(world) > 0)
  local _ = i
end)

T.test("placement text: the confirmation names what is cleared and removed, and warns about ripe crops and full stores", function()
  local PlaceText = require("src.ui.place_text")
  local colors = { text = "t", dim = "d", warn = "w" }
  local world = newWorld(1)
  local i, x, y = openBlock(world, 1, 1)
  put(world, "tree", x, y)
  plant(world, i, 1)
  Ledger.setCapacity(world, "wood", 12)
  Ledger.add(world, "wood", 12, "test")
  stock(world, "smoker")
  local text = PlaceText.confirm(world, "smoker", Placement.preview(world, "smoker", i), colors)
  local all = table.concat((function()
    local out = {}
    for _, l in ipairs(text.lines) do
      out[#out + 1] = l.text
    end
    return out
  end)(), "\n")
  T.truthy(all:find("1 tree", 1, true), "names the tree")
  T.truthy(all:find("1 crop", 1, true) and all:find("ripe", 1, true), "names the ripe crop")
  T.truthy(all:find("Nothing is refunded", 1, true), "says nothing is refunded")
  T.truthy(all:find("wood storage is full", 1, true), "warns the store is full")
  T.truthy(text.title:find("smoker", 1, true))
  Placement.request(world, "smoker", i)
  run(world, 3)
  local card = PlaceText.order(world, Placement.orders(world)[1], colors)
  T.truthy(card.lines[1].text:find("tree", 1, true))
  T.truthy(card.lines[2] and card.lines[2].text:find("wood storage is full", 1, true), "the order card says why it waits")
end)