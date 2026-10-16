-- A Sandbox slot's wardrobe (D134, D155): every garment is owned from the start, so there are no dots, no
-- "New clothes" stamp and no unlock toast, and the page carries the SANDBOX tag. Nothing here says a garment
-- is locked.
local Wardrobe = require("src.sim.systems.wardrobe")

return function(d)
  d:newGame({ sandbox = true })
  local world = d:world()
  local session = d.game.app.ctx.session
  local function top()
    return d.game.app:top()
  end
  session:setSpeed(0)
  for _ = 1, 3 do
    local t = top()
    if t.select and t.take then
      t:select(1)
      t:take()
    end
    d:frames(2, 0.05)
  end
  d:frames(10, 0.05)
  assert(world.meta.sandbox == true, "a sandbox slot")
  assert(not Wardrobe.stampDue(world), "no stamp")
  assert(Wardrobe.newCount(world) == 0, "no dots")
  assert(not Wardrobe.grant(world, "scarf"), "nothing is earned here")
  d:frames(6, 0.05)
  assert(not d:scene().toast, "no toast")
  d:key("c")
  assert(top().name == "wardrobe", "the Wardrobe opens")
  d:press("Torso")
  d:press("Down parka") -- owned: it is a normal tile, not a "???" one
  assert(top().state:draft().torso == "down_parka", "tapping a never-earned garment previews it")
  d:shot("all_owned")
end
