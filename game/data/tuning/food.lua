-- Food: keep targets and surplus (GDD §6.2, D75) and spoilage.
return {
  -- D75 (#196): every sellable or edible good has a keep target; stock above it is surplus, which the
  -- roadside stand and the truck load sell. These set the automatic (default) targets for food.
  defaultPantryDays = 3, -- days of eating the automatic keep holds in fresh food
  defaultWinterDays = 10, -- days of eating the automatic keep holds for winter (preserved food, potatoes, food waiting for the smoker)
  maxKeep = 999, -- units; the highest keep target the Pantry stepper sets
  loadStationTime = 2, -- seconds of work to load a processing station (smoker)
  -- D68 (#163): the automatic keep holds a perishable only as long as it will be eaten before it
  -- spoils, so the rest is surplus for sale instead of rotting at home.
  autoPantryHorizon = 0.5, -- fraction of a food's shelf life the automatic keep may hold it (fish 2 d -> 1 d, radish 7 d -> 3.5 d)
  -- D73 (#183): shelf lives. Every harvest, catch or collection is a batch with its own age; nothing
  -- in a batch spoils until it is older than its food's shelf life, then it rots (rotShare a night).
  -- A resource is perishable when it has an entry here (by id first, then by category); preserved
  -- food (smoked fish, cheese, canned food) has none and never spoils.
  shelfLife = { -- days each perishable keeps before it starts to rot (a freezer stretches them)
    byResource = {
      radish = 7, -- days a radish keeps fresh (a week: a harvest can wait for the next truck)
      potato = 21, -- days a potato keeps (three seasons: autumn potatoes last the winter)
      egg = 14, -- days an egg keeps (two weeks)
    },
    byCategory = {
      fish = 2, -- days fresh fish keep (eat, smoke or sell it within two days)
      dairy = 2, -- days milk keeps (press it into cheese or drink it fast)
    },
  },
  rotShare = 0.5, -- share of a batch past its shelf life that rots each night (rounded up, so small batches go at once)
  -- D68/D73: how spoilage is described to the player (read through Spoilage accessors).
  spoilWarnUnits = 1, -- units of one food that will rot tonight from which the pantry and the top bar warn
}
