-- First-time user experience steps (GDD D69, #152; step list from docs/GAMEPLAY_LOOP.md section 4).
-- File order is the order cards show in when several are due. A step appears as a small card the
-- first time its trigger happens in a slot, and can be replayed from Menu > Tips.
--   trigger  event name on the bus (see the event list in the systems), or "start" (due as soon as
--            a fresh slot begins). Optional: a step may rely on `after` alone.
--   match    optional { field = value } the event payload must equal.
--   delay    game seconds from trigger to due (default tuning.ftue.defaultDelay).
--   after    optional { step, seconds }: also due `seconds` after that step was dismissed.
--   retire   events that mean the player already knows it: the step is marked seen without a card.
--   doneFlag a meta flag that means the step was already told by another card (the spoilage card, D68).
--   card     false: the step never queues a card (told elsewhere); the Tips list still replays it.
--   highlight optional target the scene outlines while the card is up (D89, src/ui/highlight.lua):
--            "button:<id>", "seeds", "chip:<id>" or "tile:truck". Render only; a target that is not on
--            screen shows no outline.
--   replay   "spoil": the Tips list shows the live spoilage explanation instead of `text`.
-- Text may hold {domain.key} tokens, read from tuning at show time so a retuned number stays true.
return {
  {
    id = "welcome",
    title = "Welcome",
    trigger = "start",
    delay = 3,
    text = "Your truck died here. Tap the ground to walk, and tap trees, rocks and junk to clear them. Junk pays a few dollars.",
  },
  {
    -- The top-bar chips explain themselves on tap (D72), but nothing says so (#186, D89). Retired by the
    -- first chip card opened (hud.chipOpened, emitted by the homestead scene).
    id = "chips",
    title = "The top bar",
    highlight = "chip:food",
    after = { step = "welcome", seconds = 5 },
    retire = { "hud.chipOpened" },
    text = "Tap a chip in the top bar (food, health, money ...) to see what it means and what moves it.",
  },
  {
    id = "plant",
    highlight = "seeds",
    title = "Plant a seed",
    trigger = "object.cleared",
    after = { step = "welcome", seconds = 60 },
    retire = { "crop.planted" },
    text = "Cleared! Pick a seed in the bottom bar (under Tools on a narrow screen), then tap open ground to till and plant it.",
  },
  {
    -- Early money is invisible (#161, D88): the first junk pile cleared pays, so say that is where it comes from.
    id = "junk_money",
    highlight = "button:catalog",
    title = "Where money comes from",
    trigger = "object.cleared",
    match = { object = "junk" },
    text = "Junk pays cash: that is where your first money comes from, so clear more of it. Spend it in the Catalog on seeds, bait and food. Later the truck sells your spare food in town.",
  },
  {
    id = "water",
    title = "Water",
    trigger = "crop.planted",
    text = "Planted. Crops grow only while they are wet: tap a thirsty crop and the homesteader fetches water from the creek.",
  },
  {
    id = "food_clock",
    highlight = "chip:food",
    title = "Food and health",
    trigger = "needs.ate",
    text = "You eat {needs.dailyCalories} calories a day. The food chip is days of food left. At zero your health (heart) drops. Harvest radishes or catch fish.",
  },
  {
    id = "routine",
    title = "The Routine",
    trigger = "routine.idleHint",
    text = "Stop tapping for {idle.takeoverDelay} seconds and the Routine takes over: watering, harvesting, planting, chopping, fishing. Tap anywhere to take over again. It will not sell, buy, drive or choose what to study.",
  },
  {
    id = "bedtime",
    title = "Bedtime",
    trigger = "sleep.started",
    text = "The homesteader sleeps in the truck until sunrise. Sleeping is when the Journal studies. Tap Skip night to jump ahead. Anything you order wakes them.",
  },
  {
    id = "idea",
    highlight = "button:journal",
    title = "A new idea",
    trigger = "journal.idea",
    text = "Open the Journal and pick an idea to study. It finishes while you sleep, then you can buy it in the Catalog.",
  },
  {
    id = "harvest",
    highlight = "button:pantry",
    title = "First harvest",
    trigger = "crop.harvested",
    text = "The Pantry keeps what you need to eat. Anything above that is spare: the stand and the truck can sell it. Open the Pantry to change what you keep.",
  },
  {
    id = "spoil",
    title = "Food spoils",
    -- Told by the card Food shows after the first night of spoilage (D68); this entry just records it
    -- and lets Menu > Tips replay it.
    doneFlag = "spoilExplained",
    card = false,
    replay = "spoil",
    text = "Fresh food keeps for a while, then spoils. Eat it, sell it or smoke it before then.",
  },
  {
    id = "fish",
    title = "Fish keep badly",
    trigger = "fish.caught",
    text = "Fish spoil fast. Smoked fish keeps all winter, so watch the Journal for a smoker.",
  },
  {
    id = "delivery",
    highlight = "button:place",
    title = "A delivery",
    trigger = "market.delivered",
    text = "Your order arrived at the road. Tap the Place button in the bottom bar, then tap where it should go.",
  },
  {
    id = "truck_ready",
    highlight = "tile:truck",
    title = "The truck can drive",
    trigger = "market.tripReady",
    retire = { "market.trip" },
    text = "The truck has enough charge for a trip. Tap the truck, choose Load the truck (Auto-load fills it with spare goods), then Drive to town.",
  },
  {
    id = "town",
    title = "Town",
    trigger = "market.trip",
    text = "Sell the load to turn what you brought into money; anything you did not load stayed home. You can also buy animals and pickup-only items here.",
  },
  {
    id = "autumn",
    title = "Autumn",
    trigger = "calendar.newSeason",
    match = { season = "autumn" },
    text = "Winter is coming: store firewood (the firewood chip counts nights), keep food, and watch the forecast under the top bar. Crops still in the ground die when winter starts.",
  },
  {
    id = "winter",
    title = "Winter",
    trigger = "weather.froze",
    text = "The creek froze: cut a hole to fish or fetch water. Long nights mean fast studying.",
  },
  -- Cards for run 2 (D99, #173): `run = 2` queues them when the slot's second run begins, even though the
  -- first-run tips are over, and never if the player skipped the tips. Once per slot like every step.
  {
    id = "carried",
    run = 2,
    trigger = "start",
    delay = 3,
    title = "New land, same knowledge",
    text = "The land is new and the farm is gone. What stays: the notes you wrote, the idea you studied for free, and the Journal's research.",
  },
  {
    id = "carried_perks",
    run = 2,
    highlight = "button:journal",
    after = { step = "carried", seconds = 8 },
    title = "Notes spark ideas",
    text = "Open the Journal: notes from last run are ready to study. A perk studied in a run works from your next run, so it starts now.",
  },
  {
    id = "threat",
    title = "A threat is coming",
    trigger = "threat.warned",
    text = "The forecast shows when it hits. The Journal learns a counter after the first strike.",
  },
}
