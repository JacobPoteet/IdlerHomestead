-- Chickens (GDD §7.7, D63): a coop placed near the truck, hens roaming its run, eggs waiting in the
-- nest box (HUD chips), the object card, a tap that sends the homesteader to collect them (with the
-- toast), and the Animals chapter of the journal. The scenario places the coop and buys the hens
-- directly (as if bought and driven home), then plays through the real HUD and input.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(1)

  -- The free spot nearest the truck for a two-tile coop.
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx - 3) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, "chicken_coop", i) then
      best, bestDist = i, dist
    end
  end
  assert(best, "no spot for the coop")
  local scene = d:scene()
  local view = d.game.app.view
  local bx, by = Grid.coords(grid, best)
  local cx, cy = scene.camera:tileToWorld(bx + 1, by + 1)
  scene.camera:centerOn(cx, cy, view)

  Inventory.addObject(world, "chicken_coop")
  assert(Inventory.place(world, "chicken_coop", best))
  Ledger.add(world, "hen", 5, "driver")
  Ledger.add(world, "chicken_feed", 10, "driver")
  local s = world.state.animals
  s.feed, s.water = 12, 4
  scene.selected = best
  d:frames(3)
  d:shot("coop_card_hens")

  -- Eggs pile up in the nest box: cream dots on the coop and the egg chip in the HUD.
  s.nest = 5
  scene.toast = nil
  d:frames(2)
  d:shot("eggs_waiting")

  -- Tap the coop: the homesteader walks over, collects the eggs and tops up the bowls.
  d:clickTile(bx, by)
  local seconds = 0
  while s.nest > 0 and seconds < 60 do
    d:frames(20)
    seconds = seconds + 1
  end
  assert(s.nest == 0, "the eggs were never collected")
  assert(Ledger.get(world, "egg") >= 5, "the eggs did not reach the ledger")
  d:frames(2)
  d:shot("collected_toast")

  -- The Animals chapter of the Field Journal: the coop and hens appear once the notes are written.
  world.events:emit("crop.harvested", { amount = 1 })
  world.events:emit("market.trip", {})
  scene.toast = nil
  d:press("Journal")
  d:frames(3)
  d:shot("journal")
end
