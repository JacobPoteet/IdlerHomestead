-- Progression goal (GDD §4.4, D117): the Great Winter and the "Established" soft win. The numbers are
-- placeholders until the balance pass (D95).
return {
  greatWinterYear = 3, -- game year whose winter is the Great Winter (the hardest the run has faced; may move after the balance pass)
  greatWinterBoost = 0.25, -- winter warmth-need multiplier added to the run's previous worst winter severity: the Great Winter is at least that harsh
  surfaces = { -- things Footing opens that no catalog definition can flag, listed on the Progress panel after the flagged catalog items; each is gated in code (the board by Contracts.isOpen, D197). Tiers are not here: they open by Journal notes and contracts, not Footing (D198). Words only, no balance value
    "Contracts board",
  },
  gate = { -- the words for something that opens at Footing (D164, #343); catalog rows, item cards and the Journal read these
    reason = "Opens at Footing", -- why it cannot be bought yet (the card's Right now line, the Journal and Catalog rows)
    short = "Locked", -- the disabled button in a row or card
  },
  bottleneck = { -- the "what is limiting you" line on the Progress panel (D202, #377, PLAN_DEPTH §10.2); first guesses, not balanced (M9)
    minCrops = 3, -- crops: fewest dry crops that can make water the limit (one thirsty bed is a chore, not a bottleneck)
    waterShare = 0.3, -- share (0..1) of the growing crops that must be dry at once for water to be the limit
    minJobs = 4, -- field jobs: fewest ripe crops and weedy tiles waiting that can make labour the limit
    labourShare = 0.3, -- share (0..1) of the field's tiles with a ripe crop or weeds past the pull level for labour to be the limit
    storageCategories = { "material", "food", "fish", "dairy", "preserved" }, -- resource categories whose full store counts as the storage limit (not seeds, supplies or animals); words only, no balance value
    marketCategories = { "food", "fish", "dairy", "preserved" }, -- resource categories counted as spare produce for the market limit (not stone or scrap from clearing); words only
    marketLoads = 1, -- truckloads: spare produce of at least this many full truck cargoes makes the market the limit
    marketPrice = 0.7, -- price multiplier (0..1): the town paying under this for the most plentiful spare good makes the market the limit
  },
  greatWinterSnapDays = 2, -- nights; the shortest cold snap the Great Winter can have (a snap is guaranteed in every winter, this one is never the shortest)
}
