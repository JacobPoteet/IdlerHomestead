-- Misfortune events (D169, #347, docs/PLAN_DEPTH.md §6.2): something that happens to a person living alone, answered with
-- a choice between two options that have a real trade-off, or ignored. Content only: src/sim/systems/events.lua draws,
-- offers and applies them. The body pack (B6, D173), the home pack (B7, D192) and the land pack (B8, D193) are below; the other packs add more by data alone.
--
--   title, line      the card's title and one sentence
--   class            "body" | "home" | "land" | "visitors": the standing-order class (B5, #349)
--   when             "night" | "morning" | "day": when it is offered after the dusk draw picks it
--   bad              a misfortune: never drawn while Footing is slipped, Condition is low or the statuses are full (6.5)
--   wake             may wake the homesteader; the card never freezes time (6.3)
--   seasons          season id -> weight multiplier (absent = every season at 1; a season left out is 0)
--   minYear, cooldown (days), once (per run), weight, exposure (0..1, how much night exposure shapes the weight)
--   conditions       all must hold, checked when drawn and again when offered:
--                    weather = { kinds }, frozen = bool, status = { ids or families }, noStatus = { ids or families },
--                    noColdNight = true, placed = { object ids (heat sources) }, coldNight = bool (tonight asks at least
--                    tuning.events.body.coldNightNeed), thirsty = bool (under tuning.events.body.thirstyDays of water),
--                    feet = weight class of the boots ("light" | "mid" | "heavy"), outfit = which way the clothes lean
--                    (same words, GDD 7.8), shelter = { ids of the best shelter placed ("camp", "shack") },
--                    noDamage = { damage flags that must not be open }, pipesOpen = bool (pipes that can freeze, neither frozen
--                    nor kept by lagging or a shack), planted = bool (a crop is in the ground)
--   drawConditions   the same keys, checked only when the dusk draw picks (not again when the card is offered): the trigger
--                    of an event whose cause has passed by the time it comes (a fall while Strained, a cold night)
--   fall             the weight is multiplied by the fall chance of the statuses (a bad ankle makes a fall likelier)
--   terms            weight terms: { <any condition key above>, mult }, each that holds multiplies the weight
--   journalNote      note id (data/content/notes.lua) written the first time the event is offered
--   options          exactly two: { label, cost = { resource = n }?, effect, risk (qualitative words, never odds; the card
--                    (B4, D172) says the cost and the effect in plain words itself from `cost` and `effect`, so `risk` is
--                    only how safe the choice is, e.g. "Safe. It passes by tomorrow."),
--                    careful = true? (what Careful standing orders pick, B5), bold = true? (what Bold picks) }
--   ignore           { label, effect, risk }: applies when nobody answers in the window (tuning.events.ignoreHours,
--                    never under ignoreMinSeconds of real time). Free, safe and non-escalating (6.2): no cost, no condition
--                    loss, no status that can escalate, no chain, no lasting damage. A gamble is something the player picks.
--
-- Effects (one table; every key optional):
--   status = id | { ids }       Status.apply (families escalate, the cap holds)
--   gain = { res = n }          resources gained (overflow is lost); lose = { res = n } lost, at most what is in stock
--   condition = -n              Condition lost, never under tuning.events.mercy.conditionFloor
--   flags = { name = days | true | false }   a flag for that many days (true until cleared, false clears it); Events.flag
--   damage = { names }          lasting damage flags opened (torn canvas, clogged flue), capped by mercy.maxOpenDamage; Events.repair
--   lockTiles = { count, days } planted tiles locked from work for the days; Events.tileLocked (the land packs read it)
--   damageTiles = { count, setback }  planted tiles knocked back (Crops.setBack)
--   repair = { names }          lasting damage flags mended (what a `later` outcome does to the damage that opened them)
--   freezePipes = true          the pumps and pipes freeze now until the thaw hour (Weather.freezePipes)
--   note = id                   Journal.write: a Field Journal note
--   later = { days, hour? | hours, chance?, effect }   an outcome that lands later: `hours` on, or `days` on at `hour` (default the
--                               hour it was chosen); `chance` names a key of tuning.events.chances (absent = certain), and the
--                               card says "may", never the odds. The effect takes the keys above except later, chain, capital, damage
--   chain = { id, afterDays }   a follow-up event, offered that many days later (a chain is at most tuning.events.maxChainDepth long)
--   capital = true, lesser = {} an outcome that destroys capital (the stove, devices, livestock): while Footing is slipped, or
--                               when a damage flag would pass the cap, `lesser` applies instead (a spoiled store, a damage flag)

-- BANDAGE STAND-IN (B10, #354). The plan's cleaning options cite "1 bandage or an hour of work". The first-aid kit does not
-- exist yet, so those options cost the hour of work (the `tending` status, a day of slightly slower work) and the water.
-- When the kit lands, B10 adds the bandage as the second way to pay and this stays as the price without a kit.
local HOUR_OF_WORK = "tending"

return {
  {
    id = "sprained_ankle",
    title = "Sprained ankle",
    line = "You slip on the wet rocks by the creek and your ankle gives.",
    class = "body",
    when = "day",
    bad = true,
    wake = false,
    conditions = { noStatus = { "ankle" } }, -- a bad ankle comes back as the torn ankle, not as a fresh sprain
    weight = 1,
    terms = {
      { weather = { "rain", "storm" }, mult = 3 }, -- wet rocks
      { frozen = true, mult = 2 }, -- ice
      { status = { "tired" }, mult = 2 }, -- worn out and careless
      { feet = "light", mult = 1.5 }, -- loose, light shoes (GDD 7.8)
      { feet = "heavy", mult = 0.6 }, -- heavy boots hold the ankle
    },
    cooldown = 7,
    journalNote = "ankle_sprain",
    options = {
      {
        label = "Splint it",
        cost = { wood = 2 },
        effect = { status = "ankle_1" },
        risk = "Safe. Slow today, and it passes by tomorrow.",
        careful = true,
      },
      {
        label = "Power through",
        effect = { later = { days = 1, hour = 8, effect = { status = "ankle_2" } } },
        risk = "Risky. Fine today, but a fall is likelier tomorrow, and a fall can tear it.",
        bold = true,
      },
    },
    ignore = {
      label = "Limp on",
      effect = { status = "limp", note = "limped_on" },
      risk = "Safe. It never gets worse than this.",
    },
  },
  {
    -- The fall that Power through risks: only while Strained, and a fall is likelier the worse the ankle is.
    id = "torn_ankle",
    title = "Torn ankle",
    line = "Your strained ankle gives out on the first step of the day.",
    class = "body",
    when = "morning",
    bad = true,
    wake = false,
    drawConditions = { status = { "ankle_2" } },
    fall = true,
    weight = 1.5,
    cooldown = 6,
    journalNote = "ankle_torn",
    options = {
      {
        label = "Splint it hard",
        cost = { wood = 3, canned_food = 1 }, -- the broth for the days off your feet
        effect = { status = "ankle_3b" },
        risk = "Safe. Two slow days, then it is mended.",
        careful = true,
      },
      {
        label = "Walk it off",
        effect = { status = "ankle_3", condition = -15 },
        risk = "Hard. It hurts, and it keeps you slow for three days.",
        bold = true,
      },
    },
    ignore = {
      label = "Limp on",
      effect = { status = "limp", note = "limped_on" },
      risk = "Safe. Slow for two days, and no worse.",
    },
  },
  {
    id = "festering_cut",
    title = "Festering cut",
    line = "A small cut from yesterday's work is red, hot and sore.",
    class = "body",
    when = "day",
    bad = true,
    wake = false,
    weight = 1,
    terms = {
      { status = { "tired" }, mult = 1.5 }, -- careless hands
      { weather = { "rain", "storm" }, mult = 1.3 }, -- damp, dirty work
    },
    seasons = { spring = 1, summer = 1, autumn = 1, winter = 0.5 },
    cooldown = 6,
    journalNote = "festering_cut",
    options = {
      {
        label = "Clean and bandage",
        cost = { water = 1 },
        effect = { status = HOUR_OF_WORK },
        risk = "Safe. An hour of work lost, and no infection.",
        careful = true,
      },
      {
        label = "Leave it",
        effect = { later = { days = 2, hour = 8, chance = "festerInfection", effect = { status = "infection" } } },
        risk = "Risky. It may turn infected in two days.",
        bold = true,
      },
    },
    ignore = {
      label = "Rinse it",
      effect = { status = "rinse" },
      risk = "Safe. A little slower for two days, and no infection.",
    },
  },
  {
    id = "fever_cold_night",
    title = "Fever",
    line = "You wake hot and shivering after the cold night.",
    class = "body",
    when = "morning",
    bad = true,
    wake = false,
    seasons = { spring = 0.5, autumn = 1, winter = 1.5 },
    conditions = { noColdNight = true }, -- never after a night that already cost cold damage (PLAN_DEPTH 6.5)
    drawConditions = { coldNight = true }, -- a cold night coming, judged at the dusk draw
    weight = 1,
    exposure = 0.5, -- a poor shelter makes a cold night colder
    cooldown = 8,
    journalNote = "cold_fever",
    options = {
      {
        label = "Rest a day",
        effect = { status = "rested" },
        risk = "Safe. The day's work is lost, but the fever does not take hold.",
        careful = true,
      },
      {
        label = "Work through",
        effect = {
          status = "fever",
          later = { days = 2, hour = 8, chance = "feverFlu", effect = { status = "flu", condition = -20 } },
        },
        risk = "Risky. Slow for days, and it may turn into flu.",
        bold = true,
      },
    },
    ignore = {
      label = "Shiver it off",
      effect = { status = "chill" },
      risk = "Safe. A few slow days, and no worse.",
    },
  },
  {
    id = "back_strain",
    title = "Back strain",
    line = "Your back seizes up after another heavy load.",
    class = "body",
    when = "day",
    bad = true,
    wake = false,
    weight = 0.8,
    terms = {
      { status = { "tired" }, mult = 1.5 },
    },
    -- Nothing counts a run of heavy carrying yet, so the autumn harvest and being Tired stand in for the plan's "carry streak".
    seasons = { spring = 1, summer = 1, autumn = 1.5, winter = 0.7 },
    cooldown = 6,
    journalNote = "bad_back",
    options = {
      {
        label = "Rest a few hours",
        effect = { status = "break" },
        risk = "Safe. A few hours of work lost, and the back is fine.",
        careful = true,
      },
      {
        label = "Keep hauling",
        effect = { status = "back" },
        risk = "Risky. You carry half as much for two days.",
        bold = true,
      },
    },
    ignore = {
      label = "Stretch it out",
      effect = { status = "stiff" },
      risk = "Safe. A little stiff for two days.",
    },
  },
  {
    id = "stove_burn",
    title = "Burn from the stove",
    line = "You catch your hand on the hot stove door.",
    class = "body",
    when = "morning",
    bad = true,
    wake = false,
    conditions = { placed = { "wood_stove" } }, -- stove use
    seasons = { spring = 0.7, autumn = 1, winter = 1.5 },
    weight = 0.7,
    cooldown = 6,
    journalNote = "stove_burn",
    options = {
      {
        label = "Cold water compress",
        cost = { water = 1 },
        effect = {},
        risk = "Safe. It cools at once.",
        careful = true,
      },
      {
        label = "Shrug it off",
        effect = { status = "burn" },
        risk = "Risky. Your hand is slow for two days.",
        bold = true,
      },
    },
    ignore = {
      label = "Run it under the tap",
      effect = { status = "sting" },
      risk = "Safe. A stinging hand for a day.",
    },
  },
  {
    id = "heat_exhaustion",
    title = "Heat exhaustion",
    line = "The sun is merciless and your head swims.",
    class = "body",
    when = "day",
    bad = true,
    wake = false,
    seasons = { summer = 1 },
    conditions = { weather = { "clear" } }, -- sun
    weight = 0.8,
    terms = {
      { thirsty = true, mult = 2 }, -- dehydration
      { outfit = "light", mult = 1.5 }, -- light clothes catch more sun (PLAN_DEPTH 7)
      { outfit = "heavy", mult = 0.8 },
    },
    cooldown = 5,
    journalNote = "heat_exhaustion",
    options = {
      {
        label = "Rest in the shade",
        effect = { status = "break" },
        risk = "Safe. You lose the hours around noon.",
        careful = true,
      },
      {
        label = "Push on",
        effect = {
          status = "heat",
          later = { hours = 3, chance = "heatCollapse", effect = { status = "collapsed", condition = -10 } },
        },
        risk = "Risky. You need more water, and you may collapse this afternoon.",
        bold = true,
      },
    },
    ignore = {
      label = "Slow down",
      effect = { status = "sluggish" },
      risk = "Safe. Slower for the rest of the day.",
    },
  },
  {
    id = "bad_tooth",
    title = "Bad tooth",
    line = "A tooth has been aching for days, and today it throbs.",
    class = "body",
    when = "day",
    bad = true,
    wake = false,
    minYear = 2, -- late-game flavor
    weight = 0.5,
    cooldown = 14,
    journalNote = "bad_tooth",
    options = {
      {
        label = "Willow-bark tea",
        cost = { water = 1 }, -- the kit's pain remedy is B10's; until it exists, a brew and an hour of work
        effect = { status = HOUR_OF_WORK },
        risk = "Safe. An hour of work lost, and the ache eases.",
        careful = true,
      },
      {
        label = "Tough it out",
        effect = { status = "toothache" },
        risk = "Risky. You cannot focus on study for three nights.",
        bold = true,
      },
    },
    ignore = {
      label = "Chew on the other side",
      effect = { status = "tooth_nag" },
      risk = "Safe. Study is a little harder for two nights.",
    },
  },

  -- Home pack (B7, #351, D192). The damage flags are read through systems/home.lua and mend themselves (a `later` repair), so
  -- neglect costs a few days of warmth and never more (D184). Pipe freezing itself is the weather night (D190): this is the
  -- choice event for a frozen pump in the morning.
  {
    id = "roof_leak",
    title = "Roof leak",
    line = "Rain finds a hole in the roof and drips onto the bed.",
    class = "home",
    when = "night",
    bad = true,
    wake = true,
    conditions = { weather = { "rain", "storm" }, shelter = { "camp", "shack" } },
    weight = 1,
    exposure = 0.5, -- a poor shelter leaks more
    cooldown = 8,
    journalNote = "roof_leak",
    options = {
      {
        label = "Patch it now",
        cost = { wood = 1, scrap = 1 },
        effect = {},
        risk = "Safe. The drip stops for good.",
        careful = true,
      },
      {
        label = "Set a pot",
        effect = { status = "leaky" },
        risk = "Risky. A colder, restless night.",
        bold = true,
      },
    },
    ignore = {
      label = "Move the bed",
      effect = { status = "damp" },
      risk = "Safe. A damp night, and no worse.",
    },
  },
  {
    id = "tarp_torn",
    title = "Tarp torn",
    line = "The wind gets under the camp canvas and tears a seam.",
    class = "home",
    when = "night",
    bad = true,
    wake = false,
    conditions = { shelter = { "camp" }, noDamage = { "torn_canvas" } },
    weight = 1,
    terms = {
      { weather = { "windy", "storm" }, mult = 2 },
    },
    cooldown = 8,
    journalNote = "tarp_torn",
    options = {
      {
        label = "Mend it tonight",
        cost = { wood = 1, scrap = 1 },
        effect = {},
        risk = "Safe. The canvas holds again.",
        careful = true,
      },
      {
        label = "Sleep cold",
        effect = {
          status = "draughty",
          damage = { "torn_canvas" },
          later = { days = 3, hour = 8, effect = { repair = { "torn_canvas" } } },
          lesser = { status = "draughty" },
        },
        risk = "Risky. Colder nights for a few days, until you patch it.",
        bold = true,
      },
    },
    ignore = {
      label = "Hang a blanket",
      effect = { status = "draughty" },
      risk = "Safe. One draughty night, and no worse.",
    },
  },
  {
    id = "frozen_pump",
    title = "Frozen pump",
    line = "The pump handle will not move: the line is frozen solid.",
    class = "home",
    when = "morning",
    bad = true,
    wake = false,
    seasons = { winter = 1 },
    conditions = { frozen = true, pipesOpen = true },
    weight = 0.8,
    cooldown = 6,
    journalNote = "frozen_pump",
    options = {
      {
        label = "Thaw it",
        cost = { wood = 2 },
        effect = {},
        risk = "Safe. Water flows again at once.",
        careful = true,
      },
      {
        label = "Wait for the sun",
        effect = { freezePipes = true },
        risk = "Safe. No pumped water until noon, and the wood stays.",
        bold = true,
      },
    },
    ignore = {
      label = "Use the canteen",
      effect = { freezePipes = true },
      risk = "Safe. No pumped water until noon.",
    },
  },
  {
    id = "tool_breaks",
    title = "Tool breaks",
    line = "A handle splits in the middle of the job.",
    class = "home",
    when = "day",
    bad = true,
    wake = false,
    weight = 1,
    cooldown = 6,
    journalNote = "tool_breaks",
    options = {
      {
        label = "Mend it with wood",
        cost = { wood = 1 },
        effect = { status = HOUR_OF_WORK },
        risk = "Safe. An hour of work lost, and the same tool.",
        careful = true,
      },
      {
        label = "Make do",
        effect = { status = "bare_hands" },
        risk = "Risky. Slower work for two days.",
        bold = true,
      },
    },
    ignore = {
      label = "Bind it with twine",
      effect = { status = "twine" },
      risk = "Safe. A little slower for a day.",
    },
  },
  {
    id = "flue_clogged",
    title = "Flue clogged",
    line = "Smoke rolls back out of the stove and into the room.",
    class = "home",
    when = "night",
    bad = true,
    wake = true,
    seasons = { spring = 0.5, autumn = 1, winter = 1.5 },
    conditions = { placed = { "wood_stove" }, noDamage = { "clogged_flue" } },
    weight = 0.8,
    cooldown = 8,
    journalNote = "flue_clogged",
    options = {
      {
        label = "Douse the fire",
        cost = { water = 1 },
        effect = { lose = { wood = 2 } }, -- the fuel in the firebox is wasted
        risk = "Safe. Some wood is wasted, and the flue is clear.",
        careful = true,
      },
      {
        label = "Burn it out",
        effect = {
          damage = { "clogged_flue" },
          status = "smoke",
          later = { days = 3, hour = 8, effect = { repair = { "clogged_flue" } } },
          lesser = { status = "smoke" },
        },
        risk = "Risky. Smoky air, and the stove draws badly until it clears.",
        bold = true,
      },
    },
    ignore = {
      label = "Open the windows",
      effect = { status = "airing" },
      risk = "Safe. A chillier night, and no worse.",
    },
  },

  -- Land pack (B8, #352, D193). Three mild choices about the fields and the woodlot. Nothing shrinks the farm (hornets and the
  -- creek washout are cut, D184): the worst a crop suffers is a setback in growth, never its loss, and ignoring costs a day of
  -- slightly slower work.
  {
    id = "livestock_in_field",
    title = "Livestock in the field",
    line = "A neighbor's cow has wandered through the fence and is eyeing the rows.",
    class = "land",
    when = "day",
    bad = true,
    wake = false,
    seasons = { spring = 1, summer = 1, autumn = 1 },
    conditions = { planted = true },
    weight = 1,
    cooldown = 8,
    journalNote = "livestock_in_field",
    options = {
      {
        label = "Chase it off",
        effect = { status = HOUR_OF_WORK },
        risk = "Safe. An hour of work lost, and the crops are untouched.",
        careful = true,
      },
      {
        label = "Let it graze",
        effect = { damageTiles = { count = 2, setback = 0.25 } },
        risk = "Risky. A couple of rows are nibbled back, and they grow again.",
        bold = true,
      },
    },
    ignore = {
      label = "Shoo it with a shout",
      effect = { status = "trampled" },
      risk = "Safe. A little slower for a day while you mend the gap.",
    },
  },
  {
    id = "late_frost",
    title = "Late frost",
    line = "The sky clears at dusk and the air goes still: the forecast missed a frost.",
    class = "land",
    when = "night",
    bad = true,
    wake = false,
    seasons = { spring = 1, autumn = 0.8 },
    conditions = { planted = true },
    terms = {
      { weather = { "clear" }, mult = 1.5 }, -- clear skies lose their heat
    },
    weight = 1,
    cooldown = 8,
    journalNote = "late_frost",
    options = {
      {
        label = "Light smudge fires",
        cost = { wood = 2 },
        effect = { status = HOUR_OF_WORK }, -- an hour of sitting up to feed the fires
        risk = "Safe. An hour of work lost, and the smoke holds the frost off the rows.",
        careful = true,
      },
      {
        label = "Trust the sprouts",
        effect = {
          later = { days = 1, hour = 5, chance = "lateFrost", effect = { damageTiles = { count = 3, setback = 0.3 } } },
        },
        risk = "Risky. The frost may nip some rows back, and they grow again.",
        bold = true,
      },
    },
    ignore = {
      label = "Throw sacks over a few",
      effect = { status = "cold_fingers" },
      risk = "Safe. Cold hands and a little slower work tomorrow.",
    },
  },
  {
    id = "storm_tree",
    title = "Storm-felled tree",
    line = "The wind brought a tree down at the edge of the clearing.",
    class = "land",
    when = "morning",
    bad = false,
    wake = false,
    conditions = { noStatus = { "ankle" } },
    drawConditions = { weather = { "windy", "storm" } }, -- the wind that felled it has passed by morning
    weight = 1,
    cooldown = 10,
    journalNote = "storm_tree",
    options = {
      {
        label = "Take the easy branches",
        effect = { gain = { wood = 2 } },
        risk = "Safe. A little wood, and no hard work.",
        careful = true,
      },
      {
        label = "Buck it whole",
        effect = {
          gain = { wood = 5 },
          status = HOUR_OF_WORK,
          later = { hours = 1, chance = "fellingSlip", effect = { status = "ankle_1" } },
        },
        risk = "Risky. Plenty of wood and an hour of work, and a slip may hurt your ankle.",
        bold = true,
      },
    },
    ignore = {
      label = "Leave it for now",
      effect = {},
      risk = "Safe. It lies there, and nothing is lost.",
    },
  },
}
