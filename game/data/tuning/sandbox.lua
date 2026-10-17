-- Sandbox save mode (D134): a slot flagged `meta.sandbox` plays the normal game with nothing costing resources
-- and no way to fail the run. The words shown to the player live in tuning.ui.sandbox.
return {
  conditionFloor = 25, -- condition the homesteader never drops below in a sandbox slot (of needs.conditionMax); hunger and cold still drain it, they just can't finish it
  freeReasons = { -- ledger removal reasons that cost nothing in a sandbox slot (the stock stays as it is); losses such as selling, spoilage and predators are not costs, so they still happen
    plant = true, -- seeds sown
    fishing = true, -- bait used
    eat = true, -- the daily meal
    drink = true, -- the daily drink from the cistern stock
    melt = true, -- wood burned to melt snow for the canteen
    burn = true, -- wood burned for the night's warmth
    feeder = true, -- hen feed
    manger = true, -- goat hay
    generator = true, -- generator fuel
    fuel = true, -- fuel a machine burns per run
    process = true, -- recipe inputs
    bucket = true, -- cistern water into the bucket
    drip = true, -- drip irrigation water
    sprinkler = true, -- sprinkler water
    order = true, -- catalog orders
    bought = true, -- town pickups
  },
}
