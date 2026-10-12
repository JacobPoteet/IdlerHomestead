-- Simulation systems, initialized and ticked in this order.
-- Shared interfaces (ledger, tasks) come before the systems that use them.
return {
  "calendar",
  "ledger",
  "land",
  "tasks",
  "crops",
  "inventory",
  "power",
  "food",
  "spoilage",
  "water",
  "clearing",
  "fishing",
  "processing",
  "market",
  "needs",
  "actors",
}
