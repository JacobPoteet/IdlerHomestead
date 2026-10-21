-- Work categories for the task system (GDD §7.4). File order is the default idle priority.
return {
  { id = "harvest", name = "Harvest" },
  { id = "water", name = "Water" },
  { id = "animals", name = "Tend animals" },
  { id = "maintenance", name = "Upkeep" }, -- pulls weeds and spreads compost (D180, D181); ON by default and above planting so an idle day keeps the beds clean (D185)
  { id = "plant", name = "Till & plant" },
  { id = "process", name = "Preserve" },
  { id = "clear", name = "Clear land" },
  { id = "trees", name = "Clear trees", startsOff = true }, -- fells trees as the hand order does; off until the player switches it on (D109)
  { id = "fish", name = "Fish" },
}
