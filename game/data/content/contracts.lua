-- Contracts (D197, #372, docs/PLAN_DEPTH.md §9.2): what the town asks for. Content only: src/sim/systems/contracts.lua rolls
-- the board from it each week; the numbers (offers a week, deadlines, reward multiplier) are tuning.contracts.
--
--   name       who asks (the buyer's label on the board)
--   item       resource id asked for (offered only once the run has held some)
--   min, max   units an offer asks (capped to the good's storage)
--   minDone    contracts finished before it is offered: reputation is that count, it opens richer goods and a better price
--   standing   true = the repeating weekly order: one of each stays on the board, and a new one comes each week once it is
--              filled or has lapsed. A board offer is picked at random from the eligible ones; a standing order is always offered.
-- No quality tiers: a contract wants units of a good, whatever their quality.
return {
  { id = "eggs", name = "The diner", item = "egg", min = 6, max = 14 },
  { id = "radish", name = "The market stall", item = "radish", min = 10, max = 24 },
  { id = "lettuce", name = "The diner", item = "lettuce", min = 6, max = 14 },
  { id = "beans", name = "The cannery", item = "beans", min = 8, max = 18 },
  { id = "potato", name = "The school", item = "potato", min = 10, max = 24 },
  { id = "corn", name = "The market stall", item = "corn", min = 8, max = 18 },
  { id = "tomato", name = "The cannery", item = "tomato", min = 6, max = 12 },
  { id = "carrot", name = "The school", item = "carrot", min = 8, max = 18, minDone = 2 },
  { id = "onion", name = "The diner", item = "onion", min = 6, max = 14, minDone = 2 },
  { id = "squash", name = "The grocer", item = "squash", min = 6, max = 14, minDone = 2 },
  { id = "milk", name = "The creamery", item = "milk", min = 6, max = 12, minDone = 3 },
  { id = "herbs", name = "The grocer", item = "herbs", min = 4, max = 10, minDone = 3 },
  { id = "berries", name = "The bakery", item = "berries", min = 4, max = 10, minDone = 4 },
  { id = "apple", name = "The bakery", item = "apple", min = 6, max = 12, minDone = 4 },
  { id = "cheese", name = "The grocer", item = "cheese", min = 3, max = 8, minDone = 5 },
  { id = "firewood", name = "The neighbor", item = "wood", min = 20, max = 40 },
  { id = "standing_eggs", name = "The diner, weekly", item = "egg", min = 6, max = 6, standing = true },
  { id = "standing_wood", name = "The neighbor, weekly", item = "wood", min = 15, max = 15, standing = true },
}
