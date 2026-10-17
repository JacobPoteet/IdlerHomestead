-- The drinking-water need (D160, #95): the drink chip on the top bar (days of water on hand), its modal in
-- each state (fine, low, thirsty), and the routine filling the canteen. Stock and the clock are set through the
-- sim; the taps are the real ones, so touch and keyboard (Escape) reach the same modal.
local Needs = require("src.sim.systems.needs")

--- Tap the middle of a chip's tap target, if the chip is on the bar.
local function tapChip(d, id)
  local scene = d:scene()
  for _, r in ipairs(scene:chipRects()) do
    if r.id == id then
      d:click(r.x + r.w / 2, r.y + r.h / 2)
      return true
    end
  end
  return false
end

local function show(d, id, name)
  assert(tapChip(d, id), "the " .. id .. " chip is on the bar")
  d:frames(3)
  d:shot(name)
  d:key("escape")
  d:frames(2)
end

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(1)
  d:frames(4)
  assert(d:scene().name == "homestead", "expected the homestead, got " .. d:scene().name)
  d:shot("bar_full")
  show(d, "drink", "modal_ok")

  -- Low: under a day and a half of water on hand.
  world.state.needs.canteen = world.tuning.needs.dailyWater * 1.2
  d:frames(3)
  show(d, "drink", "modal_low")

  -- Thirsty: a dry midnight has passed.
  world.state.needs.canteen = 0
  Needs.drink(world)
  d:frames(3)
  d:shot("bar_thirsty")
  show(d, "drink", "modal_thirsty")

  -- The routine fills the canteen again.
  world.control = "idle"
  d:advance(30)
  d:frames(2)
  assert(Needs.canteen(world) > 0, "the homesteader filled the canteen")
  d:shot("bar_refilled")
end
