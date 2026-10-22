-- Field Journal chapters (GDD §8.3): regions of the knowledge map. Journal nodes (catalog items
-- and perks) land in the chapter that lists their `page`. File order is map order; chapters with
-- no nodes yet are hidden. `area` is the heading the chapter sits under on the journal overview (D81);
-- a chapter without one goes under tuning.ui.journal.defaultArea. Areas appear in order of first use.
return {
  { id = "water_soil", name = "Water & Soil", pages = { "seeds", "tools", "water_soil" }, area = "Farm" },
  { id = "fishing", name = "Fishing", pages = { "fishing" }, area = "Food" },
  { id = "preserving", name = "Preserving", pages = { "preserving", "supplies" }, area = "Food" },
  { id = "shelter", name = "Shelter", pages = { "shelter" }, area = "Home" },
  { id = "power", name = "Power", pages = { "power" }, area = "Home" },
  { id = "weather", name = "Weather", pages = { "weather" }, area = "Know-how" },
  { id = "habits", name = "Habits", pages = { "habits" }, area = "Know-how" },
  { id = "animals", name = "Animals", pages = { "animals" }, area = "Farm" },
  { id = "machines", name = "Machines", pages = { "machines" }, area = "Farm" },
  { id = "upgrades", name = "Upgrades", pages = { "upgrades" }, area = "Farm" }, -- tiers II and III of the catalog ladders (D198)
}
