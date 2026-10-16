-- The Axe's and the Pail's area drags (GDD §9.4, D138, D147, #299): a rectangle dragged over the brush, rocks and
-- trees marks them in graphite hatch; a rectangle over thirsty crops marks them in blue waves. The marks are worked
-- through the task board, cancelled by a drag from a marked tile or from the tile card, and drawn in chalk at night.
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Marks = require("src.sim.systems.marks")

return function(d)
  d:newGame()
  local world = d:world()
  local scene, view = d:scene(), d.game.app.view
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  scene.camera.zoomIndex = 2
  d:setSpeed(0) -- hold game time still, so the shots show the marks and not the work
  local function at(frac)
    local step = frac - Calendar.now(world).timeOfDay
    if step < 0 then
      step = step + 1
    end
    world.state.calendar.elapsed = world.state.calendar.elapsed + step * dayLength
    d:frames(20, 0.05)
  end
  -- The view position of the middle of tile (x, y).
  local function viewOf(x, y)
    local wx, wy = scene.camera:tileToWorld(x, y)
    return scene.camera:worldToView(wx + tile / 2, wy + tile / 2, view)
  end
  local function dragTiles(x1, y1, x2, y2)
    local ax, ay = viewOf(x1, y1)
    local bx, by = viewOf(x2, y2)
    d:drag(ax, ay, bx, by, 8)
  end

  -- Frame the clutter around the homesteader.
  local hx, hy = d:homesteaderTile()
  scene.camera:centerOn((hx + 0.5) * tile, (hy + 0.5) * tile, view)
  d:frames(2, 0.05)
  d:shot("start")

  -- The Axe: a drag marks everything clearable in the rectangle; the pencil hatches it while it is dragged out.
  scene:equip("axe")
  d:frames(2, 0.05)
  local ax, ay = view.w * 0.1, view.h * 0.2 -- corner to corner over the clutter on screen
  local bx, by = view.w * 0.75, view.h * 0.7
  local input, s = d.game.input, view.scale
  input:mousemoved(ax * s, ay * s, 0, 0, false)
  input:mousepressed(ax * s, ay * s, 1, false)
  for n = 1, 8 do
    input:mousemoved((ax + (bx - ax) * n / 16) * s, (ay + (by - ay) * n / 16) * s, 0, 0, false)
  end
  d:frames(2, 0.05)
  d:shot("axe_dragging")
  input:mousemoved(bx * s, by * s, 0, 0, false)
  input:mousereleased(bx * s, by * s, 1, false)
  d:frames(4, 0.05)
  local clearMarks = Marks.count(world, "clear")
  assert(clearMarks > 2, "areadrag: the Axe drag marked " .. clearMarks)
  d:shot("axe_marked")

  -- The tile card of a marked tile: a line saying what was marked and a Cancel mark button.
  scene.selected = Marks.list(world, "clear")[1]
  d:frames(2, 0.05)
  d:shot("axe_card")
  d:press("Cancel mark")
  assert(Marks.count(world, "clear") == clearMarks - 1, "areadrag: the card cancels one mark")
  scene.selected = nil

  -- Dragging again from a marked tile with the Axe cancels the marks it crosses.
  local sx, sy = Grid.coords(grid, Marks.list(world, "clear")[1])
  dragTiles(sx, sy, sx + 2, sy + 2)
  d:shot("axe_cancelled_some")

  -- The hand works the marks through the task board, with the routine off.
  d:setSpeed(1)
  d:advance(1.5)
  d:shot("axe_worked")
  d:setSpeed(0)

  -- The Pail: thirsty crops, marked in waves.
  local px, py = d:freeTileNear(3, 3)
  local planted = 0
  for y = py, py + 2 do
    for x = px, px + 3 do
      if Grid.inBounds(grid, x, y) then
        local i = Grid.index(grid, x, y)
        if not world.occupancy[i] and Grid.terrain(world, i).tillable then
          world.state.fields.tilled[i] = true
          world.state.crops[i] = { id = "radish", growth = 0.1, moisture = 0 }
          planted = planted + 1
        end
      end
    end
  end
  assert(planted > 4, "areadrag: too few crop tiles")
  scene.camera:centerOn((px + 2) * tile, (py + 1.5) * tile, view)
  d:frames(2, 0.05)
  scene:equip("pail")
  dragTiles(px - 1, py - 1, px + 3, py + 2)
  assert(Marks.count(world, "water") > 4, "areadrag: the Pail drag marked crops")
  d:shot("pail_marked")

  -- Night: the same marks again in pale chalk, the hatch and the waves still apart.
  scene:equip("axe")
  dragTiles(px - 3, py - 3, px - 1, py - 1)
  at(0.93)
  d:shot("night_chalk")
end
