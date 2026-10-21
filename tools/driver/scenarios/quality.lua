-- Crop quality (D182, #368): the Pantry and the truck's Load list show the tier of stocked produce, the town's load
-- lists the tiers it sells at their price, and the tile card of a growing crop names the grade it would get now (D185: normal or fine).
-- Stock and crop state are set through the sim (a scenario cannot wait for harvests).
local Grid = require("src.sim.grid")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local Quality = require("src.sim.systems.quality")

local function hasLine(lines, text)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then
      return true
    end
  end
  return false
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  d:advance(1)

  -- Stock: radishes and potatoes of both tiers.
  Ledger.add(world, "radish", 40)
  Quality.add(world, "radish", "fine", 12)
  Ledger.add(world, "potato", 20)
  Quality.add(world, "potato", "fine", 5)
  d:frames(3)

  d:pick("Pantry")
  d:frames(3)
  d:shot("pantry_tiers")
  d:key("escape")
  d:frames(2)

  -- The truck: load the best, see the tiers in the Load list, drive to town and sell them.
  Power.add(world, Land.truck(world), world.tuning.economy.tripCost + 2)
  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(4)
  d:press("Load the truck")
  d:frames(3)
  d:press("Auto-load")
  d:frames(3)
  assert(Market.loadUnits(world) > 0, "auto-load loaded nothing")
  d:shot("load_tiers")
  d:key("escape")
  d:frames(4)
  d:press("Drive to town")
  d:frames(4)
  local lines, total = Market.loadQuote(world)
  local tiered = false
  for _, line in ipairs(lines) do
    tiered = tiered or line.worth > line.units * line.price
  end
  assert(tiered, "the quote pays the tiers")
  d:shot("town_tiers")
  d:press("Sell the load  $" .. total)
  d:frames(3)
  assert(Market.loadUnits(world) == 0, "the load was not sold")
  d:press("Drive home")
  d:frames(3)

  -- The tile card of a crop: its grade now, then neglected.
  local x, y = d:freeTileNear(2, 2)
  local i = Grid.index(world.state.grid, x, y)
  world.state.fields.tilled[i] = true
  world.state.grid.fertility[i] = 0.95
  world.state.crops[i] = { id = "carrot", growth = 0.5, moisture = 1, thirst = 0 }
  assert(hasLine(scene:tileInfo(i), "Quality: fine"), "rich ground grades fine")
  world.state.grid.fertility[i] = 0.1
  world.state.soil.weeds[i] = 0.9
  assert(hasLine(scene:tileInfo(i), "Quality: normal"), "worn, weedy ground grades normal")
  world.state.grid.fertility[i] = 0.95
  world.state.soil.weeds[i] = nil
  assert(hasLine(scene:tileInfo(i), "Quality: fine"), "and fine again once it is cleaned")
  scene.selected = i
  d:frames(12)
  d:shot("tile_card_fine")
  scene.selected = nil
  d:frames(4)
end
