-- Order the homesteader to clear the nearest rock/log/brush and capture the action progress ring
-- while the work is under way, then once it is done.
local Actors = require("src.sim.systems.actors")

return function(d)
  d:newGame()
  local tx, ty = d:nearestObject({ rock = true, log = true, brush = true })
  assert(tx, "nothing to clear on the map")
  local target = require("src.sim.grid").index(d:world().state.grid, tx, ty)
  d:clickTile(tx, ty)
  d:shot("order_given")

  -- Walk there, then wait until the timed work has started and is part-way done.
  local hs = Actors.homesteader(d:world())
  for _ = 1, 400 do
    d:frames(1)
    local p = Actors.progress(d:world(), hs)
    if p and p.target == target and p.fraction > 0.4 then
      break
    end
  end
  d:shot("progress_ring")

  d:advance(0.5)
  d:shot("after_clear")
end
