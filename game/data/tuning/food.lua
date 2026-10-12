-- Food rules: pantry, preserving, sell crate (GDD §6.2) and spoilage.
return {
  defaultPantryDays = 3, -- days of food kept to eat before anything is preserved or sold
  defaultWinterDays = 10, -- days of preserved food to aim for before selling preserved goods
  maxPantryDays = 30, -- upper limit for the pantry slider
  maxWinterDays = 120, -- upper limit for the winter stock slider
  rulesInterval = 1, -- in-game hours between automatic pantry/crate sorting passes
  loadStationTime = 2, -- seconds of work to load a processing station (smoker)
  -- D68 (#163): the automatic pantry keeps a perishable only as long as it will be eaten before it
  -- spoils, so surplus goes to the sell crate instead of rotting in the pantry.
  autoPantryHorizon = 0.5, -- fraction of a food's spoilDays the automatic pantry may hold it (fish 2 d -> 1 d, radish 4 d -> 2 d)
  -- D68 (#151): how spoilage is described to the player (read through Spoilage accessors).
  spoilWarnUnits = 1, -- units of one food expected to rot tonight from which the pantry shows a warning
  spoilFastRate = 0.2, -- share of a stock lost per night from which a food "spoils fast" (fish, radish)
  spoilSlowRate = 0.1, -- share lost per night below which a food "keeps well" (egg, potato)
}
