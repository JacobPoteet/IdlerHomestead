-- The Power and Water lenses (D141, D145, #297): the blueprint wash with sources, sinks and connections
-- (Power) and the water table, coverage and cistern (Water); each switch-on route (the vital, the Pail, a
-- placement), the vital again and the card's Close putting a lens away, and a priority moved on the card.
-- Objects are added through the sim; the taps and keys are the real ones.
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

local function tapChip(d, id)
  for _, r in ipairs(d:scene():chipRects()) do
    if r.id == id then
      d:click(r.x + r.w / 2, r.y + r.h / 2)
      return
    end
  end
  error("no chip " .. id)
end

local function dismissFinds(d)
  for _ = 1, 3 do
    if d:scene().name == "finds" then
      local first = d:scene().buttons.list[1]
      d:click(first.x + first.w / 2, first.y + first.h / 2)
      d:frames(2)
    end
  end
end

return function(d)
  d:newGame()
  local world = d:world()
  d:frames(10)
  place(world, "solar_array")
  place(world, "folding_panel")
  place(world, "battery_bank")
  place(world, "chest_freezer")
  place(world, "electric_heater")
  place(world, "cistern")
  place(world, "drip_line")
  place(world, "sprinkler")
  d:advance(1)
  dismissFinds(d)
  d:setSpeed(0)
  d:frames(3)
  local scene = d:scene()
  d:shot("world")
  assert(scene.lens:active() == nil, "no lens at rest")

  -- From the vital: the battery card's shortcut shows Power; the vital again puts it away.
  tapChip(d, "battery")
  d:frames(3)
  d:press("Show power")
  d:frames(4)
  assert(scene.lens:active() == "power", "the vital's shortcut shows the Power lens")
  d:shot("power")
  tapChip(d, "battery")
  d:frames(3)
  assert(scene.lens:active() == nil, "the vital again puts the lens away")
  assert(d:scene() == scene, "and does not open its card")

  -- A priority moved on the card (the Power panel's job), then Close.
  scene:showLens("power")
  d:frames(4)
  local before = Power.order(world)[1]
  local down
  for _, b in ipairs(scene.lensCard.rowButtons.list) do
    if b.label == "v" and b.enabled and not down then
      down = b
    end
  end
  assert(down, "a priority row has a move-down button")
  assert(down.w >= scene.app.ctx.tuning.input.minTouchTarget / 2, "and it is finger-sized")
  d:click(down.x + down.w / 2, down.y + down.h / 2)
  d:frames(3)
  assert(Power.order(world)[1] ~= before, "the first priority moved down")
  d:shot("power_priority")
  d:pick("Close")
  d:frames(3)
  assert(scene.lens:active() == nil, "Close puts the lens away")

  -- From the tool: the Pail shows Water, another tool takes it away.
  d:key("3")
  d:frames(4)
  assert(scene.lens:active() == "water", "the Pail shows the Water lens")
  d:shot("water_pail")
  d:key("1")
  d:frames(3)
  assert(scene.lens:active() == nil, "putting the Pail away ends the lens")

  -- Closing a lens that came with the Pail keeps it closed while the Pail is in hand.
  d:key("3")
  d:frames(3)
  d:pick("Close")
  d:frames(3)
  assert(scene.lens:active() == nil, "Close holds while the Pail is in hand")
  d:key("1")
  d:frames(2)

  -- From a placement: a panel shows Power, a pump shows Water, with the ground it can go on.
  Inventory.addObject(world, "folding_panel")
  scene:startPlacing("folding_panel")
  d:frames(4)
  assert(scene.lens:active() == "power", "placing a panel shows the Power lens")
  d:shot("place_panel")
  scene:setHand(nil, nil)
  d:frames(3)
  assert(scene.lens:active() == nil, "the lens ends with the placement")
  Inventory.addObject(world, "well")
  scene:startPlacing("well")
  d:frames(4)
  assert(scene.lens:active() == "water", "placing a well shows the Water lens")
  d:shot("place_well")
  scene:setHand(nil, nil)
  Inventory.addObject(world, "drip_line")
  scene:startPlacing("drip_line")
  d:frames(2)
  local x, y = d:freeTileNear(3, 3)
  scene.hover = Grid.index(world.state.grid, x, y)
  d:frames(4)
  d:shot("place_drip")
  scene:setHand(nil, nil)
  d:frames(2)

  -- A tap on a powered device shows Power too.
  local tx, ty = d:nearestObject("battery_bank")
  d:clickTile(tx, ty)
  d:frames(4)
  assert(scene.lens:active() == "power", "tapping a battery shows the Power lens")
  d:shot("tap_battery")
  scene.lens:dismiss()
  d:frames(2)

  -- Night: the painted layer dims with the light.
  d:setSpeed(1)
  d:advance(10)
  dismissFinds(d)
  d:setSpeed(0)
  scene:showLens("water")
  d:frames(4)
  d:shot("water_night")
end
