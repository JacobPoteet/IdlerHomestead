-- The store's item card (#266, D107): a tap on a Catalog row shows what the item is (what it gives, its cost,
-- what it needs, its cap) before anything is bought; a long-press (the "context" action) shows the same card;
-- the card's button orders it; the town shop's rows do the same with no delivery fee.
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")

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
  d:advance(1)
  -- A few ideas learned and some money, as if earned, so the list has gear, buildings and a refusal.
  local known = world.meta.journal.known
  for _, id in ipairs({ "smoker", "axe", "goat_pen", "goats", "auto_harvester" }) do
    known[id] = true
  end
  Ledger.add(world, "money", 60)
  d:frames(2)

  d:pick("Catalog")
  d:frames(3)
  d:shot("list")
  local scene = d:scene()
  local box = scene.box

  -- A tap on the name of a row: the card, nothing bought.
  local money = Ledger.get(world, "money")
  d:click(box.x + 60, rowFor(scene, "axe").y + 8)
  d:frames(2)
  assert(scene.card:isOpen(), "tapping a row did not open the card")
  assert(Ledger.get(world, "money") == money and #world.state.market.orders == 0, "the tap bought something")
  d:shot("card_axe")
  d:press("Close")
  assert(not scene.card:isOpen(), "Close left the card open")

  -- A long-press (or right click) shows the same card; this one is not affordable or housed yet.
  local row = rowFor(scene, "goats")
  scene:action("context", { x = box.x + 60, y = row.y + 8 })
  d:frames(2)
  assert(scene.card:isOpen(), "a long-press did not open the card")
  d:shot("card_goats_refused")
  d:key("escape")
  assert(not scene.card:isOpen(), "Escape left the card open")

  -- A building card, then its button orders it.
  d:click(box.x + 60, rowFor(scene, "smoker").y + 8)
  d:frames(2)
  d:shot("card_smoker")
  local buy = scene.card.buttons.list[1] -- the card's own order button (the row has one with the same label)
  assert(buy and buy.enabled, "the card's order button is missing or off")
  d:click(buy.x + buy.w / 2, buy.y + buy.h / 2)
  d:frames(2)
  assert(not scene.card:isOpen() and #world.state.market.orders == 1,
    "the card's button did not order: open=" .. tostring(scene.card:isOpen()) .. " orders=" .. #world.state.market.orders)
  d:shot("ordered")
  d:key("escape")
  d:frames(2)

  -- The town shop: same card, no delivery fee.
  local truck = Land.truck(world)
  Power.add(world, truck, world.tuning.economy.tripCost + 2)
  local tx, ty = d:nearestObject("truck")
  d:clickTile(tx, ty)
  d:frames(3)
  d:press("Drive to town")
  d:frames(4)
  local town = d:scene()
  local first = town.shopRows[1]
  d:click(first.x + 30, first.y + 8)
  d:frames(2)
  assert(town.card:isOpen(), "tapping a town row did not open the card")
  d:shot("town_card")
  d:key("escape")
  d:press("Drive home")
end
