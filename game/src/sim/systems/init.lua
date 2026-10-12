-- Simulation systems, initialized and ticked in this order.
-- Shared interfaces (ledger, tasks) come before the systems that use them.
return {
  "calendar",
  "ledger",
  "journal",
  "weather",
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
  "fishing",
  "processing",
  "firewood",
  "market",
  "stand",
  "finds",
  "cat",
  "animals",
  "threats",
  "needs",
  "sleep",
  "actors",
  "machines",
  "routine",
  "ftue",
  "alerts", -- D70: reads needs; listens after everything has set up its state
  "nightly", -- D70: the morning report's ledger; closes after sleep has woken the homesteader
  "readiness", -- D70: accessors only
}
