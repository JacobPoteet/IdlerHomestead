-- Camp to shack by replacement at placement (D115, #253): buy the shack (ordered, delivered), pick it up in the
-- Place tool and hover the camp. The ghost is tinted and labelled "replaces camp", the camp's footprint is
-- outlined, the confirm card says the camp is removed. Cancel keeps the camp; Go ahead puts the shack up over it.
-- Also: a spot away from the camp is refused with the reason toast.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")

return function(d)
  d:newGame()
  local world = d:world()
  local grid = world.state.grid
  d:advance(2)
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  local scene, view = d:scene(), d.game.app.view

  -- Tidy the clutter around the truck so the shots show only the camp and the shack.
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if
      world.registry:get("objects", obj.id).clearable ~= false
      and math.abs(x - tx) <= 12
      and math.abs(y - ty) <= 10
    then
      Grid.removeObject(world, anchor)
    end
  end
  local cx, cy
  for y = ty + 2, ty + 10 do
    for x = tx + 2, tx + 10 do
      if
        not cx
        and Grid.inBounds(grid, x, y)
        and Inventory.canPlace(world, "camp", Grid.index(grid, x, y))
        and Inventory.canPlace(world, "shack", Grid.index(grid, x, y))
      then
        cx, cy = x, y
      end
    end
  end
  assert(cx, "no spot for the camp and the shack")
  Inventory.addObject(world, "camp")
  assert(Inventory.place(world, "camp", Grid.index(grid, cx, cy)))
  local wx, wy = scene.camera:tileToWorld(cx + 1, cy + 1)
  scene.camera:centerOn(wx, wy, view)

  -- Buy the shack: ordered, then delivered the next morning; nothing changes on the land yet.
  world.meta.journal.known.shack = true
  Ledger.add(world, "money", 200)
  assert(Market.order(world, "shack"))
  d:frames(2)
  d:advance(30)
  -- Midday, clear sky, so the shots are readable.
  local now = require("src.sim.systems.calendar").now(world)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((now.day - 1 + 11 / 24) - t.startHour / 24) * t.dayLength
  world.state.weather.sky.days[1] = "clear"
  d:frames(3)
  assert(Inventory.objectCount(world, "shack") == 1, "the shack was not delivered")
  assert(grid.objects[Grid.index(grid, cx, cy)].id == "camp", "the camp changed before the shack was placed")

  scene:layout()
  d:pick("Place shack")
  -- Away from the camp: refused.
  scene.hover = Grid.index(grid, cx + 6, cy)
  d:frames(2)
  d:shot("away_from_camp")
  d:clickTile(cx + 6, cy)
  d:frames(2)
  d:shot("away_refused")
  scene.toast = nil

  -- Over the camp: the replacement preview.
  scene.hover = Grid.index(grid, cx, cy)
  d:frames(2)
  d:shot("preview_replaces")
  d:clickTile(cx, cy)
  d:frames(3)
  assert(scene.placeCard and scene.placeCard.kind == "confirm", "no confirm card over the camp")
  d:shot("confirm_card")

  -- Cancel keeps the camp.
  d:press("Cancel")
  d:frames(2)
  assert(grid.objects[Grid.index(grid, cx, cy)].id == "camp", "cancelling removed the camp")
  assert(Inventory.objectCount(world, "shack") == 1, "cancelling used up the shack")
  d:shot("cancelled_camp_stays")

  -- Go ahead: the shack stands where the camp was; no refund, no second charge.
  d:clickTile(cx, cy)
  d:frames(3)
  local money = Ledger.get(world, "money")
  d:press("Go ahead")
  d:frames(4)
  assert(grid.objects[Grid.index(grid, cx, cy)].id == "shack", "the shack did not go up over the camp")
  assert(Ledger.get(world, "money") == money, "money changed on placement")
  scene.mode = "act"
  d:frames(2)
  d:shot("shack_up")
  scene.selected = Grid.index(grid, cx, cy)
  d:frames(2)
  d:shot("shack_card")
end
