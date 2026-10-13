-- First-time tip cards (GDD D69, #152): the welcome card on a brand-new slot, the clearing and planting
-- tips, a card with a tile selected, the routine and autumn cards (the longest texts), the Menu's Tips
-- list and a replayed tip, then "Skip tips". The first card comes from the real start of the game;
-- later moments (a seed planted, autumn arriving) are announced on the event bus because waiting for
-- them would take most of a season. The cards and the Menu are the real ones.
local Ftue = require("src.sim.systems.ftue")

return function(d)
  d:newGame({ tips = true })
  local world = d:world()
  d:frames(80) -- the welcome card is due a few game seconds in
  d:shot("welcome")

  -- Tapping the card does not hand the homesteader the ground beneath it, and Got it closes it.
  d:press("Got it")
  d:frames(3)
  d:shot("dismissed") -- cards leave the screen clear

  -- The chip tip (D89, #186) follows the welcome card and outlines the food chip; tapping a chip retires it.
  d:advance(1.8)
  d:frames(3)
  d:shot("chips") -- pulsing outline on the food chip
  d:press("Got it")
  -- The real sim raises the routine and bedtime cards on its own in this stretch; hold them back so
  -- the highlighted cards below are the ones on screen (the routine card is shot further down).
  local held = Ftue.state(world).seen
  held.routine, held.bedtime, held.plant = true, true, true
  d:advance(1.8)
  world.events:emit("market.tripReady", {})
  d:advance(0.4)
  d:frames(3)
  d:shot("truck_ready") -- pulsing outline on the truck
  d:press("Got it")
  d:advance(1.8)
  world.events:emit("journal.idea", { item = "smoker" })
  d:advance(0.4)
  d:frames(3)
  d:shot("idea") -- outline on the Journal button
  d:press("Got it")
  held.routine, held.bedtime, held.plant = nil, nil, nil
  world.events:emit("hud.chipOpened", {}) -- a chip opened: the chip tip is retired (tests cover it)

  -- The first thing cleared: the plant tip, with the tile info panel pushed above the card.
  world.events:emit("object.cleared", { id = "tree" })
  d:advance(2)
  d:clickTile(d:freeTileNear(1, 0))
  d:frames(3)
  d:shot("plant_with_selection")
  d:press("Got it")

  -- Two cards at once queue rather than stack: water comes first, food waits out the gap.
  world.events:emit("needs.ate", { calories = 3000, shortfall = 0 })
  world.events:emit("crop.planted", {})
  d:advance(2)
  d:shot("water_first")
  d:press("Got it")
  d:frames(3)
  d:shot("gap_after_card") -- nothing yet: the next one waits out tuning.ftue.minGap
  d:advance(2)
  d:shot("food_clock")
  d:press("Got it")

  -- The longest texts.
  world.events:emit("routine.idleHint", { idleFor = 60 })
  d:advance(2)
  d:shot("routine")
  d:press("Got it")
  world.events:emit("calendar.newSeason", { season = "autumn", year = 1 })
  d:advance(2)
  d:shot("autumn")
  d:press("Skip tips")
  d:frames(3)
  d:shot("skipped")

  -- Menu > Tips: replay a tip, bring them back.
  d:key("escape") -- cancel opens the Menu on the homestead
  d:frames(3)
  d:shot("menu")
  d:press("Tips")
  d:frames(3)
  d:shot("tips_list")
  d:press("Winter")
  d:frames(3)
  d:shot("tip_replayed")
  d:press("Got it")
  d:press("Show all again")
  d:key("escape")
  d:key("escape")
  d:frames(3)
  assert(Ftue.enabled(world), "Show all again turns the tips back on")
  d:advance(2)
  d:shot("welcome_again")
end
