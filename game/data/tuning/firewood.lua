-- Firewood (GDD §4.2, §5.3). Heat per unit lives on the resource; heat sources on the object.
return {
  splitTime = 3, -- seconds of work to split one batch of wood at the chopping block
  splitBatch = 2, -- wood split per batch (1 wood -> 1 green firewood)
  keepWood = 4, -- wood the routine leaves unsplit (smoker fuel)
  splitFrom = "wood", -- resource id split at the chopping block
  splitInto = "firewood", -- resource id it becomes (1 for 1)
}
