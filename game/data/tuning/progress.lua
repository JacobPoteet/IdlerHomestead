-- Progression goal (GDD §4.4, D117): the Great Winter and the "Established" soft win. The numbers are
-- placeholders until the balance pass (D95).
return {
  greatWinterYear = 3, -- game year whose winter is the Great Winter (the hardest the run has faced; may move after the balance pass)
  greatWinterBoost = 0.25, -- winter warmth-need multiplier added to the run's previous worst winter severity: the Great Winter is at least that harsh
  surfaces = { -- gated things with no content definition yet, listed on the Progress panel after the flagged catalog items; the slice that builds one flags its content (`requiresFooting`, D164) and deletes its name here; words only, no balance value
    "Contracts board",
    "Land purchases",
    "Year charter",
    "Tiered upgrades",
    "Levy clock",
  },
  gate = { -- the words for something that opens at Footing (D164, #343); catalog rows, item cards and the Journal read these
    reason = "Opens at Footing", -- why it cannot be bought yet (the card's Right now line, the Journal and Catalog rows)
    short = "Locked", -- the disabled button in a row or card
  },
  greatWinterSnapDays = 2, -- nights; the shortest cold snap the Great Winter can have (a snap is guaranteed in every winter, this one is never the shortest)
}
