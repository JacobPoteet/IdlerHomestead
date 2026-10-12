-- The idle routine's starter field (GDD D61, #66): handing over with nothing planned makes the
-- routine plan a small field near the truck, then till, plant and water it unattended.
local Grid = require("src.sim.grid")

--- Centre the camera on the middle of the planned tiles.
local function centreOnPlan(d)
  local world, scene = d:world(), d:scene()
  local grid = world.state.grid
  local sx, sy, n = 0, 0, 0
  for i in pairs(world.state.fields.plan) do
    local x, y = Grid.coords(grid, i)
    sx, sy, n = sx + x, sy + y, n + 1
  end
  assert(n > 0, "the routine planned nothing")
  local cx, cy = scene.camera:tileToWorld(sx / n, sy / n)
  scene.camera:centerOn(cx, cy, d.game.app.view)
  d:frames(2)
end

return function(d)
  d:newGame()
  local world = d:world()
  assert(next(world.state.fields.plan) == nil, "a new run starts with nothing planned")
  d:advance(0.1)
  d:press("Start routine")
  d:frames(3)
  centreOnPlan(d)
  d:shot("planned")
  d:advance(2)
  centreOnPlan(d)
  d:shot("working")
  d:advance(6)
  centreOnPlan(d)
  d:shot("planted")
end
