-- The hammer and the crate (D139, #295): deliveries counted on the tool badge, the delivery stamp opening the
-- Hammer's ring with the crate's items as world sprites, placing one from the ring, key 6, Order more opening the
-- Catalog on its buildings, and a crate too big for the ring ending in More, which opens the full tray.
local Inventory = require("src.sim.systems.inventory")
local Market = require("src.sim.systems.market")

local function centre(r)
  return r.x + r.w / 2, r.y + r.h / 2
end

return function(d)
  d:newGame()
  d:frames(10)
  local world = d:world()
  local scene = d:scene()
  local s = scene.app.view.scale
  Inventory.addObject(world, "campfire")
  Inventory.addObject(world, "campfire")
  Inventory.addObject(world, "smoker")
  Inventory.addObject(world, "shack")
  scene:layout()
  d:frames(2)
  assert(scene:crateCount() == 4, "four things in the crate")
  d:shot("badge_count")

  -- The delivery stamp opens the wheel with the Hammer's ring: the crate's items, then the four verbs.
  d:pressHud("delivery")
  assert(scene.wheel and scene.wheel.highlight == "hammer", "the stamp opens the Hammer's ring")
  d:shot("crate_ring")
  -- Hovering a crate item names it; a tap holds its ghost.
  local lay = scene.wheelLayout
  local items = scene:ringItems("hammer")
  local shack
  for k, item in ipairs(items) do
    if item.object == "shack" then
      shack = k
    end
  end
  local hx, hy = centre(lay.ring[shack])
  d.game.input:mousemoved(hx * s, hy * s, 0, 0, false)
  d:frames(2)
  d:shot("crate_hover")
  d:click(hx, hy)
  assert(scene.mode == "place" and scene.placing == "shack", "a ring item holds its ghost")
  d:shot("placing_shack")
  d:key("escape")
  d:frames(2)

  -- Key 6: the Hammer alone takes the first item in the crate.
  d:key("6")
  assert(scene.placing == "campfire", "6 takes the first crate item")
  d:shot("key_hammer")
  d:key("escape")
  d:frames(2)

  -- Order more: the Catalog, scrolled to its first building (every item listed, so the list scrolls).
  Market.setCheat(world, true)
  d:pick("Order more")
  d:frames(3)
  local catalog = d:scene() -- the Ledger's Catalog page
  assert(catalog.name == "catalog", "Order more opens the Catalog")
  assert(catalog.list.offset > 0, "scrolled down to the buildings")
  d:shot("order_more")
  d:key("escape")
  d:frames(2)
  Market.setCheat(world, false)

  -- A crate with more kinds than the ring shows ends in More, which opens the full tray.
  local kinds = 0
  for _, def in ipairs(world.registry:all("objects")) do
    if def.placeable and kinds < 8 then
      Inventory.addObject(world, def.id)
      kinds = kinds + 1
    end
  end
  scene:openHammerRing()
  d:frames(2)
  d:shot("crate_more")
  items = scene:ringItems("hammer")
  local more
  for k, item in ipairs(items) do
    if item.kind == "more" then
      more = k
    end
  end
  assert(more, "the ring ends in More")
  d:click(centre(scene.wheelLayout.ring[more]))
  assert(scene.palette == "tools", "More opens the tools tray")
  d:shot("crate_tray")
end
