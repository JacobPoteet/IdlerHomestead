-- Keep targets and the truck load (D75, #196): the Pantry's keep list (automatic, then one set by
-- hand), the truck panel at home with an empty truck, Load the truck before and after Auto-load, the
-- reserve guard when loading kept wood, the loaded truck at home, and the town selling the load.
-- Stock and charge are set up directly (as if harvested and charged); everything else is input.
local Food = require("src.sim.systems.food")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")

local function rowOf(scene, id)
  for _, row in ipairs(scene.rows) do
    if row.res.id == id then
      return row
    end
  end
  error("no row for " .. id)
end

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)
  Ledger.add(world, "radish", 40)
  Ledger.add(world, "sunfish", 8)
  Ledger.add(world, "egg", 12)
  Ledger.add(world, "potato", 10)
  Ledger.add(world, "stone", 25)
  Ledger.add(world, "scrap", 6)
  Ledger.add(world, "wood", 30)
  d:frames(3)

  -- The Pantry: every good with its keep (Auto) and its spare.
  d:pick("Pantry")
  d:frames(3)
  d:shot("pantry_keep")
  -- Keep fewer radishes: the "-" on the radish row, three times.
  local scene, box = d:scene(), d:scene().box
  for _ = 1, 3 do
    local row = rowOf(scene, "radish")
    d:click(box.x + box.w - 122 + 12, row.y + 12)
    d:frames(1)
  end
  d:frames(2)
  d:shot("pantry_keep_set")
  -- Hold the "+" on the radish row: the keep climbs faster the longer it is held, then stops at the top.
  local plusX = box.x + box.w - 96 + 12
  local before = Food.keeps(world).radish
  d:hold(plusX, rowOf(d:scene(), "radish").y + 12, 1)
  local after1 = Food.keeps(world).radish
  assert(after1 > before + 5, "holding + did not repeat")
  d:hold(plusX, rowOf(d:scene(), "radish").y + 12, 3)
  assert(Food.keeps(world).radish > after1 + 30, "a long hold did not speed up")
  d:shot("pantry_keep_held")
  -- Hold the "-" to bring it back down to zero; the hold stops there.
  d:hold(box.x + box.w - 122 + 12, rowOf(d:scene(), "radish").y + 12, 8)
  assert(Food.keeps(world).radish == 0, "holding - did not reach zero")
  d:shot("pantry_keep_zero")
  Food.setKeep(world, "radish", nil) -- back to Auto for the load steps below
  d:key("escape")
  d:frames(2)

  -- The truck at home: an empty load and the spare left at home.
  local truck = Land.truck(world)
  Power.add(world, truck, world.tuning.economy.tripCost + 2)
  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(4)
  d:shot("truck_home_empty")

  -- Load the truck: the list, then Auto-load.
  d:press("Load the truck")
  d:frames(3)
  d:shot("load_empty")
  d:press("Auto-load")
  d:frames(3)
  assert(Market.loadUnits(world) > 0, "auto-load loaded nothing")
  d:shot("load_auto")
  -- Hold the "+" on the stone row: it climbs and stops at the spare (never into the keep prompt).
  Market.clearLoad(world)
  d:frames(2)
  scene, box = d:scene(), d:scene().box
  local fish = rowOf(scene, "stone")
  d:hold(box.x + box.w - 106 + 12, fish.y + 18, 4)
  assert(Market.loaded(world, "stone") > 5, "holding + on the load did not repeat")
  assert(d:scene().name == "load", "holding + opened a prompt")
  d:shot("load_held")
  Market.clearLoad(world)
  d:press("Auto-load")
  d:frames(3)

  -- Wood is kept for winter: a + on its row asks first (the reserve guard).
  Market.setLoad(world, "radish", Market.loaded(world, "radish") - 5) -- make room in the cargo for the wood
  d:frames(2)
  scene, box = d:scene(), d:scene().box
  local wood = rowOf(scene, "wood")
  d:click(box.x + box.w - 78 + 15, wood.y + 18) -- +5
  d:frames(3)
  assert(d:scene().name == "confirm", "loading kept wood did not ask")
  d:shot("reserve_guard")
  d:press("Load anyway")
  d:frames(3)
  assert(Market.loaded(world, "wood") == 5, "the confirmed wood is not loaded")
  d:shot("load_wood")
  d:key("escape")
  d:frames(4)
  d:shot("truck_home_loaded")

  -- Drive to town and sell the load.
  d:press("Drive to town")
  d:frames(4)
  d:shot("town_load")
  local _, total = Market.loadQuote(world)
  d:press("Sell the load  $" .. total)
  d:frames(3)
  assert(Market.loadUnits(world) == 0, "the load was not sold")
  d:shot("town_sold")
  d:press("Drive home")
  d:frames(3)
end
