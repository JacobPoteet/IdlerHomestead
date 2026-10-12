-- Processing recipes for processor objects (GDD §5.3, §6.2).
-- inputCategory: any resource of this category is accepted, up to `batch` units per load.
-- fuel: resources consumed per load. hours: in-game hours a load takes.
return {
  {
    id = "smoke_fish",
    name = "Smoke fish",
    station = "smoker",
    inputCategory = "fish",
    batch = 4,
    fuel = { wood = 2 },
    output = "smoked_fish",
    hours = 6,
  },
}
