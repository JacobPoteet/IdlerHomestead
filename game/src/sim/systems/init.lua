-- Simulation systems, initialized and ticked in this order.
-- Shared interfaces (ledger, tasks) come before the systems that use them.
return {
  "sandbox", -- D134: accessors only (the slot's sandbox flag); read by ledger, market and needs
  "calendar",
  "ledger",
  "journal",
  "weather",
  "established", -- D117: the Great Winter's thaw marks the slot; listens to the calendar after weather
  "land",
  "soil", -- D178: fertility per tile (grid.fertility); before crops, which read it at harvest
  "quality", -- D182: the tiers of stocked produce (a tally that follows the ledger); after soil, which it grades by
  "tasks",
  "crops",
  "inventory",
  "power",
  "perks",
  "food",
  "spoilage",
  "water",
  "felling", -- #362: the winter allowance on wood from trees; before clearing, which asks it
  "clearing",
  "marks", -- D147: the Axe's and the Pail's area marks, standing orders over the clear and water tasks
  "placement", -- D79: orders to build over trees, rocks and crops; hands the homesteader its clearing jobs
  "fishing",
  "processing",
  "market",
  "stand",
  "contracts", -- D197: the town's board (reputation = contracts finished); fills from surplus stock; the truck sale auto-fills it
  "income", -- D117: sales income per game year; listens to the sale events
  "finds",
  "cat",
  "dog", -- D189: the farm dog; eats from the food ledger; its guard is read by raiders and animals
  "lantern", -- D191: accessors only (the lantern's guard); read by raiders and animals
  "animals",
  "compost", -- D181: the bins, the manure loop and the Fertilize task; after animals, whose Tend chores rake into it
  "raiders", -- D188: the handler of the raccoon, deer and rabbits and the bear; accessors only, no state; before nightthreats, which asks it
  "threats",
  "nightthreats", -- D187: plans the night's threat at dusk and claims the night slot; after cat and animals (its handlers), before events (which draws at the same dusk)
  "home", -- D192: accessors only (a torn tarp, a clogged flue); read by shelter and needs
  "shelter", -- D82: accessors only (insulation, heater slot, best bed); read by power, needs, sleep
  "needs",
  "status", -- D166: injury and condition statuses; after needs so a duration counts down once the night's draw is done (read through Stats.factor)
  "wardrobe", -- D149: today's outfit, dressed at each new day after needs has settled the night; read by needs, power, readiness and actors
  "sleep",
  "actors",
  "machines",
  "routine",
  "ftue",
  "alerts", -- D70: reads needs; listens after everything has set up its state
  "nightly", -- D70: the morning report's ledger; closes after sleep has woken the homesteader
  "footing", -- D162: Footing, judged at dusk from the needs' figures; run state
  "events", -- D169: misfortune events (the dusk draw, the offer, the ignore window, the mercy rules); reads status and footing, and any night threat (C1) claims the night slot before it
  "milestones", -- D163: the run's checklist, ticked by world events
  "readiness", -- D70: accessors only
  "goal", -- D163: the pressing goal and its figures, accessors only (reads footing, readiness, weather)
  "dusk", -- D161: the Tonight card's one-tap fixes; issues orders through marks, tasks and actors, no state of its own
}
