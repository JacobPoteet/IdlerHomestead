-- First-time tip cards (GDD D69, #152): the welcome card on a brand-new slot, the clearing and planting
-- tips, a card with a tile selected, the routine and autumn cards (the longest texts), a walk of the homestead-depth
-- tips (D202, #390: Tonight, an event, night visitors, a status, a Footing slip, what limits you, rotation, weeds and
-- contracts), "Skip tips" on the winter card, the Menu's Tips list and a replayed tip. The first card comes from the real start of the game;
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
  -- The delivery card points at Place; the bar here keeps tools in a palette, so the outline falls back
  -- to the Tools button that opens it (src/ui/highlight.lua FALLBACK).
  world.events:emit("market.delivered", { item = "smoker" })
  d:advance(2)
  d:frames(3)
  d:shot("delivery_place_fallback")
  d:press("Got it")
  world.events:emit("calendar.newSeason", { season = "autumn", year = 1 })
  d:advance(2)
  d:shot("autumn")
  d:press("Got it")

  -- The homestead-depth tips (D202, #390), each from its own event, one card at a time. The Footing tip comes a while
  -- after Footing is gained and outlines the goal line; the contracts tip outlines the truck. Each entry: the step, the
  -- event that raises it, its payload, and how many two-hour waits it may take to come due.
  held.routine, held.bedtime, held.harvest = true, true, true -- (the first harvest has its own card above the soil tip)
  local walk = {
    { "tonight", "hud.tonightOpened", {}, 2 },
    { "event", "event.offered", { id = "sprained_ankle", class = "body", bad = true, day = 4 }, 2 },
    { "night_threat", "nightthreat.resolved", { id = "fox", outcome = "turned", lost = {} }, 2 },
    { "status", "status.applied", { id = "ankle_1" }, 2 },
    { "footing_slipped", "footing.slipped", { day = 9, fuel = 0, food = 0 }, 2 },
    { "bottleneck", "footing.gained", { day = 10 }, 4 },
    { "soil", "crop.harvested", { crop = "radish", tile = 1, amount = 1, repeated = true }, 2 },
    { "weeds", "soil.weeds", { tile = 1, from = 0, to = 0.1, cause = "sprout" }, 2 },
    { "contracts", "contract.offered", { id = 1, def = "radish", standing = false }, 6 },
  }
  for _, step in ipairs(walk) do
    local id, event, payload, steps = step[1], step[2], step[3], step[4]
    local holding = {}
    for _, other in ipairs(walk) do
      if other[1] ~= id and not Ftue.isSeen(world, other[1]) then
        held[other[1]], holding[#holding + 1] = true, other[1] -- an event can raise another step (Footing opens the board): hold it back for its own turn
      end
    end
    world.events:emit(event, payload)
    local card
    for _ = 1, steps do -- wait two in-game hours at a time, at most `steps` times, until the card is due
      d:advance(2)
      d:frames(3)
      card = Ftue.current(world)
      if card then
        break
      end
    end
    assert(card and card.id == id, "the " .. id .. " tip is up (got " .. tostring(card and card.id) .. ")")
    d:shot("depth_" .. id)
    d:press("Got it")
    for _, other in ipairs(holding) do
      held[other] = nil
    end
  end
  held.routine, held.bedtime, held.harvest = nil, nil, nil

  world.events:emit("weather.froze", {})
  d:advance(2)
  d:shot("winter")
  d:press("Skip tips")
  d:frames(3)
  d:shot("skipped")

  -- Menu > Tips: replay a tip, bring them back. (The walk above ran the clock into the evening, so the Tonight card is
  -- up and Esc would put it away first: the Menu button opens the Menu.)
  d:press("Menu")
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
