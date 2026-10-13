-- The roadside stand's "not at the stand" pin (GDD D62, #106): in the Pantry each sellable good has
-- a Stand/Truck toggle; a good set to Truck keeps its spare for the truck load (D75).
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(1)

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
  Ledger.add(world, "sunfish", 10)
  Ledger.add(world, "radish", 8)
  Food.setKeep(world, "sunfish", 0)
  Food.setKeep(world, "radish", 0)

  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_before")

  -- Keep the radishes for the truck: the first Stand toggle in the list.
  local scene = d:scene()
  local rowRadish
  for _, row in ipairs(scene.rows) do
    if row.res.id == "radish" then
      rowRadish = row
    end
  end
  assert(rowRadish, "no radish row")
  local box = scene.box
  d:click(box.x + box.w - 66 + 27, rowRadish.y + 12)
  d:frames(3)
  assert(Food.truckOnly(world, "radish"), "the pin did not take")
  d:shot("pantry_pinned")

  d:key("escape")
  local hours = 0
  while world.state.stand.last == nil and hours < 14 do
    d:advance(1)
    hours = hours + 1
  end
  assert(world.state.stand.last, "the stand never sold")
  assert(Ledger.get(world, "radish") == 8, "the pinned radishes were sold")
  d:press("Pantry")
  d:frames(3)
  d:shot("pantry_after")
end
