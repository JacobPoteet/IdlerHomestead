-- Save slots.
return {
  slotCount = 3, -- number of save slots (GDD §7.11)
  autosaveInterval = 60, -- seconds of play between autosaves (also saves on focus loss / quit)
  maxNameLength = 20, -- characters allowed in a slot name
  defaultSlotName = "Homestead", -- name given to a new slot before the player renames it
}
