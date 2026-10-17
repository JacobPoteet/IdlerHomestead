-- Misfortune events (D169, #347, docs/PLAN_DEPTH.md §6.2, §6.3, §6.5): the cadence, the quiet start, the ignore window and
-- the mercy rules of the event engine (src/sim/systems/events.lua). The events themselves are content
-- (data/content/events.lua). First guesses, reasoned and NOT balanced: the balance pass is M9.
-- The night slot, the exposure units and the pity timer are shared with the night-threat framework (C1, #355):
-- exposure itself is tuning.night.exposure.
return {
  enabled = true, -- boolean: the engine draws and offers events at all (the balance harness turns it off unless a choice policy is asked for)
  firstNight = 3, -- day number: no event is drawn on a night before this one (the quiet start, PLAN_DEPTH 6.3: the opening is a clean learning loop)
  badFromDay = 10, -- day number: no bad event before Footing is earned or this day, whichever comes first (Q10: the first events must not land on a fragile run); mild luck events may still come from firstNight
  chancePerNight = 0.3, -- chance (0..1) that a night's draw produces one event or threat, before exposure, year and pity (about one in three nights, PLAN_DEPTH 6.3)
  yearScale = { 0.7, 1 }, -- multiplier on the chance, by year (the last entry holds for later years): a gentler year 1 (PLAN_DEPTH 6.3)
  maxChance = 0.85, -- chance (0..1): ceiling on a night's chance however exposure, year and pity stack, so a night is never certain
  pityNights = 4, -- nights in a row with no event or threat after which the chance starts to rise (a turned-away threat counts, PLAN_DEPTH 6.5)
  pityBoost = 0.15, -- chance (0..1) added for each night without an event past pityNights, so a long quiet spell ends
  badCooldownNights = 2, -- nights after a bad event or a threat that landed during which no event is drawn (a turned-away threat starts none)
  perDayBudget = 1, -- events at most offered on one calendar day, however they were scheduled (a chain follow-up or a postponed one waits a day)
  maxChainDepth = 2, -- follow-up events a chain may link in a row, so a chain can never run on
  ignoreHours = 4, -- in-game hours a card waits for an answer before the ignore outcome applies (about 53 s at 1x), counted only while the player is present
  ignoreMinSeconds = 45, -- real seconds a card waits at least, counted only while the player is present, so a fast speed cannot skip a card unseen (PLAN_DEPTH 6.3)
  hours = { -- in-game hour of day a scheduled event is offered
    morning = 8, -- a morning event: after sunrise in every season (winter sunrise is 8)
    day = 13, -- a day event: the middle of the working day
    night = 1, -- a night event: hours after the homesteader's bedtime begins
  },
  chances = { -- chance (0..1) of a delayed outcome landing (an event's `later.chance` names one); the card says "may" and never the odds (PLAN_DEPTH 6.2)
    festerInfection = 0.4, -- a cut left alone turns infected two mornings on (PLAN_DEPTH 6.2: 40 percent)
    feverFlu = 0.3, -- a fever worked through turns into flu two mornings on (30 percent)
    heatCollapse = 0.35, -- pushing on in the heat ends in a collapse that afternoon (35 percent)
  },
  body = { -- the triggers of the body events (PLAN_DEPTH 6.2, 7)
    coldNightNeed = 4, -- warmth units (needs.warmthPeak is 8): a coming night that asks at least this much is cold enough to bring a fever, half a deep-winter night
    thirstyDays = 2, -- days of drinking water in hand under which the homesteader counts as dry, which doubles the weight of heat exhaustion
  },
  ordersPerk = "rules_of_thumb", -- journal perk id: standing orders (Careful, Bold) apply only once it is known; until then every class reads as Ask me (PLAN_DEPTH 6.4, B5)
  historyLimit = 20, -- events remembered in the run state's history (older ones are dropped)
  mercy = { -- the rules that keep events from snowballing (PLAN_DEPTH 6.5)
    conditionFloor = 15, -- Condition points: an event outcome never takes Condition under this (never the killing blow)
    lowCondition = 30, -- Condition points: no event is offered while Condition is under this
    slippedThreatScale = 0.5, -- multiplier (0..1) on a night threat's strength while Footing is slipped (read by the threat framework, C1)
    maxOpenDamage = 2, -- lasting damage flags (torn canvas, wrecked fence, clogged flue) open at once; at the cap a damaging outcome is swapped for its lesser form
    maxWarmthMultiplier = 2.0, -- ratio: statuses and events together never lift a night's warmth need above this multiple of the season's base need (or above what the weather and shelter already ask)
  },
}
