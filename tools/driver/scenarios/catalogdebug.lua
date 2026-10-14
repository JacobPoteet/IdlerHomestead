-- Debug cheat mode in the Catalog (D126): the normal Catalog, F1 revealing the Debug button, cheat mode
-- listing every item for $0, a few free grants (a building, seeds, an upgrade), the item card, and the
-- granted building placed with the real Place tool.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
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
  d:advance(1)
  local money = Ledger.get(world, "money")

  d:pick("Catalog")
  d:frames(3)
  d:shot("normal")
  d:key("f1") -- the debug overlay reveals the Debug button
  d:frames(3)
  d:shot("debug_button")
  d:press("Debug")
  d:frames(3)
  d:shot("cheat_on")

  local scene = d:scene()
  local box = scene.box
  -- A tap on a row opens the card: free, and "Right now" says so.
  d:click(box.x + 60, rowFor(scene, "woodshed").y + 8)
  d:frames(2)
  assert(scene.card:isOpen())
  d:shot("card")
  local buy = scene.card.buttons.list[1] -- the card's buttons are not on the scene's own lists
  assert(buy.label == "Get (free)", buy.label)
  d:click(buy.x + buy.w / 2, buy.y + buy.h / 2)
  d:frames(3)
  assert(Inventory.objectCount(world, "woodshed") == 1, "woodshed delivered at once")
  d:press("Get") -- first row button: the first listed item
  d:frames(2)
  d:shot("granted")
  assert(Ledger.get(world, "money") == money, "no money moved")
  assert(#world.state.market.orders == 0, "nothing ordered")

  -- The unique woodshed now reads Owned; it is refused a second time.
  assert(not Market.debugGrant(world, "woodshed"))
  d:frames(2)
  d:shot("owned")
  d:key("escape")
  d:frames(3)

  -- Place it with the real Place tool.
  d:tryPress("Got it") -- a status notice may have popped up meanwhile
  local hs = d:scene()
  d:pick("Place woodshed")
  local grid = world.state.grid
  local hx, hy = d:homesteaderTile()
  local spot, x, y
  for r = 3, 12 do -- the nearest tile where the woodshed fits
    for dx = -r, r do
      local tx, ty = hx + dx, hy + r
      if Grid.inBounds(grid, tx, ty) and Inventory.canPlace(world, "woodshed", Grid.index(grid, tx, ty)) then
        spot, x, y = Grid.index(grid, tx, ty), tx, ty
        break
      end
    end
    if spot then
      break
    end
  end
  assert(spot, "no spot for the woodshed")
  local cx, cy = hs.camera:tileToWorld(x + 1, y + 1)
  hs.camera:centerOn(cx, cy, d.game.app.view)
  hs.hover = spot
  d:frames(2)
  d:shot("place_preview")
  d:tryPress("Got it")
  d:clickTile(x, y)
  d:frames(2)
  d:shot("place_confirm")
end
