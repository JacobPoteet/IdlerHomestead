-- Work categories for the task system (GDD §7.4). File order is the default idle priority.
return {
  { id = "harvest", name = "Harvest" },
  { id = "water", name = "Water" },
  { id = "animals", name = "Tend animals" },
  { id = "plant", name = "Till & plant" },
  { id = "process", name = "Preserve" },
  { id = "clear", name = "Clear land" },
  { id = "trees", name = "Clear trees", startsOff = true }, -- fells trees as the hand order does; off until the player switches it on (D109)
  { id = "fish", name = "Fish" },
}
