-- The contracts board (D197, #372): the truck panel's Contracts button locked before Footing and open after, the board at
-- home (Fill disabled, "In town"), in town (Fill, then Sell the load filling the rest), and the empty board while slipped.
-- Footing, stock and charge are set directly (as if earned, harvested and charged); everything else is input.
local Contracts = require("src.sim.systems.contracts")
local Food = require("src.sim.systems.food")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")

--- Press the board button, whatever count its label carries.
local function pressBoard(d)
  for _, label in ipairs(d:labels()) do
    if label:find("^Contracts") then
      d:press(label)
      return
    end
  end
  error("no Contracts button; have: " .. table.concat(d:labels(), ", "))
end

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)
  local truck = Land.truck(world)
  Power.add(world, truck, world.tuning.economy.tripCost + 2)
  d:frames(3)

  -- Before Footing: the truck panel's board button says why it is locked.
  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(4)
  d:shot("truck_locked")
  d:key("escape")
  d:frames(2)

  -- Footing earned and goods in the barn: the board is posted.
  world.state.footing.held = true
  for _, id in ipairs({ "egg", "radish", "potato", "lettuce", "beans", "corn", "tomato", "wood" }) do
    Ledger.add(world, id, 30)
    Food.setKeep(world, id, 0)
  end
  Contracts.roll(world)
  assert(#Contracts.list(world) > 0, "nothing was posted")
  d:clickTile(tx, ty)
  d:frames(4)
  d:shot("truck_open")
  pressBoard(d)
  d:frames(3)
  d:shot("board_home")
  d:key("escape")
  d:frames(2)

  -- In town: the board with Fill, then Sell the load fills what is left.
  Market.autoLoad(world)
  d:press("Drive to town")
  d:frames(4)
  d:shot("town")
  pressBoard(d)
  d:frames(3)
  d:shot("board_town")
  local first = Contracts.list(world)[1]
  d:press("Fill")
  d:frames(3)
  assert(Contracts.reputation(world) == 1, "Fill did not finish a contract")
  assert(not Contracts.find(world, first.id), "the contract is still open")
  d:shot("board_filled")
  d:key("escape")
  d:frames(2)
  local _, total = Market.loadQuote(world)
  d:press("Sell the load  $" .. total)
  d:frames(3)
  d:shot("town_sold")
  d:press("Drive home")
  d:frames(3)

  -- Slipped: no new offers, and the board says so when nothing is open.
  world.state.contracts.open = {}
  world.state.footing.slipped = true
  d:clickTile(tx, ty)
  d:frames(4)
  pressBoard(d)
  d:frames(3)
  d:shot("board_slipped")
  d:key("escape")
  d:frames(2)
end
