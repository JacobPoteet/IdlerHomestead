-- Purchase limits (D114-D116, #252): the Catalog labels what is already owned (a unique building ordered or
-- placed, a superseded basic rod, an upgrade's lower tier), the item card says Owned and what an upgrade
-- replaces, and the roadside stand shows its tiers: the same stand bare, then with the sign, cooler and rack.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")

local function rowFor(scene, id)
  for _, row in ipairs(scene.rows) do
    if row.item.id == id then
      return row
    end
  end
  error("no catalog row for " .. id)
end

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(1)
  local scene, view = d:scene(), d.game.app.view
  local known = world.meta.journal.known
  for _, id in ipairs({
    "woodshed",
    "smoker",
    "sturdy_rod",
    "big_bucket",
    "camp",
    "shack",
    "roadside_stand",
    "stand_sign",
    "chicken_coop",
  }) do
    known[id] = true
  end
  Ledger.add(world, "money", 300)

  -- The roadside stand beside the road (as if bought and placed).
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, "roadside_stand", i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot beside the road")
  Inventory.addObject(world, "roadside_stand")
  assert(Inventory.place(world, "roadside_stand", best))
  local bx, by = Grid.coords(grid, best)
  local cx, cy = scene.camera:tileToWorld(bx + 1, by + 0.5)
  scene.camera:centerOn(cx, cy, view)
  world.state.calendar.elapsed = ((world.state.calendar.day - 1 + 11 / 24) - world.tuning.time.startHour / 24)
    * world.tuning.time.dayLength
  world.state.weather.sky.days[1] = "clear"
  scene.selected = best
  d:frames(3)
  d:shot("stand_bare")

  Inventory.addEquipment(world, "stand_sign")
  d:frames(3)
  d:shot("stand_sign")
  Inventory.addEquipment(world, "stand_cooler")
  Inventory.addEquipment(world, "stand_display")
  d:frames(3)
  d:shot("stand_full")
  scene.selected = nil

  -- Owned things: a woodshed placed, a smoker on its way, the sturdy rod bought (the basic rod is covered),
  -- the shack delivered but not placed.
  Inventory.addObject(world, "woodshed")
  for i = 1, #grid.terrain do
    if Inventory.canPlace(world, "woodshed", i) then
      Inventory.place(world, "woodshed", i)
      break
    end
  end
  Inventory.addEquipment(world, "sturdy_rod")
  Inventory.addObject(world, "shack")
  assert(Market.order(world, "smoker"))
  d:frames(2)

  d:pick("Catalog")
  d:frames(3)
  d:shot("catalog")
  scene = d:scene()
  local box = scene.box
  d:click(box.x + 60, rowFor(scene, "woodshed").y + 8)
  d:frames(2)
  assert(scene.card:isOpen())
  d:shot("card_woodshed_owned")
  d:key("escape")
  d:click(box.x + 60, rowFor(scene, "sturdy_rod").y + 8)
  d:frames(2)
  d:shot("card_sturdy_rod_owned")
  d:key("escape")
  d:wheel(-8, box.x + 100, box.y + 200) -- scroll the list down
  d:frames(2)
  d:shot("catalog_scrolled")
  d:click(box.x + 60, rowFor(scene, "shack").y + 8)
  d:frames(2)
  d:shot("card_shack_owned_replaces")
  d:key("escape")
  d:click(box.x + 60, rowFor(scene, "big_bucket").y + 8)
  d:frames(2)
  d:shot("card_big_bucket")
  d:key("escape")
  d:click(box.x + 60, rowFor(scene, "chicken_coop").y + 8)
  d:frames(2)
  d:shot("card_coop_repeatable")
  d:key("escape")
end
