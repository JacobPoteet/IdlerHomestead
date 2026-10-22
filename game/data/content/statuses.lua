-- Statuses (D166, #345, docs/PLAN_DEPTH.md §7): short lists of modifiers on the homesteader. Events apply them (the body pack,
-- B6, D173); items follow; src/sim/systems/status.lua holds the rules.
-- A family is also the chip's icon (icon_status_<family>), so the one-off statuses share the family of the injury they belong to
-- and the lost-time ones (rest, tending, break, a collapse, sluggish) share "rest".
-- A few are stand-ins for lost hours (tending, break): a status lasts whole days, so an hour of work is a day of slightly
-- slower work (a share of the ~12 working hours), and a day of rest is the work-speed floor.
--   name       the chip's title
--   line       the one effect that matters, for the chip (<= ~8 words)
--   family     statuses of one family escalate (apply a second one and the severity rises), they never stack
--   severity   1.. within the family; the cap is the highest severity (no `escalatesTo`)
--   duration   days it lasts, counted at each new day after the night's draw (1 = gone tomorrow morning);
--              absent = until something clears it
--   clearedBy  "time" (the duration runs out), "rest" (a day in the shelter, Status.clearBy) or "item" (a first-aid
--              item, Status.clearBy); any status also ends by its duration when it has one
--   escalatesTo  the id of the next severity of the same family
--   modifiers  a multiplier of 1 = no effect, except conditionDrain (Condition lost each day, summed):
--              workSpeed (floored by tuning.status.minWorkSpeed), fallChance, carryCapacity (the bucket),
--              conditionRecovery (the dailyRecovery of a fed, warm day), conditionDrain, studySpeed,
--              warmthNeed (the night's warmth), waterNeed (the day's drink)
return {
  -- The ankle (sprained ankle and its escalation, PLAN_DEPTH 6.2)
  {
    id = "ankle_1",
    name = "Hobbling",
    line = "Work 50% slower today",
    family = "ankle",
    severity = 1,
    duration = 1,
    clearedBy = "time",
    escalatesTo = "ankle_2",
    modifiers = { workSpeed = 0.5 },
  },
  {
    id = "ankle_2",
    name = "Strained ankle",
    line = "Falls twice as likely",
    family = "ankle",
    severity = 2,
    duration = 1,
    clearedBy = "time",
    escalatesTo = "ankle_3",
    modifiers = { fallChance = 2 },
  },
  {
    id = "ankle_3",
    name = "Torn ankle",
    line = "Work 60% slower",
    family = "ankle",
    severity = 3,
    duration = 3,
    clearedBy = "rest",
    modifiers = { workSpeed = 0.4, fallChance = 3 },
  },
  {
    id = "ankle_3b",
    name = "Splinted ankle",
    line = "Work 60% slower, mends sooner",
    family = "ankle",
    severity = 3,
    duration = 2, -- the torn ankle, splinted: two days instead of three
    clearedBy = "rest",
    modifiers = { workSpeed = 0.4, fallChance = 3 },
  },
  {
    id = "limp",
    name = "Limping",
    line = "Work 40% slower",
    family = "limp",
    severity = 1,
    duration = 2, -- today and tomorrow (D169): the ignore outcome of the sprained ankle, free and with no way to get worse
    clearedBy = "time",
    modifiers = { workSpeed = 0.6 },
  },
  -- Fever, infection and flu (one family: a second one raises the severity)
  {
    id = "fever",
    name = "Fever",
    line = "Work 40% slower, needs more warmth",
    family = "fever",
    severity = 1,
    duration = 3,
    clearedBy = "rest",
    escalatesTo = "flu",
    modifiers = { workSpeed = 0.6, warmthNeed = 1.15, waterNeed = 1.5, conditionRecovery = 0.5 },
  },
  {
    id = "infection",
    name = "Infected cut",
    line = "Work 25% slower, needs more water",
    family = "fever",
    severity = 1,
    duration = 4,
    clearedBy = "time",
    escalatesTo = "flu",
    modifiers = { workSpeed = 0.75, waterNeed = 1.25 },
  },
  {
    id = "flu",
    name = "Flu",
    line = "Work 50% slower, needs more warmth",
    family = "fever",
    severity = 2,
    duration = 4,
    clearedBy = "rest",
    modifiers = { workSpeed = 0.5, warmthNeed = 1.2, waterNeed = 1.5, conditionRecovery = 0.5, conditionDrain = 1 },
  },
  {
    id = "chill",
    name = "Chill",
    line = "Work 20% slower",
    family = "fever",
    severity = 1,
    duration = 3, -- the ignore outcome of the fever: free, and it cannot become a flu
    clearedBy = "time",
    modifiers = { workSpeed = 0.8 },
  },
  {
    id = "rested",
    name = "Resting",
    line = "No real work, heals twice as fast",
    family = "rest",
    severity = 1,
    duration = 1, -- a day in bed: the work-speed floor (tuning.status.minWorkSpeed) for today
    clearedBy = "time",
    modifiers = { workSpeed = 0.35, conditionRecovery = 2 },
  },
  -- Back
  {
    id = "back",
    name = "Sore back",
    line = "Carries half as much",
    family = "back",
    severity = 1,
    duration = 2,
    clearedBy = "time",
    modifiers = { carryCapacity = 0.5 },
  },
  {
    id = "stiff",
    name = "Stiff back",
    line = "Carries a little less",
    family = "back",
    severity = 1,
    duration = 2, -- the ignore outcome of back strain
    clearedBy = "time",
    modifiers = { carryCapacity = 0.85 },
  },
  -- Burns and cuts
  {
    id = "burn",
    name = "Burn",
    line = "Work 20% slower",
    family = "burn",
    severity = 1,
    duration = 2,
    clearedBy = "item",
    modifiers = { workSpeed = 0.8 },
  },
  {
    id = "sting",
    name = "Stinging hand",
    line = "Work 10% slower",
    family = "burn",
    severity = 1,
    duration = 1, -- the ignore outcome of a burn
    clearedBy = "time",
    modifiers = { workSpeed = 0.9 },
  },
  {
    id = "rinse",
    name = "Sore cut",
    line = "Work 10% slower",
    family = "wound",
    severity = 1,
    duration = 2, -- the ignore outcome of a festering cut: a rinse, and no infection roll
    clearedBy = "time",
    modifiers = { workSpeed = 0.9 },
  },
  -- Lost hours (the careful side of an injury: time instead of a risk)
  {
    id = "tending",
    name = "Tending",
    line = "An hour of work lost",
    family = "rest",
    severity = 1,
    duration = 1, -- one hour of about twelve working hours
    clearedBy = "time",
    modifiers = { workSpeed = 0.92 },
  },
  {
    id = "break",
    name = "Taking a break",
    line = "A few hours of work lost",
    family = "rest",
    severity = 1,
    duration = 1, -- three hours of about twelve working hours
    clearedBy = "time",
    modifiers = { workSpeed = 0.75 },
  },
  -- Heat
  {
    id = "heat",
    name = "Overheated",
    line = "Needs 50% more water",
    family = "heat",
    severity = 1,
    duration = 1,
    clearedBy = "time",
    modifiers = { waterNeed = 1.5 },
  },
  {
    id = "collapsed",
    name = "Collapsed",
    line = "Work 50% slower",
    family = "rest",
    severity = 1,
    duration = 1,
    clearedBy = "time",
    modifiers = { workSpeed = 0.5 },
  },
  {
    id = "sluggish",
    name = "Sluggish",
    line = "Work 30% slower",
    family = "rest",
    severity = 1,
    duration = 1, -- the ignore outcome of heat exhaustion
    clearedBy = "time",
    modifiers = { workSpeed = 0.7 },
  },
  -- Teeth
  {
    id = "toothache",
    name = "Toothache",
    line = "Studies 30% slower",
    family = "tooth",
    severity = 1,
    duration = 3,
    clearedBy = "time",
    modifiers = { studySpeed = 0.7 },
  },
  {
    id = "tooth_nag",
    name = "Sore tooth",
    line = "Studies 10% slower",
    family = "tooth",
    severity = 1,
    duration = 2, -- the ignore outcome of a bad tooth
    clearedBy = "time",
    modifiers = { studySpeed = 0.9 },
  },
  -- Home events (B7, D192): the cost of a leak, a torn tarp, a smoky flue and a broken tool. Each family is its own, so the ignore
  -- outcome of an event (the mild one) never lands on, or escalates, the one an option picks.
  {
    id = "leaky",
    name = "Leaky roof",
    line = "Colder night, studies 20% slower",
    family = "leak",
    severity = 1,
    duration = 1, -- the night's pot and moved bed: one night
    clearedBy = "time",
    modifiers = { warmthNeed = 1.2, studySpeed = 0.8 },
  },
  {
    id = "damp",
    name = "Damp bed",
    line = "Studies 10% slower",
    family = "damp",
    severity = 1,
    duration = 1, -- the ignore outcome of a roof leak
    clearedBy = "time",
    modifiers = { studySpeed = 0.9 },
  },
  {
    id = "draughty",
    name = "Draughty bed",
    line = "A slightly colder night",
    family = "draught",
    severity = 1,
    duration = 1, -- the ignore outcome of a torn tarp, and the lesser form of the torn canvas
    clearedBy = "time",
    modifiers = { warmthNeed = 1.1 },
  },
  {
    id = "smoke",
    name = "Smoky air",
    line = "Slower Condition recovery",
    family = "smoke",
    severity = 1,
    duration = 2,
    clearedBy = "time",
    modifiers = { conditionRecovery = 0.85 },
  },
  {
    id = "airing",
    name = "Airing the room",
    line = "A slightly colder night",
    family = "airing",
    severity = 1,
    duration = 1, -- the ignore outcome of a clogged flue
    clearedBy = "time",
    modifiers = { warmthNeed = 1.1 },
  },
  {
    id = "bare_hands",
    name = "Making do",
    line = "Work 15% slower",
    family = "makedo",
    severity = 1,
    duration = 2, -- a broken tool worked around with the spare or bare hands
    clearedBy = "time",
    modifiers = { workSpeed = 0.85 },
  },
  {
    id = "twine",
    name = "Twine-bound tool",
    line = "Work 10% slower",
    family = "twine",
    severity = 1,
    duration = 1, -- the ignore outcome of a broken tool
    clearedBy = "time",
    modifiers = { workSpeed = 0.9 },
  },
  {
    id = "tired",
    name = "Run down",
    line = "Slower work, slower study",
    family = "tired",
    severity = 1,
    clearedBy = "rest",
    modifiers = { workSpeed = 0.9, studySpeed = 0.8, conditionRecovery = 0.75 },
  },
}
