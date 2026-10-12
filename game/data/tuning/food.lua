-- Food rules: pantry, preserving, sell crate (GDD §6.2) and spoilage.
return {
  defaultPantryDays = 3, -- days of food kept to eat before anything is preserved or sold
  defaultWinterDays = 10, -- days of preserved food to aim for before selling preserved goods
  maxPantryDays = 30, -- upper limit for the pantry slider
  maxWinterDays = 120, -- upper limit for the winter stock slider
  rulesInterval = 1, -- in-game hours between automatic pantry/crate sorting passes
  loadStationTime = 2, -- seconds of work to load a processing station (smoker)
}
