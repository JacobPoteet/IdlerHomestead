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
  "tasks",
  "crops",
  "inventory",
  "power",
  "perks",
  "food",
  "spoilage",
  "water",
  "clearing",
  "marks", -- D147: the Axe's and the Pail's area marks, standing orders over the clear and water tasks
  "placement", -- D79: orders to build over trees, rocks and crops; hands the homesteader its clearing jobs
  "fishing",
  "processing",
  "market",
  "stand",
  "income", -- D117: sales income per game year; listens to the sale events
  "finds",
  "cat",
  "animals",
  "threats",
  "shelter", -- D82: accessors only (insulation, heater slot, best bed); read by power, needs, sleep
  "needs",
  "wardrobe", -- D149: today's outfit, dressed at each new day after needs has settled the night; read by needs, power, readiness and actors
  "sleep",
  "actors",
  "machines",
  "routine",
  "ftue",
  "alerts", -- D70: reads needs; listens after everything has set up its state
  "nightly", -- D70: the morning report's ledger; closes after sleep has woken the homesteader
  "readiness", -- D70: accessors only
  "dusk", -- D161: the Tonight card's one-tap fixes; issues orders through marks, tasks and actors, no state of its own
}
