-- Progression goal (GDD §4.4, D117): the Great Winter and the "Established" soft win. The numbers are
-- placeholders until the balance pass (D95).
return {
  greatWinterYear = 3, -- game year whose winter is the Great Winter (the hardest the run has faced; may move after the balance pass)
  greatWinterBoost = 0.25, -- winter warmth-need multiplier added to the run's previous worst winter severity: the Great Winter is at least that harsh
  greatWinterSnapDays = 2, -- nights; the shortest cold snap the Great Winter can have (a snap is guaranteed in every winter, this one is never the shortest)
}
