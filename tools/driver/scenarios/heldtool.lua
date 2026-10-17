-- The tool in the homesteader's hand (#335): the hoe, pail and axe in hand for the jobs that use them, facing
-- the way the work is, and nothing in hand for a job that holds no tool. Jobs are set on the actor directly so
-- each frame shows one tool on open ground (the sim is not stepped between a job and its shot).
local Actors = require("src.sim.systems.actors")
local Grid = require("src.sim.grid")

-- An open tile with a clear 5x5 round it, so nothing stands in front of the figure.
local function openSpot(world)
  local grid = world.state.grid
  local hx, hy = Grid.coords(grid, world.state.land.spawn)
  for r = 4, math.max(grid.w, grid.h) do
    for y = hy - r, hy + r do
      for x = hx - r, hx + r do
        local clear = Grid.inBounds(grid, x - 3, y - 2) and Grid.inBounds(grid, x + 3, y + 2)
        for dy = -2, 2 do
          for dx = -3, 3 do
            if clear then
              local i = Grid.index(grid, x + dx, y + dy)
              clear = Grid.walkable(world, i) and not world.occupancy[i]
            end
          end
        end
        if clear then
          return x, y
        end
      end
    end
  end
  error("no open spot")
end

return function(d)
  d:newGame()
  local world = d:world()
  local hs = Actors.homesteader(world)
  local x, y = openSpot(world)
  hs.x, hs.y, hs.prevX, hs.prevY = x, y, x, y
  local scene = d:scene()
  local cam = scene.camera
  local wx, wy = cam:tileToWorld(x, y)
  cam:centerOn(wx + cam.tileSize / 2, wy + cam.tileSize / 2, d.game.app.view) -- the camera follows the figure to its open spot
  d:frames(1)

  local function work(task, dx)
    local target = Grid.index(world.state.grid, x + dx, y)
    if task == "clear" and not world.state.grid.objects[target] then
      Grid.placeObject(world, "rock", x + dx, y) -- something for the axe to clear
    end
    hs.job = { task = task, target = target, path = {}, progress = 0, ordered = true }
    d:shot(task .. (dx > 0 and "_east" or "_west"))
  end
  work("till", 1)
  work("till", -1)
  work("water_crop", 1)
  work("water_crop", -1)
  work("clear", 1)
  work("clear", -1)
  work("harvest", 1) -- nothing in hand
  hs.job = nil
  d:shot("no_job")
end
