-- Scrollable panels (D87, #8, #184): the toolbar palette with many seeds (extra crops are cloned into the
-- scenario's registry, a content stand-in the real game will have), scrolled by wheel and drag; the
-- Catalog and Fish guide shrunk to a short window so they clip and scroll; the town menu (shop and
-- load lists) in the same short window. Taps, drags and wheel turns are the real ones.
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")

local function dismissFinds(d)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1]
      d:click(first.x + first.w / 2, first.y + first.h / 2)
      d:press("Take it")
      d:frames(3)
    end
  end
end

--- Clone the first crop into `n` more crops so the seed palette has something to scroll.
local function addSeeds(world, n)
  local list = world.registry.kinds.crops.list
  local first = list[1]
  for i = 1, n do
    local copy = {}
    for k, v in pairs(first) do
      copy[k] = v
    end
    copy.id = "extra" .. i
    list[#list + 1] = copy
    world.registry.kinds.crops.byId[copy.id] = copy
  end
end

--- Resize the real window to a short one (the sprites survive, #222); `restore` puts it back.
local function shorten(d, h)
  local w = love.graphics.getWidth()
  d:resize(w, h or 230)
  d:frames(3)
end

local function restore(d, w, h)
  d:resize(w, h)
  d:frames(3)
end

return function(d)
  d:newGame()
  dismissFinds(d)
  local world = d:world()
  local winW, winH = love.graphics.getDimensions()
  addSeeds(world, 40)
  d:frames(3)
  d:scene():layout()

  -- The tools tray with many seeds (the Hoe ring's More, D138): capped, scrollbar thumb, wheel and drag.
  d:scene():equip("hoe", { kind = "more" })
  do
    d:frames(3)
    d:shot("palette_seeds")
    local r = d:scene().paletteRect
    -- Wide views fit many seeds in the capped rows; narrow ones scroll.
    if r.scrolls then
      d:wheel(-2, r.x + r.w / 2, r.y + r.h / 2)
      d:frames(3)
      assert(d:scene().paletteList.offset > 0, "the wheel scrolls the palette")
      d:shot("palette_seeds_wheel")
      d:drag(r.x + r.w / 2, r.y + r.h - 10, r.x + r.w / 2, r.y + 10)
      d:frames(3)
      d:shot("palette_seeds_drag")
    end
    d:key("escape")
    d:frames(2)
  end

  -- Catalog and Fish guide in a short window.
  d:pick("Catalog")
  d:frames(3)
  d:shot("catalog_full")
  d:key("escape")
  d:frames(2)
  d:pick("Catalog")
  shorten(d, 150)
  d:shot("catalog_short")
  d:wheel(-3, d.game.app.view.w / 2, 110)
  d:frames(3)
  d:shot("catalog_short_scrolled")
  d:key("escape")
  restore(d, winW, winH)
  d:pick("Fish guide")
  shorten(d)
  d:shot("guide_short")
  d:wheel(-3, d.game.app.view.w / 2, 110)
  d:frames(3)
  d:shot("guide_short_scrolled")
  d:key("escape")
  restore(d, winW, winH)

  -- The town menu in the same window: the shop and the load list each clip and scroll.
  Power.add(world, Land.truck(world), world.tuning.economy.tripCost + 2)
  d:frames(3)
  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(3)
  d:press("Drive to town")
  d:frames(5)
  shorten(d, 220)
  d:shot("town_short")
  d:wheel(-3, d:scene().box.x + d:scene().box.w - 60, d:scene().box.y + 100)
  d:frames(3)
  d:shot("town_short_scrolled")
  d:press("Drive home")
  d:frames(3)
  restore(d, winW, winH)
end
