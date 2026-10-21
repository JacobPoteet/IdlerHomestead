-- Soil fertility and its lens (D178, #364): the Plan field tool shows the Soil lens, the ground painted by fertility
-- with the card reading out what the pointer or the rectangle would yield for the seed in hand; the first tap of the
-- two-tap plan keeps the rectangle's readout; finishing the plan puts the lens away; the tile card names the
-- fertility. Fertility is set through the sim (a scenario cannot wait for harvests); the taps are the real ones.
local Grid = require("src.sim.grid")

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

--- The farmable free tile nearest the homesteader's tile offset by (dx, dy); returns x, y (freeTileNear may land on a road).
local function tillableNear(d, dx, dy)
  local world = d:world()
  local grid = world.state.grid
  local hx, hy = d:homesteaderTile()
  local best, bx, by
  for y = 1, grid.h do
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      if Grid.terrain(world, i).tillable and not world.occupancy[i] then
        local dist = (x - hx - dx) ^ 2 + (y - hy - dy) ^ 2
        if not best or dist < best then
          best, bx, by = dist, x, y
        end
      end
    end
  end
  return bx, by
end

local function hasLine(lines, text)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then
      return true
    end
  end
  return false
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  d:advance(0.1)
  dismissFinds(d)
  d:setSpeed(0)
  d:frames(3)
  assert(scene.lens:active() == nil, "no lens at rest")

  -- Worn ground on one side of the start, rich on the other, so the lens has something to say.
  local grid = world.state.grid
  local fx, fy = tillableNear(d, 0, 0)
  for y = fy - 7, fy + 7 do
    for x = fx - 9, fx + 9 do
      if Grid.inBounds(grid, x, y) then
        local i = Grid.index(grid, x, y)
        grid.fertility[i] = x < fx and 0.15 or 0.95
      end
    end
  end

  scene.seedButtons.radish.onPress()
  d:frames(3)
  d:pick("Plan field")
  d:frames(8)
  assert(scene.lens:active() == "soil", "the Plan field tool shows the Soil lens")
  d:shot("plan_lens")

  -- The pointer over a tile: the card reads out that tile.
  local ax, ay = tillableNear(d, -3, 0)
  local bx, by = tillableNear(d, 3, 2)
  scene.hover = Grid.index(grid, ax, ay)
  d:frames(8)
  assert(scene.lensCard.focus and #scene.lensCard.focus.tiles == 1, "one tile under the pointer")
  d:shot("plan_tile")

  -- The first corner tapped: the readout follows the rectangle to the pointer, worn half and rich half together.
  d:clickTile(ax, ay)
  scene.hover = Grid.index(grid, bx, by)
  d:frames(8)
  assert(scene.lensCard.focus.rect and #scene.lensCard.focus.tiles > 1, "the rectangle is read out")
  d:shot("plan_rect")

  -- The second corner plans it and the lens goes with the tool.
  d:clickTile(bx, by)
  d:frames(10)
  assert(scene.mode == "act", "one plan per selection")
  assert(scene.lens:active() == nil, "the lens goes when the Plan tool does")
  assert(next(world.state.fields.plan) ~= nil, "the rectangle is planned")

  -- The tile card names the fertility.
  local i = Grid.index(grid, ax, ay)
  grid.fertility[i] = 0.2
  assert(hasLine(scene:tileInfo(i), "Fertility 20% (poor)"), "a poor tile says so")
  grid.fertility[i] = 0.9
  assert(hasLine(scene:tileInfo(i), "Fertility 90% (rich)"), "a rich tile says so")

  -- The field is bright, the wild ground faint: the lens over a planned plot.
  scene.seedButtons.radish.onPress()
  d:frames(2)
  d:pick("Plan field")
  d:frames(8)
  d:shot("plan_field")
  scene.lens:dismiss()
  d:frames(4)
  assert(scene.lens:active() == nil, "Close puts the lens away while the Plan tool is on")
  d:shot("closed")

  -- Rotation (D179, #365): a tile that has grown the same family again and again names its pest pressure, and a
  -- blighted crop says to pull it. The state is set through the sim (a scenario cannot wait for harvests).
  local pi = Grid.index(grid, ax, ay)
  world.state.fields.tilled[pi] = true
  world.state.crops[pi] = { id = "radish", growth = 0.4, moisture = 1 }
  world.state.soil.family[pi] = "brassicas"
  world.state.soil.pressure[pi] = 0.3
  assert(hasLine(scene:tileInfo(pi), "Pest pressure 30%"), "a pressured tile names it")
  assert(not hasLine(scene:tileInfo(pi), "(high)"), "30% is not yet high")
  world.state.soil.pressure[pi] = 0.75
  assert(hasLine(scene:tileInfo(pi), "Pest pressure 75% (high): rotate the crop"), "a high one says to rotate")
  world.state.threats.blight[pi] = 0
  assert(hasLine(scene:tileInfo(pi), "Blight: pull it before it spreads"), "a blighted crop says to pull it")
  scene.selected = pi
  d:frames(12)
  d:shot("pressure_card")
  world.state.crops[pi] = nil
  assert(not hasLine(scene:tileInfo(pi), "Blight"), "no crop, no blight line")
  scene.selected = nil
  d:frames(6)
end
