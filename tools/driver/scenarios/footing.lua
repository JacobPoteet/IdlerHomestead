-- Footing (D162, #341): five good nights earn it; the one-time card comes up as a panel in the Tonight card's place
-- (it never blocks input, Tab and Enter reach its Close, a tap outside it reaches the ground), the Tonight card then
-- stays away at dusk, and a slip brings it back as the lead goal. The clock and the stocks are set through the sim (a
-- scenario cannot wait five days); the card, the taps and the keys are the real ones. At desktop and phone sizes.
local Calendar = require("src.sim.systems.calendar")
local Footing = require("src.sim.systems.footing")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Ledger = require("src.sim.systems.ledger")
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

--- The hour the sun sets on `day` (the days of one scenario can cross a season).
local function sunsetOf(world, day)
  local t = world.tuning.time
  return t.daylight[t.seasons[Calendar.seasonOfDay(world, day)]][2]
end

local function stock(world, wood, food)
  world.state.ledger.amounts.wood = wood
  world.state.ledger.amounts.canned_food = food
  world.state.needs.canteen = world.tuning.needs.canteenCapacity
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  local cfg = world.tuning.night.footing

  if Needs.heatEfficiency(world) == 0 then
    local x, y = d:freeTileNear(2, 1)
    Inventory.addObject(world, "campfire")
    assert(Inventory.place(world, "campfire", Grid.index(world.state.grid, x, y)), "a fire to burn wood in")
  end

  -- 1. Good nights, one dusk at a time: Footing is not there until the streak is full.
  local day = 3
  for night = 1, cfg.streakNights do
    stock(world, 200, 30)
    jumpTo(world, day, sunsetOf(world, day) + 0.2)
    d:frames(10)
    dismissFinds(d)
    if night < cfg.streakNights then
      assert(not Footing.held(world), "no Footing before the streak is full")
    end
    day = day + 1
  end
  assert(Footing.held(world), "five good nights earn Footing")
  d:frames(10)
  quiet(d)

  -- 2. The one-time card: a panel in the Tonight card's place; the world stays tappable around it.
  assert(scene.footingCard and scene.tonight.open and scene.tonightRect, "the Footing card is up")
  assert(not Footing.cardDue(world), "and it shows only once")
  d:shot("gained_card")
  local fx, fy = d:freeTileNear(-3, 2)
  scene.selected = nil
  d:clickTile(fx, fy)
  d:frames(2)
  assert(scene.selected, "a tap outside the card reaches the ground")
  assert(scene.tonight.open, "and the card stays up")
  scene.selected = nil

  -- 3. The keyboard: Tab shows the focus ring on Close, Enter presses it.
  d:key("tab")
  d:shot("keyboard_focus")
  d:key("return")
  d:frames(3)
  assert(not scene.tonight.open and not scene.footingCard, "Enter on Close puts the card away")

  -- 4. Held: the next dusk, with the stocks fine, the Tonight card stays away and the stamp is gone.
  stock(world, 200, 30)
  jumpTo(world, day, sunsetOf(world, day) - world.tuning.night.duskLeadHours + 0.3)
  d:frames(30)
  dismissFinds(d)
  quiet(d)
  assert(not scene.tonight.open and not d:hudButton("tonight"), "with Footing held, tonight no longer leads")
  d:shot("held_no_card")

  -- 5. A slip: the food runs out, the dusk check marks it, and the Tonight card is the lead goal again.
  for _, res in ipairs(world.registry:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  day = day + 1 -- the clock ran on in the last step, so today's dusk may already be judged
  jumpTo(world, day, sunsetOf(world, day) + 0.2)
  d:frames(10)
  assert(Footing.slipped(world), "reserves under a day of food slip Footing")
  day = day + 1
  jumpTo(world, day, sunsetOf(world, day) - world.tuning.night.duskLeadHours + 0.3)
  d:frames(30)
  dismissFinds(d)
  quiet(d)
  assert(scene.tonight.open and not scene.footingCard, "the Tonight card is back while Footing is slipped")
  d:shot("slipped_tonight_back")
end
