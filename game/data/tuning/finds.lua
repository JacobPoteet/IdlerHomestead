-- Finds (GDD §8.4, D53): occasional "pick 1 of 3" offers. A daily roll queues an offer; it is
-- shown once the homesteader is not resting or fishing by hand.
return {
  rollHour = 9, -- in-game hour of the daily roll, and the earliest an offer appears (never in the dark morning)
  chancePerDay = 0.2, -- chance (0..1) each day's roll queues an offer, once the cooldown has passed
  cooldownDays = 4, -- days after one offer is taken before the next can be queued (the roll still happens)
  firstDay = 3, -- no offer before this day of the run, so the opening hours stay a clean learning loop
  choices = 3, -- options in an offer (fewer are shown only if fewer finds are eligible)
  lackBoost = 3, -- weight multiplier for a find whose `lacks` condition is true (steers offers to what the player is missing)
  busyJobs = { "fish" }, -- task ids the homesteader is working on that delay an offer (resting always does)
  historyLimit = 20, -- most picks remembered in the run state (older ones are dropped)
}
