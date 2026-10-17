-- The limit on wood from trees (issue #362): in autumn the winter readiness card says trees will give only so much once
-- it freezes; in winter the Tonight card says how much the trees can still give, and when the allowance is used up a tap
-- on a tree is refused with a toast while brush still clears. The clock and the tally are set through the sim; the cards,
-- the toast and the tap are the real ones. At desktop and phone sizes.
local Felling = require("src.sim.systems.felling")
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

  -- 1. Late autumn: the readiness card warns that trees will give only so much once it freezes.
  jumpTo(world, 2 * DPS + 5, 10)
  world.state.ledger.amounts.wood = 10
  d:frames(30)
  dismissFinds(d)
  quiet(d)
  scene:openReadiness()
  d:frames(3)
  assert(d:scene().name == "notice", "the readiness card is up")
  d:shot("autumn_readiness")
  d:press("Got it")
  d:frames(3)

  -- 2. A winter dusk with the allowance untouched: the Tonight card's warmth row says how much the trees can give.
  local day = 3 * DPS + 3
  local sunset = world.tuning.time.daylight.winter[2]
  jumpTo(world, day, sunset - lead + 0.3)
  world.state.ledger.amounts.wood = 3
  d:frames(40)
  dismissFinds(d)
  quiet(d)
  assert(scene.tonight.open and scene.tonightRect, "the Tonight card opens by itself at dusk")
  assert(Felling.outlook(world).left == Felling.outlook(world).allowance, "nothing felled yet")
  d:shot("tonight_allowance_left")

  -- 3. Use the allowance up (as if the axe had been busy): the card changes, and the Chop fix offers no trees.
  Felling.record(world, { kind = "tree" }, Felling.outlook(world).allowance)
  Marks.clearAll(world)
  d:frames(40)
  quiet(d)
  assert(Felling.outlook(world).left == 0, "the allowance is used up")
  d:shot("tonight_allowance_used")

  -- 4. A tap on a tree is refused with the reason; the homesteader takes no order.
  d:key("escape")
  local tx, ty = d:nearestObject({ tree = true, pine = true, birch = true })
  assert(tx, "a tree to tap")
  d:clickTile(tx, ty)
  d:frames(4)
  assert(scene.toast and scene.toast.text:find("No more wood from trees", 1, true), "the tap says why it was refused")
  d:shot("tap_tree_refused")
  quiet(d)

  -- 5. Brush still clears.
  local bx, by = d:nearestObject("brush")
  if bx then
    d:clickTile(bx, by)
    d:frames(4)
    assert(not (scene.toast and scene.toast.text:find("No more wood", 1, true)), "brush is not limited")
  end
end
