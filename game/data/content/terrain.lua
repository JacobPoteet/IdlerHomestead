-- Ground types for the tile grid.
return {
  { id = "grass", name = "Grass", walkable = true, tillable = true, buildable = true },
  { id = "road", name = "Dirt road", walkable = true },
  { id = "water", name = "Creek", walkable = false, water = true },
  -- Shallow crossing: walkable but slow, and you can fill a bucket here.
  { id = "ford", name = "Ford", walkable = true, water = true, walkCost = 2.5 },
}
