-- The store's item card (#266, D107): a tap on a Catalog row shows what the item is (what it gives, its cost,
-- what it needs, its cap) before anything is bought; a long-press (the "context" action) shows the same card;
-- the card's button orders it; the town shop's rows do the same with no delivery fee. Last, the gate (D164, #343): a
-- test-only flagged item (`requiresFooting`; no shipped item carries it) shows locked, with the reason, in the Catalog
-- row, its item card and the Journal card, on touch and keyboard, then opens once Footing is held.
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
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
  assert(
    not scene.card:isOpen() and #world.state.market.orders == 1,
    "the card's button did not order: open="
      .. tostring(scene.card:isOpen())
      .. " orders="
      .. #world.state.market.orders
  )
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

  -- The gate: the axe flagged for the test, shown but locked until Footing is held.
  d:frames(3)
  local axe = world.registry:get("catalog", "axe")
  rawset(axe, "requiresFooting", true)
  local ok, err = pcall(function()
    Ledger.add(world, "money", 200)
    d:pick("Catalog")
    d:frames(3)
    scene = d:scene()
    box = scene.box
    d:shot("gate_row")
    local locked = rowFor(scene, "axe")
    d:click(box.x + 60, locked.y + 8)
    d:frames(2)
    assert(scene.card:isOpen(), "a locked row did not open its card")
    d:shot("gate_card")
    local button = scene.card.buttons.list[1]
    assert(
      button and not button.enabled and button.label == "Locked",
      "the card's button should read Locked and be off"
    )
    local orders = #world.state.market.orders
    d:click(button.x + button.w / 2, button.y + button.h / 2)
    d:frames(2)
    assert(#world.state.market.orders == orders and scene.card:isOpen(), "a locked item was ordered")
    d:key("escape") -- the keyboard path: Escape puts the card away
    assert(not scene.card:isOpen(), "Escape left the card open")
    -- Footing held: the same row opens (still in the Ledger), then the gate closes again.
    world.state.footing.held = true
    d:frames(30)
    d:shot("gate_open")
    local open = rowFor(scene, "axe")
    d:click(box.x + 60, open.y + 8)
    d:frames(2)
    assert(scene.card.buttons.list[1].enabled, "the card's button should be on once Footing is held")
    d:key("escape")
    world.state.footing.held = false
    d:key("escape") -- and the book
    d:frames(2)
    -- The Journal card of the same item.
    d:pick("Journal")
    d:frames(6)
    d:scene():select("axe")
    d:frames(3)
    d:shot("gate_journal")
    for _ = 1, 5 do -- Escape puts away the card, then the chapter, then the book
      if d.game.app:top().name == "book" then
        d:key("escape")
        d:frames(2)
      end
    end
    assert(d.game.app:top().name ~= "book", "Escape did not leave the book")
  end)
  rawset(axe, "requiresFooting", nil)
  world.state.footing.held = false
  if not ok then
    error(err, 0)
  end
end
