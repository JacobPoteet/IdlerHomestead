-- The message log (GDD D90, #167) and the falling-condition chip (#176). Toasts are staged through the
-- scene's own entry points and the world's own events; the screens, taps and drags are the real ones.
return function(d)
  d:newGame()
  local world = d:world()
  d:frames(60)
  local scene = d:scene()

  -- A busy stretch: toasts that replace each other, a repeated catch and a storage overflow for three
  -- goods at once (one line), then a spoilage summary.
  local news = {
    "Delivered: Chicken coop",
    "Caught a perch",
    "Caught a perch",
    "Roadside stand sold 4 items for $12",
    "3 canned food ready",
    "The truck is charged: tap it to drive to town",
    "Forecast: rain on day 5, then clear",
    "New note: The creek runs low in late summer.",
    "Collected 4 eggs",
    "A fox tried the coop in the night. The door held.",
    "Collected 3 milk",
    "Caught a bluegill (new!)",
    "Health is falling (82). Eat and keep warm",
    "Routine planned a starter field (6 tiles). Plan field changes it",
  }
  for _, text in ipairs(news) do
    scene:queueToast(text)
  end
  for _, part in ipairs({ { "wood", 3 }, { "stone", 2 }, { "radish", 5 } }) do
    world.events:emit("ledger.overflow", { id = part[1], lost = part[2] })
  end
  scene:urgentToast("Spoiled overnight: 3 radish, 1 fish. See the Pantry.")
  d:frames(3)
  d:shot("toast") -- the toast on screen, the Log button beside Menu

  d:pick("Log")
  d:frames(3)
  d:shot("open") -- newest first, the coalesced storage line and a repeat count in the list
  d:wheel(-6, 200, 200)
  d:frames(2)
  d:shot("scrolled")
  d:key("escape")
  d:frames(3)

  -- Save the slot, close it and reopen it from the saved file (D120, #224): the log is still there.
  local before = scene.log:lines()
  scene.session:save()
  local session = scene.session
  d.game.app:switch(require("src.scenes.slots").new())
  d:frames(3)
  d.game.app:switch(require("src.scenes.homestead").new(), session.slot, session.store:read(session.slot))
  d:frames(10)
  scene = d:scene()
  world = d:world()
  local after = scene.log:lines()
  assert(#after == #before and after[1].text == before[1].text, "the reopened slot lost its message log")
  d:pick("Log")
  d:frames(3)
  d:shot("reopened") -- the same lines as before the save
  d:key("escape")
  d:frames(3)

  -- A full heart dropping a lot overnight: amber long before it is low.
  world.state.needs.condition = 100
  world.state.alerts.dawn = { last = 100, prior = 100, day = 1 }
  d:frames(3)
  world.state.needs.condition = 100 - world.tuning.alerts.conditionFallDrop - 8
  scene.toast, scene.toastQueue = nil, {}
  d:frames(60)
  d:shot("falling") -- the heart chip is amber at about 82
end
