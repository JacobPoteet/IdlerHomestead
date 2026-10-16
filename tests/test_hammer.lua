-- The hammer and the crate (D139, #295): the crate's items and count, the Hammer's ring, what the Hammer takes
-- from the wheel, and its Move, Pick up and Demolish modes routed to the D98 and D110 flows. A stand-in scene
-- borrows the real Homestead methods; the flows themselves are tested in test_pickup and test_destroy.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Homestead = require("src.scenes.homestead")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

-- Place `id` on the nearest legal tile to the spawn; returns its anchor.
local function place(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local d = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or d < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, d
    end
  end
  Inventory.addObject(world, id)
  T.truthy(Inventory.place(world, id, best), "placed " .. id)
  return best
end

-- A tile with nothing on it and no crop, near the spawn.
local function emptyTile(world)
  for i = Land.spawn(world), #world.state.grid.terrain do
    if not Grid.object(world, i) and not world.state.crops[i] then
      return i
    end
  end
end

--- A stand-in scene: the real methods, with the flows, wheel and panels recorded instead of run.
local function hammerScene(world)
  local scene = setmetatable({
    world = world,
    app = { ctx = { tuning = tun }, view = { w = 640, h = 360 } },
    mode = "act",
    calls = {},
    toasts = {},
  }, { __index = Homestead })
  local function record(name)
    return function(_, ...)
      scene.calls[#scene.calls + 1] = { name, ... }
    end
  end
  scene.layout = function() end
  scene.showToast = function(self, text)
    self.toasts[#self.toasts + 1] = text
  end
  for _, name in ipairs({ "askPickUp", "askDestroy", "askDestroyCrop", "startMove", "openHammerRing", "openPanel" }) do
    scene[name] = record(name)
  end
  return scene
end

T.test("crate: delivered objects with their counts, sorted; items promised to an order are left out", function()
  local world = newWorld()
  local scene = hammerScene(world)
  T.eq(#scene:crateItems(), 0, "an empty crate")
  T.eq(scene:crateCount(), 0)
  Inventory.addObject(world, "smoker")
  Inventory.addObject(world, "campfire")
  Inventory.addObject(world, "campfire")
  local items = scene:crateItems()
  T.eq(#items, 2)
  T.eq(items[1].id, "campfire")
  T.eq(items[1].count, 2)
  T.eq(items[2].id, "smoker")
  T.eq(scene:crateCount(), 3, "the count on the Hammer wedge and the tool badge")
  T.eq(scene:nextPlaceable(), "campfire")
end)

T.test("hammer ring: the crate's items as world sprites, then Move, Pick up, Demolish and Order more", function()
  local world = newWorld()
  local scene = hammerScene(world)
  local ring = scene:ringItems("hammer")
  local kinds = {}
  for _, item in ipairs(ring) do
    kinds[#kinds + 1] = item.kind
  end
  T.eq(table.concat(kinds, ","), "move,pickup,demolish,order", "an empty crate leaves the four verbs")
  Inventory.addObject(world, "campfire")
  ring = scene:ringItems("hammer")
  T.eq(ring[1].kind, "crate")
  T.eq(ring[1].object, "campfire")
  T.eq(ring[1].sprite, "campfire", "a thumbnail of the world sprite")
  T.eq(ring[1].count, 1)
  T.eq(#ring, 5)
end)

T.test("hammer ring: a crate too big to show ends in More, and the ring keeps its cap", function()
  local world = newWorld()
  local scene = hammerScene(world)
  local ids = {}
  for _, def in ipairs(reg:all("objects")) do
    if def.placeable and #ids < tun.ui.wheel.maxRing then
      ids[#ids + 1] = def.id
      Inventory.addObject(world, def.id)
    end
  end
  T.truthy(#ids > tun.ui.wheel.maxRing - 4, "enough kinds of building to overflow the ring")
  local ring = scene:ringItems("hammer")
  T.eq(#ring, tun.ui.wheel.maxRing)
  T.eq(ring[#ring - 4].kind, "more", "More sits before the four verbs")
  T.eq(ring[#ring].kind, "order")
end)

T.test("hammer: a crate item holds its ghost; the Hammer alone takes the first item or shows its ring", function()
  local world = newWorld()
  local scene = hammerScene(world)
  scene:equip("hammer")
  T.eq(scene.calls[1][1], "openHammerRing", "an empty crate shows the ring to choose a mode")
  Inventory.addObject(world, "smoker")
  Inventory.addObject(world, "campfire")
  scene:equip("hammer", { kind = "crate", object = "smoker" })
  T.eq(scene.mode, "place")
  T.eq(scene.placing, "smoker")
  T.eq(scene:currentTool(), "hammer")
  scene:equip("hammer")
  T.eq(scene.placing, "campfire", "the Hammer alone (a key or a flick) takes the first item")
  scene:equip("hammer", { kind = "order" })
  T.eq(scene.calls[#scene.calls][1], "openPanel")
  T.eq(scene.calls[#scene.calls][2], "buildings", "Order more opens the Catalog on its buildings")
end)

T.test("hammer modes: Move, Pick up and Demolish act on the building tapped", function()
  local world = newWorld()
  local scene = hammerScene(world)
  local anchor = place(world, "campfire")
  for _, case in ipairs({ { "move", "startMove" }, { "pickup", "askPickUp" }, { "demolish", "askDestroy" } }) do
    scene:equip("hammer", { kind = case[1] })
    T.eq(scene.mode, "act")
    T.eq(scene.tool, case[1])
    T.eq(scene:currentTool(), "hammer")
    T.truthy(scene:captionText(), "the caption says what a tap does")
    scene.calls = {}
    scene:tap(anchor)
    T.eq(#scene.calls, 1, case[1])
    T.eq(scene.calls[1][1], case[2])
    T.eq(scene.calls[1][2], anchor, "the building's anchor")
  end
end)

T.test("hammer modes: off a building they say so, and Demolish takes a crop", function()
  local world = newWorld()
  local scene = hammerScene(world)
  local tile = emptyTile(world)
  for _, mode in ipairs({ "move", "pickup", "demolish" }) do
    scene:equip("hammer", { kind = mode })
    scene.calls, scene.toasts = {}, {}
    scene:tap(tile)
    T.eq(#scene.calls, 0, mode .. " does nothing off a building")
    T.eq(#scene.toasts, 1, mode .. " says why")
  end
  world.state.crops[tile] = { id = "radish", growth = 0.5, moisture = 1 }
  scene:equip("hammer", { kind = "demolish" })
  scene.calls = {}
  scene:tap(tile)
  T.eq(scene.calls[1][1], "askDestroyCrop")
  T.eq(scene.calls[1][2], tile)
end)

T.test("hammer: the driver's labels reach every Hammer choice", function()
  local world = newWorld()
  local scene = hammerScene(world)
  Inventory.addObject(world, "smoker")
  T.truthy(scene:equipByLabel("Place smoker"))
  T.eq(scene.placing, "smoker")
  T.falsy(scene:equipByLabel("Place shack"), "nothing of that name in the crate")
  T.truthy(scene:equipByLabel("Pick up"))
  T.eq(scene.tool, "pickup")
  T.truthy(scene:equipByLabel("Demolish"))
  T.eq(scene.tool, "demolish")
  T.truthy(scene:equipByLabel("Move"))
  T.eq(scene.tool, "move")
end)
