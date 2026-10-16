-- The homesteader's figure (docs/PLAN_WARDROBE.md): the sprite on every ground it has to read against.
-- Spring grass in the morning, a summer noon, golden hour, a night by the fire, and a snowy winter day,
-- each with a shrub, a rock and a tree beside it for scale. Paused, so the frames are still.
local Actors = require("src.sim.systems.actors")
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")

return function(d)
  d:newGame()
  local world = d:world()
  d:advance(4)
  local function dismissFinds()
    for _ = 1, 3 do
      local top = d.game.app:top()
      if top.select and top.take then
        top:select(1)
        top:take()
      end
      d:frames(2, 0.05)
    end
  end
  dismissFinds()
  local scene, view = d:scene(), d.game.app.view
  local cam = scene.camera
  local grid = world.state.grid
  local tile = world.tuning.display.tileSize
  local dayLength = world.tuning.time.dayLength
  local session = d.game.app.ctx.session
  local hs = Actors.homesteader(world)
  local hx, hy = math.floor(hs.x), math.floor(hs.y)

  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    if world.registry:get("objects", obj.id).clearable ~= false and math.abs(x - hx) <= 6 and math.abs(y - hy) <= 5 then
      Grid.removeObject(world, anchor)
    end
  end
  for _, put in ipairs({ { "brush", -2, 0 }, { "rock", 2, 0 }, { "tree", 4, -1 }, { "campfire", 0, 2 } }) do
    Grid.placeObject(world, put[1], hx + put[2], hy + put[3])
  end
  cam:centerOn((hx + 0.5) * tile, (hy + 0.5) * tile, view)
  cam.zoomIndex = 3
  cam:clamp(view)

  local function at(day, hour, frames)
    world.state.calendar.elapsed = (day - 1) * dayLength
    local now = Calendar.now(world)
    world.state.calendar.elapsed = world.state.calendar.elapsed + ((hour - now.hour) % 24) / 24 * dayLength
    d:frames(frames or 60, 0.05)
  end
  local function settle()
    d:frames(400, 0.05)
    dismissFinds()
  end

  session:setSpeed(1)
  d:tryPress("Start routine")
  session:setSpeed(0)
  at(2, 9, 40)
  settle()
  d:shot("spring_morning")
  at(10, 12, 40)
  settle()
  d:shot("summer_noon")
  at(10, 18, 40)
  settle()
  d:shot("golden_hour")
  at(10, 22, 40)
  settle()
  d:shot("night")
  at(23, 12, 40)
  settle()
  d:shot("winter_day")
end
