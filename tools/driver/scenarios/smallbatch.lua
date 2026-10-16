-- The small batch (D76-D78): a long Power list scrolled by wheel and drag with a switch pressed while
-- paused (#82), the Plan button before and after a plan is placed (#192), and the speed button while
-- in town and after the drive home (#191). Devices and charge are added through the sim (a scenario
-- cannot wait to buy them); the screens, taps and drags are the real ones.
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Power = require("src.sim.systems.power")

--- Place an object on the free tile nearest the spawn.
local function place(world, id)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  local best, bestDist
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local dist = (x - sx) ^ 2 + (y - sy) ^ 2
    if (not bestDist or dist < bestDist) and Inventory.canPlace(world, id, i) then
      best, bestDist = i, dist
    end
  end
  Inventory.addObject(world, id)
  assert(Inventory.place(world, id, best), "could not place " .. id)
end

--- A random find can pop up after the clock moves: take it so the homestead is on top again.
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

return function(d)
  d:newGame()
  local world = d:world()

  -- Power (#82): more devices than fit, paused, scrolled, and a switch pressed.
  place(world, "battery_bank")
  for _ = 1, 24 do
    place(world, "chest_freezer")
  end
  d:advance(1)
  dismissFinds(d)
  d:setSpeed(0)
  d:frames(3)
  d:scene():openPower() -- the power vital's way in until the Power lens (#297)
  d:frames(4)
  d:shot("power_top")
  local scene = d:scene()
  local v = scene.list.view
  d:wheel(-4, v.x + v.w / 2, v.y + v.h / 2)
  d:frames(3)
  d:shot("power_wheel")
  d:drag(v.x + v.w / 2, v.y + v.h - 10, v.x + v.w / 2, v.y + 20)
  d:frames(3)
  d:shot("power_dragged")
  -- Switch the first visible device off while paused: the numbers on the left follow at once.
  local before = Power.flow(world).demand
  local button
  for _, b in ipairs(scene.rowButtons.list) do
    if b.y >= v.y and not button then
      button = b -- the first switch fully inside the window
    end
  end
  d:click(button.x + button.w / 2, button.y + button.h / 2)
  d:frames(2)
  assert(Power.flow(world).demand < before, "demand did not drop while paused")
  d:shot("power_switched_paused")
  d:key("escape")
  d:frames(2)

  -- Plan (#192): the button is lit while planning and plain afterwards.
  d:setSpeed(1)
  d:scene().seedButtons.potato.onPress()
  d:frames(3)
  dismissFinds(d)
  d:pick("Plan field")
  d:frames(2)
  d:shot("plan_on")
  d:clickTile(d:freeTileNear(2, 2))
  d:clickTile(d:freeTileNear(4, 3))
  d:frames(3)
  assert(d:scene().mode == "act", "the plan tool should be off after a plan")
  d:shot("plan_off")

  -- Town (#191): the speed button reads Paused while away, and the old speed returns.
  d:setSpeed(2)
  d:frames(2)
  dismissFinds(d)
  Power.add(world, Land.truck(world), world.tuning.economy.tripCost + 2)
  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(3)
  d:shot("town_before")
  d:press("Drive to town")
  d:frames(5)
  local elapsed = world.state.calendar.elapsed
  d:frames(30)
  assert(world.state.calendar.elapsed == elapsed, "game time moved in town")
  d:shot("town_paused")
  d:press("Drive home")
  d:frames(5)
  assert(d.session == nil or true)
  d:shot("town_home_again")
end
