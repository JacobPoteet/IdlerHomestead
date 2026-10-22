-- The goal ladder (D163, #342, #276): the pressing-goal line under the top bar (its own tappable line, no chip) and the
-- Progress panel it opens: Tonight first, then Footing's checklist, then the winter and the Great Winter; the run's
-- milestones ticking; the gates locked ("opens at Footing") and then open; the "Limiting you" line naming water once
-- the beds are dry (D202, #377). Tap and keyboard (P, Esc). The clock and the stocks are set through the sim; the line,
-- the taps and the keys are the real ones. At desktop and phone sizes.
local Bottleneck = require("src.sim.systems.bottleneck")
local Crops = require("src.sim.systems.crops")
local Footing = require("src.sim.systems.footing")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Needs = require("src.sim.systems.needs")
local Weather = require("src.sim.systems.weather")

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

local function stock(world, wood, food)
  world.state.ledger.amounts.wood = wood
  world.state.ledger.amounts.canned_food = food
  world.state.needs.canteen = world.tuning.needs.canteenCapacity
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()

  if Needs.heatEfficiency(world) == 0 then
    local x, y = d:freeTileNear(2, 1)
    Inventory.addObject(world, "campfire")
    assert(Inventory.place(world, "campfire", Grid.index(world.state.grid, x, y)), "a fire to burn wood in")
  end

  -- 1. The line: a plate of its own under the top bar, not a chip, and no taller than a touch target.
  d:frames(30)
  quiet(d)
  local goal = d:hudButton("goal")
  assert(goal, "the goal line is up")
  assert(goal.y >= scene.hud.topH, "under the top plates")
  assert(goal.h >= world.tuning.input.minTouchTarget, "a touch-sized line")
  assert(goal.x + goal.w <= scene.app.view.w, "inside the view")
  d:shot("line_start")

  -- 2. Tonight leads while something is short.
  stock(world, 2, 1)
  world.state.needs.canteen = 0
  d:frames(40)
  quiet(d)
  assert(scene.goal.kind == "tonight", "short on wood, food and water: Tonight leads")
  assert(scene.hud.goal.w > 0)
  d:shot("line_tonight")

  -- 3. A tap on the line opens the Progress panel; Close puts it away.
  d:pressHud("goal")
  d:frames(4)
  assert(d:scene().name == "progress", "the line opens the Progress panel")
  d:shot("panel_tonight")
  local panel = d:scene()
  panel.list.offset = panel.list.contentH -- the bottom of the list: milestones and the gates
  d:frames(3)
  d:shot("panel_gates")
  d:press("Close")
  d:frames(3)
  assert(d:scene().name == "homestead", "Close returns to the homestead")

  -- 4. The keyboard: P opens it, P (or Esc) closes it.
  d:key("p")
  d:frames(3)
  assert(d:scene().name == "progress", "P opens the panel")
  d:key("p")
  d:frames(3)
  assert(d:scene().name == "homestead", "P closes it again")
  d:key("p")
  d:frames(3)
  d:key("escape")
  d:frames(3)
  assert(d:scene().name == "homestead", "Esc closes it")

  -- 5. Everything in stock: the Footing checklist leads, with the nights in a row.
  stock(world, 200, 30)
  world.state.footing.streak = 2
  d:frames(40)
  quiet(d)
  assert(scene.goal.kind == "footing", "nothing short: Footing is the goal")
  d:shot("line_footing")
  d:pressHud("goal")
  d:frames(4)
  d:shot("panel_footing")
  d:key("escape")
  d:frames(3)

  -- 6. Footing held: the winter leads, with the days to it and the reserve target; milestones tick.
  jumpTo(world, 3, 12)
  world.state.footing.held, world.state.footing.gainedDay, world.state.footing.streak = true, 12, 0
  world.events:emit("footing.gained", { day = 12 })
  world.events:emit("crop.harvested", { crop = "radish", amount = 1 })
  world.events:emit("market.sold", { earnings = 5 })
  d:frames(40)
  dismissFinds(d)
  quiet(d)
  assert(scene.goal.kind == "winter", "with Footing held, the winter is the goal")
  d:shot("line_winter")
  d:pressHud("goal")
  d:frames(4)
  d:shot("panel_winter")
  panel = d:scene()
  panel.list.offset = panel.list.contentH
  d:frames(3)
  d:shot("panel_winter_gates")
  d:key("escape")
  d:frames(3)

  -- 6b. What is limiting the homestead (D202, #377): a bed of dry radishes, under a clear sky, names water, with the
  -- figures and what helps, second on the panel under the goal.
  Weather.force(world, "clear")
  local radish = world.registry:get("crops", "radish")
  for dx = 2, 6 do
    local x, y = d:freeTileNear(dx, 2)
    local i = Grid.index(world.state.grid, x, y)
    world.state.fields.tilled[i] = true
    local crop = Crops.newCrop(world, radish)
    crop.moisture, crop.growth = 0, 0.3
    world.state.crops[i] = crop
  end
  assert(Bottleneck.current(world).id == "water", "dry beds: water is the limit")
  d:pressHud("goal")
  d:frames(4)
  d:shot("panel_limit")
  d:key("escape")
  d:frames(3)

  -- 7. A slip: Tonight is back as the lead goal and says so.
  stock(world, 0, 0)
  world.state.footing.slipped = true
  d:frames(40)
  quiet(d)
  assert(Footing.slipped(world) and scene.goal.kind == "tonight", "slipped: Tonight leads again")
  d:shot("line_slipped")
end
