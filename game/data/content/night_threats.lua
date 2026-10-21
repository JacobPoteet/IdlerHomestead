-- Night threats (D187, #355, docs/PLAN_DEPTH.md §6.1): what can come at the homestead in the night. Content only:
-- src/sim/systems/nightthreats.lua plans one at dusk (a night has one slot, shared with misfortune events), lands it at its
-- hour and reports it; the handler named here owns the stream and the effect. The tuning is tuning.night (exposure,
-- mercy) and the handler's own file (tuning.cat, tuning.animals).
--
--   handler       "cat" | "animals": the system whose nightPlan and nightLand draw and land this threat (mice, fox)
--   seasons       list of season ids it can come in (absent = every season); the handler's tuning shapes the odds
--   minDay        earliest day of the run (absent = the handler's own firstDay is the only limit)
--   minYear       earliest year (absent = any)
--   weight        relative weight when more than one threat hits the same night and the `night` stream picks one
--   exposure      0..1, how much the night's exposure shapes this threat's chance (0 = none, 1 = fully)
--   guard         stat name whose modifiers turn it aside (documentation; the handler reads the stat)
--   counter       catalog id of the item that answers it (a journal idea once its note is written)
--   warn          { line }: the dusk sign on the Tonight card once the threat is drawn for tonight
--   outcomes      turned = { report }: the morning report line when it was turned away;
--                 landed = { capital? (it destroys capital: livestock), lesser? = { lose = { resource = n } }, sparedReport? }:
--                 the handler's own toast and report line say what a landed threat took; while Footing is slipped a capital
--                 threat takes only `lesser` (PLAN_DEPTH 6.5 rule 3) and the report says `sparedReport`
--   wake          id of a night event (data/content/events.lua, `wake = true`) offered once it has resolved; the event engine
--                 keeps its own wake rules (not before night 3, one a night, never under the mercy rules)
--   journalNote   note id written the first time it lands
return {
  {
    id = "mice",
    name = "Mice",
    handler = "cat",
    weight = 1,
    exposure = 1,
    counter = "shelter_cat",
    warn = { line = "Droppings by the food store: mice are about tonight." },
    outcomes = {
      turned = { report = "The cat caught a mouse in the night." },
      landed = {},
    },
    journalNote = "mice_raid",
  },
  {
    id = "fox",
    name = "Fox",
    handler = "animals",
    weight = 2, -- a fox is the likelier to be the one that comes when both would
    exposure = 1,
    guard = "predatorGuard",
    counter = "chicken_fence",
    warn = { line = "Fresh tracks by the coop: a fox is about tonight." },
    outcomes = {
      turned = { report = "A fox tried the animals in the night. The fence held." },
      landed = {
        capital = true,
        lesser = { lose = { chicken_feed = 3, hay = 3 } }, -- units: a slipped Footing costs a raided feed store, not the animals
        sparedReport = "A fox got into the feed store. The animals were safe.",
      },
    },
    journalNote = "fox_raid",
  },
}
