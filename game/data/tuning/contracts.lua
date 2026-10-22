-- The contracts board (D197, #372, docs/PLAN_DEPTH.md §9.2). First guesses; the balance pass (M9) sets them.
return {
  offersPerWeek = 3, -- board offers rolled each week (standing orders come on top)
  deadlineMin = 3, -- days an offer stays open at the least
  deadlineMax = 10, -- days an offer stays open at the most
  rewardMult = 1.5, -- reward = the good's base value x units x this: a contract pays above the market and never saturates it
  rewardPerDone = 0.05, -- added to rewardMult for each contract finished (reputation, a count): higher-paying offers
  doneCap = 10, -- contracts finished past which reputation adds no more pay
  standingMult = 1.3, -- reward multiplier of a standing order (steady, a little under a board offer); reputation adds to it too
  standingDays = 7, -- days a standing order stays open (it renews each week)
}
