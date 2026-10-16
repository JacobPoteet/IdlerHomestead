-- Open each page of the two books from the homestead and close it again (D143): the Ledger's Pantry, Routine,
-- Catalog and Truck & town (by tapping the truck tile), the Notebook's Journal, Fish guide and Diary, and
-- the Power lens's card (a lens, not a book page; D145). Then the book plates
-- reopen each book on the page it was last left on, and the camp is a way into the Pantry.
return function(d)
  d:newGame()
  d:advance(1)

  local function panel(label, name)
    if label == "Power" then
      d:scene():showLens("power")
    else
      d:pick(label)
    end
    d:frames(5)
    d:shot(name)
    if label == "Power" then
      assert(d:scene().lens:active() == "power", "the Power lens is on")
      d:scene().lens:dismiss()
    else
      d:key("escape")
    end
    d:frames(3)
  end

  panel("Pantry", "pantry")
  panel("Routine", "routine")
  panel("Catalog", "catalog")
  panel("Journal", "journal")
  panel("Power", "power")
  panel("Fish guide", "guide")
  panel("Diary", "diary")

  -- The plates reopen each book where it was left.
  d:pressHud("notebook")
  d:frames(5)
  assert(d:book().current == "diary", "the Notebook reopens on the Diary, the page it was left on")
  d:shot("notebook_remembered")
  d:key("escape")
  d:frames(3)
  d:pressHud("ledger")
  d:frames(5)
  assert(d:book().current == "catalog", "the Ledger reopens on the Catalog, the page it was left on")
  d:key("escape")
  d:frames(3)

  local tx, ty = d:nearestObject("truck")
  assert(tx, "no truck on the map")
  d:clickTile(tx, ty)
  d:frames(5)
  assert(d:book().current == "truck", "the truck opens the Ledger on Truck & town")
  d:shot("truck")
  d:key("escape")
  d:frames(3)
  d:shot("homestead_after_panels")
end
