-- The dusk check (D161, #340): the Tonight card opens by itself a few hours before sunset with what the night
-- needs and what the homestead has, a fix button per gap, Close and the stamp to bring it back, the T key, and the
-- keyboard path (Tab, Enter, Esc). The clock and the stocks are set through the sim (a scenario cannot wait for a
-- season); the card, the taps and the keys are the real ones. At desktop and phone sizes.
local Actors = require("src.sim.systems.actors")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Marks = require("src.sim.systems.marks")
local Needs = require("src.sim.systems.needs")

--- Jump the sim clock to a day and hour (the calendar's day marker with it, so no day is announced).
local function jumpTo(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- A random find can pop up after a long jump of the clock: take it so the homestead is on top again.
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

local function quiet(d)
  local scene = d:scene()
  scene.toast, scene.toastQueue = nil, {}
end

--- The fix button whose label starts with `prefix`, or nil.
local function fixButton(scene, prefix)
  for _, b in ipairs(scene.tonightCard.rowButtons.list) do
    if b.label:sub(1, #prefix) == prefix then
      return b
    end
  end
  return nil
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local DPS = world.tuning.time.daysPerSeason
  local lead = world.tuning.night.duskLeadHours

  if Needs.heatEfficiency(world) == 0 then
    local x, y = d:freeTileNear(2, 1)
    Inventory.addObject(world, "campfire")
    assert(Inventory.place(world, "campfire", Grid.index(world.state.grid, x, y)), "a fire to burn wood in")
  end

  -- 1. A winter afternoon, short of wood, food and water: the card is not up yet, the stamp is.
  local day = 3 * DPS + 3
  local sunset = world.tuning.time.daylight.winter[2]
  jumpTo(world, day, sunset - lead - 2)
  world.state.ledger.amounts.wood = 3
  world.state.ledger.amounts.canned_food = 1
  world.state.needs.canteen = 1
  d:frames(30)
  dismissFinds(d)
  quiet(d)
  assert(not scene.tonight.open, "by day the card is closed")
  assert(d:hudButton("tonight"), "the Tonight stamp is up while something is short")
  d:shot("afternoon_stamp")

  -- 2. Dusk: the card opens by itself.
  jumpTo(world, day, sunset - lead + 0.3)
  d:frames(30)
  dismissFinds(d)
  quiet(d)
  assert(scene.tonight.open and scene.tonightRect, "the card opens by itself at dusk")
  assert(not d:hudButton("tonight"), "the stamp steps aside while the card is up")
  d:shot("card_open")

  -- 3. It never blocks input: a tap on the ground outside the card selects the tile as ever.
  local fx, fy = d:freeTileNear(-3, 2)
  scene.selected = nil
  d:clickTile(fx, fy)
  d:frames(2)
  assert(scene.selected, "a tap outside the card reaches the ground")
  assert(scene.tonight.open, "and the card stays up")
  scene.selected = nil
  d:frames(2)

  -- 4. Chop: the nearest trees are marked as Axe orders.
  local chop = fixButton(scene, "Chop")
  assert(chop, "wood is short, so the card offers to chop")
  d:click(chop.x + chop.w / 2, chop.y + chop.h / 2)
  d:frames(4)
  assert(Marks.count(world, "clear") > 0, "the trees are marked")
  d:shot("after_chop")
  quiet(d)

  -- 5. Fill the canteen: the homesteader is ordered to the creek like a tap on it.
  local fill = fixButton(scene, "Fill the canteen")
  assert(fill, "the water is low, so the card offers to fill the canteen")
  d:click(fill.x + fill.w / 2, fill.y + fill.h / 2)
  d:frames(4)
  local hs = Actors.homesteader(world)
  assert(hs.order or hs.job, "the homesteader has an order")
  d:shot("after_fill")
  quiet(d)

  -- 6. The keyboard: Tab shows the focus ring, Enter presses the focused fix.
  d:key("tab")
  d:shot("keyboard_focus")
  d:key("return")
  quiet(d)

  -- 7. Close, then the stamp brings it back, Esc puts it away without opening the menu.
  d:press("Close")
  d:frames(3)
  assert(not scene.tonight.open, "Close puts the card away")
  jumpTo(world, day, sunset - lead + 0.6)
  d:frames(30)
  assert(not scene.tonight.open, "a card closed at dusk stays closed that day")
  assert(d:hudButton("tonight"), "the stamp offers it back")
  d:shot("closed_stamp")
  d:pressHud("tonight")
  d:frames(3)
  assert(scene.tonight.open, "the stamp brings it back")
  d:key("escape")
  assert(not scene.tonight.open and d:scene().name == "homestead", "Esc closes the card before the menu")
  d:key("t")
  assert(scene.tonight.open, "T opens it at any hour")
  d:key("t")
  assert(not scene.tonight.open, "and closes it again")

  -- 8. Everything in stock: the card says the night is ready and offers no fix.
  world.state.ledger.amounts.wood = 200
  world.state.ledger.amounts.canned_food = 30
  world.state.needs.canteen = world.tuning.needs.canteenCapacity
  Marks.clearAll(world)
  d:key("t")
  d:frames(40)
  assert(#scene.tonightCard.rowButtons.list == 0, "no gap, no fix button")
  d:shot("all_ready")
end
