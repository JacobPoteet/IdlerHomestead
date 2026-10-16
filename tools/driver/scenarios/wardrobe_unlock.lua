-- Earning clothes (D155, docs/PLAN_WARDROBE_MENU.md §7.2): a garment earned in play shows its toast, the left-edge
-- "New clothes" stamp and a dot on its tile and slot tab; the run fails; the recovery scene lists the run's new
-- clothes beside a Change clothes button; the Wardrobe opens over it, a Wear applies at once, and the next run
-- begins wearing it. Garments are earned through the sim's own grant (which raises wardrobe.unlocked as a real
-- unlock does), never by writing meta.
local Actors = require("src.sim.systems.actors")
local Wardrobe = require("src.sim.systems.wardrobe")

return function(d)
  d:newGame()
  local world = d:world()
  local session = d.game.app.ctx.session
  local function top()
    return d.game.app:top()
  end
  local function dismissFinds()
    for _ = 1, 3 do
      local t = top()
      if t.select and t.take then
        t:select(1)
        t:take()
      end
      d:frames(2, 0.05)
    end
  end
  session:setSpeed(0)
  dismissFinds()

  -- Two garments earned on one dawn read as one toast; here three come at once.
  Wardrobe.grant(world, "straw_hat")
  Wardrobe.grant(world, "linen_shirt")
  Wardrobe.grant(world, "work_gloves")
  d:frames(6, 0.05)
  assert(d:scene().toast and d:scene().toast.text == "New clothes: 3 garments", "one toast says all three")
  d:shot("toast")
  assert(Wardrobe.stampDue(world), "the stamp is due")
  d:frames(60, 0.05)
  d:shot("stamp")

  d:press("New clothes") -- the stamp opens the Wardrobe and goes
  assert(top().name == "wardrobe", "the stamp opens the Wardrobe")
  assert(not Wardrobe.stampDue(world), "opening it answers the stamp")
  assert(top().slot == "head", "it opens on the first slot with a new garment")
  assert(Wardrobe.isNew(world, "straw_hat"), "the dot waits until the tile is looked at")
  d:frames(4, 0.05)
  d:shot("new_dot")
  d:press("Straw hat")
  assert(not Wardrobe.isNew(world, "straw_hat"), "looking at a tile clears its dot")
  d:key("escape")
  d:frames(4, 0.05)
  assert(top().name == "homestead")

  -- The run fails (the failure is raised on the bus, as the rescue scenario does); the rescue scene, then recovery.
  world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
  d:frames(4)
  d:frames(150, 1 / 30)
  d:click(40, 40)
  d:frames(6)
  assert(top().name == "recovery", "on to the recovery scene, not " .. tostring(top().name))
  assert(#top().clothes >= 3, "the row lists the run's clothes")
  d:shot("recovery_row")

  d:press("Change clothes")
  assert(top().name == "wardrobe" and top().variant == "recovery", "the recovery Wardrobe")
  assert(top().slot == "torso", "it opens on the slot of the garment still marked new")
  d:press("Head")
  d:press("Straw hat")
  d:press("Wear")
  d:frames(4)
  assert(Wardrobe.committed(top().world).head == "straw_hat", "Wear chose it")
  d:shot("recovery_wardrobe")
  d:press("Done")
  d:frames(4)
  assert(top().name == "recovery", "Done comes back to the recovery scene")

  d:press("Head out")
  d:frames(4)
  d:advance(0.1)
  d:frames(120)
  dismissFinds()
  world = d:world()
  assert(Wardrobe.dressed(world).head == "straw_hat", "the next run wears it from the start")
  d:tryPress("Got it")
  session = d.game.app.ctx.session
  session:setSpeed(0)
  local scenery = d:scene()
  local hs = Actors.homesteader(world)
  local tile = world.tuning.display.tileSize
  scenery.camera:centerOn((hs.x + 0.5) * tile, (hs.y + 0.5) * tile, d.game.app.view)
  scenery.camera.zoomIndex = 3
  scenery.camera:clamp(d.game.app.view)
  d:frames(4, 0.05)
  d:shot("head_out_dressed")
end
