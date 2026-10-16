-- The Wardrobe menu (D154, docs/PLAN_WARDROBE_MENU.md §7.2): the Head slot on open, a light torso previewed with
-- its meters, a locked garment's hint and shape, a Wear that waits for dawn, the same menu after dawn passes
-- with it open, a heavy winter outfit on snow, the night lamp pool, the keyboard focus (C, arrows, Enter) and the
-- homesteader in the world wearing what was chosen. Garments are earned through the sim's own grant, never by
-- writing meta; the menu is driven by its buttons and keys like a player.
local Actors = require("src.sim.systems.actors")
local Calendar = require("src.sim.systems.calendar")
local Wardrobe = require("src.sim.systems.wardrobe")

return function(d)
  d:newGame()
  local world = d:world()
  local session = d.game.app.ctx.session
  local dayLength = world.tuning.time.dayLength
  for _, id in ipairs({
    "straw_hat",
    "wool_toque",
    "linen_shirt",
    "wool_sweater",
    "down_parka",
    "wool_trousers",
    "shorts",
    "snow_boots",
    "canvas_shoes",
    "scarf",
  }) do
    Wardrobe.grant(world, id)
  end
  d:frames(4)

  local function at(day, hour, frames)
    world.state.calendar.elapsed = (day - 1) * dayLength
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(frames or 40, 0.05)
  end
  local function dismissFinds()
    for _ = 1, 3 do
      local top = d.game.app:top()
      if top.select and top.take then
        top:select(1)
        top:take()
      end
      d:frames(2, 0.05)
    end
  end
  local function top()
    return d.game.app:top()
  end
  local function opened()
    assert(top().name == "wardrobe", "the Wardrobe is on top, not " .. tostring(top().name))
    return top()
  end

  session:setSpeed(0)
  dismissFinds()
  at(2, 10) -- a day after the first, so a Wear waits for dawn

  d:press("Menu") -- the menu has a Wardrobe row, and Close comes back to the world
  d:press("Wardrobe")
  opened()
  d:key("escape")
  assert(top().name == "homestead", "Esc from the Wardrobe opened from the menu returns to the world")
  d:key("c")
  local scene = opened()
  assert(scene.slot == "head", "opens on the Head slot")
  d:shot("open_head")

  d:press("Torso")
  d:press("Linen shirt")
  assert(scene.state:draft().torso == "linen_shirt", "tapping a tile previews it")
  assert(Wardrobe.committed(world).torso == "flannel_shirt", "nothing is chosen yet")
  d:shot("torso_preview_light")

  d:press("??? Denim jacket")
  assert(scene.lockedDef and scene.lockedDef.id == "denim_jacket", "a locked tile shows its hint")
  assert(scene.state:draft().torso == "linen_shirt", "and leaves the draft as it was")
  d:shot("locked_hint")

  d:press("Linen shirt")
  d:press("Wear")
  assert(Wardrobe.committed(world).torso == "linen_shirt", "Wear chooses the draft")
  assert(Wardrobe.dressed(world).torso == "flannel_shirt", "but today's clothes wait for dawn")
  d:shot("worn_dawn")

  -- Dawn passes with the menu open: Today moves to the new shirt.
  session:setSpeed(1)
  at(2, 23.95, 2)
  d:frames(240, 0.05)
  assert(Wardrobe.dressed(world).torso == "linen_shirt", "dawn put the shirt on")
  assert(top() == scene, "the Wardrobe stayed open through the dawn")
  d:shot("after_dawn")
  session:setSpeed(0)
  d:key("escape")
  assert(top().name == "homestead", "Esc closes the Wardrobe")

  -- A winter day on snow, a heavy outfit in the draft.
  at(23, 12, 40)
  session:setSpeed(1)
  d:tryPress("Start routine")
  d:frames(400, 0.05)
  dismissFinds()
  session:setSpeed(0)
  d:key("c")
  opened()
  d:press("Head")
  d:press("Wool toque")
  d:press("Torso")
  d:press("Down parka")
  d:press("Legs")
  d:press("Wool trousers")
  d:press("Feet")
  d:press("Snow boots")
  d:press("Extra")
  d:press("Scarf")
  d:shot("winter_heavy")
  d:key("escape")

  -- Night: the lamp pool round the paper.
  at(23, 22, 80)
  d:key("c")
  scene = opened()
  assert(scene.state:changed(), "the heavy draft was kept for the session")
  d:shot("night")
  d:key("escape")

  -- The keyboard: C, arrows, Enter.
  at(23, 12, 40)
  d:key("c")
  opened()
  d:key("up")
  d:key("left")
  d:key("down")
  d:key("right")
  d:shot("keyboard_focus")
  d:key("return")
  d:key("c")
  assert(top().name == "homestead", "C closes it again")

  -- Dawn, then the world: the homesteader wears what was chosen.
  session:setSpeed(1)
  at(23, 23.95, 2)
  d:frames(240, 0.05)
  at(24, 12, 40)
  d:tryPress("Start routine")
  d:frames(400, 0.05)
  dismissFinds()
  session:setSpeed(0)
  local scenery = d:scene()
  local hs = Actors.homesteader(world)
  local tile = world.tuning.display.tileSize
  scenery.camera:centerOn((hs.x + 0.5) * tile, (hs.y + 0.5) * tile, d.game.app.view)
  scenery.camera.zoomIndex = 3
  scenery.camera:clamp(d.game.app.view)
  d:frames(4, 0.05)
  d:shot("world_figure")
end
