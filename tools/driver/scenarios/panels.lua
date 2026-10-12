-- Open each main panel from the homestead and close it again: pantry, catalog, journal, power,
-- guide (the "Fish" button) and the town/truck screen (by tapping the truck tile).
return function(d)
  d:newGame()
  d:advance(1)

  local function panel(label, name)
    d:press(label)
    d:frames(5)
    d:shot(name)
    d:key("escape")
    d:frames(3)
  end

  panel("Pantry", "pantry")
  panel("Catalog", "catalog")
  panel("Journal", "journal")
  panel("Power", "power")
  panel("Fish", "guide")

  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(5)
  d:shot("truck")
  d:key("escape")
  d:shot("homestead_after_panels")
end
