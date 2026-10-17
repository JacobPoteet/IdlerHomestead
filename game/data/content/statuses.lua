-- Statuses (D166, #345, docs/PLAN_DEPTH.md §7): short lists of modifiers on the homesteader. Nothing applies one yet
-- (events and items do, phase B3 on); src/sim/systems/status.lua holds the rules.
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
  {
    id = "ankle_1",
    name = "Hobbling",
    line = "Work 20% slower",
    family = "ankle",
    severity = 1,
    duration = 1,
    clearedBy = "time",
    escalatesTo = "ankle_2",
    modifiers = { workSpeed = 0.8, fallChance = 1.5 },
  },
  {
    id = "ankle_2",
    name = "Strained ankle",
    line = "Falls twice as likely",
    family = "ankle",
    severity = 2,
    duration = 3,
    clearedBy = "time",
    escalatesTo = "ankle_3",
    modifiers = { workSpeed = 0.7, fallChance = 2 },
  },
  {
    id = "ankle_3",
    name = "Torn ankle",
    line = "Work 50% slower",
    family = "ankle",
    severity = 3,
    duration = 6,
    clearedBy = "rest",
    modifiers = { workSpeed = 0.5, fallChance = 3, carryCapacity = 0.8 },
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
  {
    id = "fever",
    name = "Fever",
    line = "Needs more warmth and water",
    family = "fever",
    severity = 1,
    duration = 3,
    clearedBy = "rest",
    modifiers = { workSpeed = 0.8, warmthNeed = 1.15, waterNeed = 1.5, conditionRecovery = 0.5 },
  },
  {
    id = "back",
    name = "Sore back",
    line = "Carries a lot less",
    family = "back",
    severity = 1,
    duration = 4,
    clearedBy = "time",
    modifiers = { workSpeed = 0.85, carryCapacity = 0.6 },
  },
  {
    id = "burn",
    name = "Burn",
    line = "Loses Condition each day",
    family = "burn",
    severity = 1,
    duration = 3,
    clearedBy = "item",
    modifiers = { workSpeed = 0.9, conditionDrain = 1 },
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
