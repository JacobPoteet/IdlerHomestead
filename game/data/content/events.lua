-- Misfortune events (D169, #347, docs/PLAN_DEPTH.md §6.2): something that happens to a person living alone, answered with
-- a choice between two options that have a real trade-off, or ignored. Content only: src/sim/systems/events.lua draws,
-- offers and applies them. The demo below is the sprained ankle; the packs (B6 on) add more by data alone.
--
--   title, line      the card's title and one sentence
--   class            "body" | "home" | "land" | "visitors": the standing-order class (B5, #349)
--   when             "night" | "morning" | "day": when it is offered after the dusk draw picks it
--   bad              a misfortune: never drawn while Footing is slipped, Condition is low or the statuses are full (6.5)
--   wake             may wake the homesteader; the card never freezes time (6.3)
--   seasons          season id -> weight multiplier (absent = every season at 1; a season left out is 0)
--   minYear, cooldown (days), once (per run), weight, exposure (0..1, how much night exposure shapes the weight)
--   conditions       all must hold, checked when drawn and again when offered:
--                    weather = { kinds }, frozen = bool, status = { ids or families }, noColdNight = true
--   terms            weight terms: { weather | frozen | status, mult }, each that holds multiplies the weight
--   journalNote      note id (data/content/notes.lua) written the first time the event is offered
--   options          exactly two: { label, cost = { resource = n }?, effect, risk (qualitative words, never odds),
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
--   note = id                   Journal.write: a Field Journal note
--   chain = { id, afterDays }   a follow-up event, offered that many days later (a chain is at most tuning.events.maxChainDepth long)
--   capital = true, lesser = {} an outcome that destroys capital (the stove, devices, livestock): while Footing is slipped, or
--                               when a damage flag would pass the cap, `lesser` applies instead (a spoiled store, a damage flag)
return {
  {
    id = "sprained_ankle",
    title = "Sprained ankle",
    line = "You slip on the wet rocks by the creek and your ankle gives.",
    class = "body",
    when = "day",
    bad = true,
    wake = false,
    conditions = {},
    weight = 1,
    terms = {
      { weather = { "rain", "storm" }, mult = 3 }, -- wet rocks
      { frozen = true, mult = 2 }, -- ice
      { status = { "tired" }, mult = 2 }, -- worn out and careless
    },
    cooldown = 7,
    journalNote = "ankle_sprain",
    options = {
      {
        label = "Splint it",
        cost = { wood = 2 },
        effect = { status = "ankle_1" },
        risk = "Two wood. Slower today, gone tomorrow.",
        careful = true,
      },
      {
        label = "Power through",
        effect = { status = "ankle_2" },
        risk = "Free. Falls twice as likely for days, and it can get worse.",
        bold = true,
      },
    },
    ignore = {
      label = "Limp on",
      effect = { status = "limp", note = "limped_on" },
      risk = "Free. Work 40% slower today and tomorrow, and no worse.",
    },
  },
}
