-- The Wardrobe's presets and Auto (D156, docs/PLAN_WARDROBE_MENU.md §7.2): the Warm and Cold chips empty, a cold
-- outfit built and saved with Save then a chip, an outfit loaded whole from a chip, Auto switched on, and a
-- winter dawn on which Auto dresses the Cold preset and says so in a toast. Garments are earned through the
-- sim's own grant, never by writing meta; the menu is driven by its buttons like a player.
local Calendar = require("src.sim.systems.calendar")
local Wardrobe = require("src.sim.systems.wardrobe")

return function(d)
  d:newGame()
  local world = d:world()
  local session = d.game.app.ctx.session
  local dayLength = world.tuning.time.dayLength
  world.debugInvincible = true
  for _, id in ipairs({
    "straw_hat",
    "wool_toque",
    "linen_shirt",
    "wool_sweater",
    "wool_trousers",
    "shorts",
    "snow_boots",
    "canvas_shoes",
    "scarf",
    "bandana",
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
      local t = d.game.app:top()
      if t.select and t.take then
        t:select(1)
        t:take()
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
  local function wearSet(list)
    for _, step in ipairs(list) do
      d:press(step)
    end
  end

  session:setSpeed(0)
  dismissFinds()
  at(2, 10)

  -- Both chips start empty, Auto off.
  d:key("c")
  local scene = opened()
  assert(Wardrobe.preset(world, "warm") == nil and Wardrobe.preset(world, "cold") == nil, "no preset yet")
  assert(not Wardrobe.autoOn(world), "Auto starts off")
  d:press("Warm")
  assert(scene.note == scene.cfg.presetEmptyHint, "an empty chip says so")
  assert(not scene.state:changed(), "and loads nothing")
  d:shot("empty")

  -- A cold outfit, saved with Save then the Cold chip.
  wearSet({
    "Head",
    "Wool toque",
    "Torso",
    "Wool sweater",
    "Legs",
    "Wool trousers",
    "Feet",
    "Snow boots",
    "Extra",
    "Scarf",
  })
  d:press("Save")
  assert(scene.saving, "Save waits for a chip")
  d:press("Cold")
  assert(not scene.saving, "the chip took it")
  local cold = Wardrobe.preset(world, "cold")
  assert(cold and cold.torso == "wool_sweater" and cold.extra == "scarf", "the Cold preset holds the outfit")
  assert(Wardrobe.committed(world).torso == "flannel_shirt", "saving a preset chooses nothing")
  d:shot("saved_cold")

  -- A warm outfit into the Warm chip.
  d:press("Reset")
  wearSet({ "Head", "Straw hat", "Torso", "Linen shirt", "Legs", "Shorts", "Feet", "Canvas shoes", "Extra", "Bandana" })
  d:press("Save")
  d:press("Warm")
  assert(Wardrobe.preset(world, "warm").legs == "shorts", "the Warm preset holds the outfit")

  -- Loading: all five slots at once into the draft; Wear then chooses it.
  d:press("Reset")
  d:press("Cold")
  assert(scene.state:draft().head == "wool_toque" and scene.state:draft().feet == "snow_boots", "a whole outfit loads")
  assert(Wardrobe.committed(world).head == "bare_head", "a load only previews")
  d:shot("load_cold")

  -- Auto on, then a winter dawn: the Cold preset is dressed and a toast says so.
  d:press("Reset")
  d:press("Auto")
  assert(Wardrobe.autoOn(world), "Auto is on")
  d:key("escape")
  assert(top().name == "homestead")
  session:setSpeed(1)
  at(22, 23.95, 2)
  local seen = false
  for _ = 1, 80 do -- the toast waits behind the morning's others: step until it shows
    d:frames(5, 0.05)
    dismissFinds()
    local t = d:scene().toast
    if t and t.text:find("Auto") then
      seen = true
      break
    end
  end
  assert(Wardrobe.dressed(world).torso == "wool_sweater", "Auto dressed the Cold preset at dawn")
  assert(Wardrobe.autoOn(world), "Auto stays on after a dawn")
  assert(seen, "the toast says Auto dressed")
  d:tryPress("Got it") -- the morning report card goes; the toast stays a moment
  d:frames(2, 0.05)
  assert(d:scene().toast, "the toast outlasts the card")
  d:shot("auto_toast")
  session:setSpeed(0)

  -- Opened again: the Cold chip shows as the outfit on show, Auto lit; a manual Wear turns Auto off.
  d:key("c")
  scene = opened()
  assert(not scene.state:changed(), "the menu follows the Auto outfit")
  d:shot("auto_on")
  d:press("Head")
  d:press("Bare head")
  d:press("Wear")
  assert(not Wardrobe.autoOn(world), "a manual Wear turned Auto off")
  d:shot("auto_off")
  d:key("escape")
end
