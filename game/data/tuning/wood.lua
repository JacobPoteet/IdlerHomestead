-- Wood on demand (docs/PLAN_DEPTH.md F4, C8, issue #362, #65): in a hard season the standing trees give only so much
-- wood, so the winter's fuel has to be stockpiled before it freezes instead of chopped as it is burned. A mechanism
-- with first guesses, not balanced (balance waits for M9).
return {
  fellAllowance = { -- season id -> wood the trees will give in that season; a season not listed is unlimited
    winter = 24, -- wood (units) felled from standing trees in one winter, about three trees; once it is used, trees are refused until spring. Logs, brush and bought wood are not counted. Intent: winter fuel (about 60 wood a winter) comes from the store, not the axe
  },
}
