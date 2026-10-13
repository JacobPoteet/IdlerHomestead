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
    id = "plant",
    title = "Plant a seed",
    trigger = "object.cleared",
    after = { step = "welcome", seconds = 60 },
    retire = { "crop.planted" },
    text = "Cleared! Pick a seed in the bottom bar (under Tools on a narrow screen), then tap open ground to till and plant it.",
  },
  {
    id = "water",
    title = "Water",
    trigger = "crop.planted",
    text = "Planted. Crops grow only while they are wet: tap a thirsty crop and the homesteader fetches water from the creek.",
  },
  {
    id = "food_clock",
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
    title = "A new idea",
    trigger = "journal.idea",
    text = "Open the Journal and pick an idea to study. It finishes while you sleep, then you can buy it in the Catalog.",
  },
  {
    id = "harvest",
    title = "First harvest",
    trigger = "crop.harvested",
    text = "Food goes to the Pantry first, and the extra to the sell crate. Open the Pantry to see the rules.",
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
    title = "A delivery",
    trigger = "market.delivered",
    text = "Your order arrived at the road. Tap the Place button in the bottom bar, then tap where it should go.",
  },
  {
    id = "truck_ready",
    title = "The truck can drive",
    trigger = "market.tripReady",
    retire = { "market.trip" },
    text = "The truck has enough charge for a trip. Tap the truck, choose Drive to town, and sell what is in the crate.",
  },
  {
    id = "town",
    title = "Town",
    trigger = "market.trip",
    text = "Town buys what is in your sell crate. You can also buy animals and pickup-only items here.",
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
  {
    id = "threat",
    title = "A threat is coming",
    trigger = "threat.warned",
    text = "The forecast shows when it hits. The Journal learns a counter after the first strike.",
  },
}
