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
  "placement", -- D79: orders to build over trees, rocks and crops; hands the homesteader its clearing jobs
  "fishing",
  "processing",
  "market",
  "stand",
  "finds",
  "cat",
  "animals",
  "threats",
  "shelter", -- D82: accessors only (insulation, heater slot, best bed); read by power, needs, sleep
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
