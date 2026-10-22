-- Night threats (D187, #355, docs/PLAN_DEPTH.md §6.1): what can come at the homestead in the night. Content only:
-- src/sim/systems/nightthreats.lua plans one at dusk (a night has one slot, shared with misfortune events), lands it at its
-- hour and reports it; the handler named here owns the stream and the effect. The tuning is tuning.night (exposure,
-- mercy) and the handler's own file (tuning.cat, tuning.animals).
--
--   handler       "cat" | "animals" | "raiders": the system whose nightPlan and nightLand draw and land this threat (mice, fox;
--                 the raccoon, deer and bear are all "raiders", which reads this entry's id and tuning.raiders[id])
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
--                 the handler's own toast and report line say what a landed threat took (a raider's `report` has one %s for what
--                 it took: the units of a store, or the number of crops, D188); while Footing is slipped a capital
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
  {
    id = "raccoon",
    name = "Raccoon",
    handler = "raiders",
    seasons = { "spring", "summer", "autumn" },
    weight = 2,
    exposure = 0.7, -- a raccoon comes for the food, whatever the shelter says
    guard = "raccoonGuard",
    counter = "lidded_bins",
    warn = { line = "Overturned bin by the shed: a raccoon is about tonight." },
    outcomes = {
      turned = { report = "A raccoon tried the stores in the night. The lids held." },
      landed = { report = "A raccoon got into the stores and spoiled %s." },
    },
    journalNote = "raccoon_raid",
  },
  {
    id = "deer",
    name = "Deer and rabbits",
    handler = "raiders",
    seasons = { "spring", "summer", "autumn" },
    weight = 1,
    exposure = 0.5,
    guard = "cropGuard",
    counter = "scarecrow",
    warn = { line = "Hoofprints and nibbled leaves at the field's edge: deer are about tonight." },
    outcomes = {
      turned = { report = "Deer came to the field in the night. The scarecrow kept them off." },
      landed = { report = "Deer and rabbits browsed %s on the field's edge. They will give a smaller harvest." },
    },
    journalNote = "deer_browse",
  },
  {
    id = "bear",
    name = "Black bear",
    handler = "raiders",
    seasons = { "autumn" },
    weight = 3, -- a bear is the one that comes when it would
    exposure = 1,
    guard = "bearGuard",
    counter = "bear_box",
    warn = { line = "Claw marks on the smokehouse door: a bear is about tonight." },
    outcomes = {
      turned = { report = "A bear nosed around the stores in the night. The bear box held." },
      landed = { report = "A bear tore into the stores and took %s." },
    },
    journalNote = "bear_raid",
  },
}
