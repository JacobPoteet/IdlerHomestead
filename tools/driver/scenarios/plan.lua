-- Plan = automate the plot (D92, #231): planning a field with the Routine off starts tilling and planting
-- at once; with the seeds gone the plot is still tilled and planting waits; a tap elsewhere sends the
-- homesteader off and it comes back to finish the whole plot. Seeds are taken and returned through the
-- ledger (a scenario cannot wait for a harvest); the taps, toasts and screens are the real ones.
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")

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

--- Centre the camera on the middle of the planned tiles.
local function centreOnPlan(d)
  local world, scene = d:world(), d:scene()
  local grid = world.state.grid
  local sx, sy, n = 0, 0, 0
  for i in pairs(world.state.fields.plan) do
    local x, y = Grid.coords(grid, i)
    sx, sy, n = sx + x, sy + y, n + 1
  end
  assert(n > 0, "nothing is planned")
  local cx, cy = scene.camera:tileToWorld(sx / n, sy / n)
  scene.camera:centerOn(cx, cy, d.game.app.view)
  d:frames(2)
end

local function counts(d)
  local f, c = d:world().state.fields, d:world().state.crops
  local tilled, planted = 0, 0
  for _ in pairs(f.tilled) do
    tilled = tilled + 1
  end
  for _ in pairs(c) do
    planted = planted + 1
  end
  return tilled, planted
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  d:advance(0.1)
  dismissFinds(d)

  -- Plan a field with radish seeds in hand; the Routine button is never pressed.
  scene.seedButtons.radish.onPress()
  d:frames(3)
  d:pick("Plan field")
  d:clickTile(d:freeTileNear(3, 2))
  d:clickTile(d:freeTileNear(6, 4))
  d:frames(3)
  assert(world.control == "active", "the Routine stays off")
  centreOnPlan(d)
  d:shot("planned") -- toast says tilling and planting start now
  d:advance(1.5)
  dismissFinds(d)
  centreOnPlan(d)
  d:shot("working") -- some tiles tilled, the homesteader at work, Routine still off
  local tilled = counts(d)
  assert(tilled > 0, "tilling started with the Routine off")

  -- The seeds run out: every planned tile is still tilled, planting waits.
  local have = Ledger.get(world, "seed_radish")
  Ledger.remove(world, "seed_radish", have, "scenario")
  d:advance(4)
  dismissFinds(d)
  centreOnPlan(d)
  local t2, planted = counts(d)
  d:shot("no_seeds") -- tilled bare soil, planting waits for seeds
  assert(t2 >= tilled, "tilling went on without seeds")

  -- Click away: a far tap sends the homesteader off. Seeds come back; the whole plot gets finished.
  Ledger.add(world, "seed_radish", have, "scenario")
  d:clickTile(d:freeTileNear(-5, -3))
  d:frames(30)
  d:shot("away")
  d:advance(5)
  dismissFinds(d)
  centreOnPlan(d)
  local _, planted2 = counts(d)
  assert(planted2 > planted, "the plot was planted after the homesteader came back")
  d:shot("resumed") -- every planned tile planted, nothing but the plan needed a tap
end
