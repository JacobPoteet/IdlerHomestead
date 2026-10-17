-- The roguelite loop around runs (GDD §4.3): failure, search & rescue, recovery, new land.
-- Pure logic on save-slot data; no rendering. Scenes call these at the right moments.
--
-- Slot data = { meta, run }. When Condition hits zero:
--   Run.fail(data, world)   summarize the run into meta.career.history, finish the study in
--                           progress, set meta.recovery, and discard data.run.
--   (rescue + recovery scenes: review the run, maybe pick the one free study)
--   Run.freeStudy(...)      learn one idea for free during recovery
--   Run.startNext(data)     count the new run and clear recovery; the session then generates new
--                           land because data.run is nil.
--
-- meta.career = { runs = number of the current run (1-based), history = { summary, ... },
--                 best = { years = most years survived by any run, yearIncome = best year's sales income } }
-- A summary also carries yearsSurvived (full game years completed: the year counter minus one, so dying in
-- year 3 is 2), bestYearIncome (the most sales income, in $, in one game year of the run, D117) and, from
-- the second run on, newBest = { years = bool, yearIncome = bool } (strictly beat the slot's earlier best).
-- A summary also carries greatWinter (bool, D117): the run lived through the Great Winter to the thaw; the
-- slot's best keeps it as career.best.greatWinter (true once any run did).
-- meta.recovery = { summary, finishedStudy = itemId?, freeStudyUsed = bool } while recovering.

local Calendar = require("src.sim.systems.calendar")
local Established = require("src.sim.systems.established")
local Events = require("src.core.events")
local Ftue = require("src.sim.systems.ftue")
local Income = require("src.sim.systems.income")
local Journal = require("src.sim.systems.journal")
local Wardrobe = require("src.sim.systems.wardrobe")

local Run = {}

--- The slot's career record, created on first use.
function Run.career(meta)
  meta.career = meta.career or { runs = 1, history = {} }
  meta.career.best = meta.career.best or { years = 0, yearIncome = 0 }
  return meta.career
end

--- Which run this is (1 for a brand-new slot).
function Run.number(meta)
  return Run.career(meta).runs
end

--- A world-like view of the slot's knowledge for Journal calls between runs (no run state).
function Run.metaWorld(ctx, meta)
  return { meta = meta, registry = ctx.registry, tuning = ctx.tuning, events = ctx.events or Events.new() }
end

--- What this run amounted to: { run, days, year, season, dayOfSeason, notes = { noteId, ... } }.
function Run.summary(world)
  local now = Calendar.now(world)
  local run = Run.number(world.meta)
  local notes = {}
  for _, def in ipairs(world.registry:all("notes")) do
    local info = Journal.noteInfo(world, def.id)
    if info and info.run == run then
      notes[#notes + 1] = def.id
    end
  end
  return {
    run = run,
    days = now.day,
    year = now.year,
    season = now.season,
    dayOfSeason = now.dayOfSeason,
    yearsSurvived = now.year - 1,
    bestYearIncome = (Income.best(world)),
    greatWinter = Established.survived(world.tuning, now.year), -- lived through the Great Winter (D117, #277)
    notes = notes,
  }
end

--- What finished the run (D99): `depleted` is the needs.depleted payload { hunger, cold, shelter } (the
--- last day's shortfalls, 0..1, `thirst` in units of thirstDamage, and the shelter id of the night). Returns
--- { kind, shelter } where kind is "thirst" (water was the biggest cause), "cold", "hunger", "both" (neither
--- damage at least twice the other) or "unknown" (no payload).
function Run.cause(tuning, depleted)
  if not depleted or depleted.hunger == nil then
    return { kind = "unknown" }
  end
  local hunger = tuning.needs.hungerDamage * (depleted.hunger or 0)
  local cold = tuning.needs.coldDamage * (depleted.cold or 0)
  local thirst = tuning.needs.thirstDamage * (depleted.thirst or 0)
  if thirst > hunger and thirst > cold then
    return { kind = "thirst", shelter = depleted.shelter or nil }
  end
  local both = tuning.ui.failure.bothRatio
  local kind = "unknown"
  if hunger > 0 and cold > 0 and hunger < cold * both and cold < hunger * both then
    kind = "both"
  elseif cold > hunger then
    kind = "cold"
  elseif hunger > 0 then
    kind = "hunger"
  end
  return { kind = kind, shelter = depleted.shelter or nil }
end

--- The next shelter rung above `shelterId` as an object definition, or nil at the top (or unknown).
function Run.nextRung(registry, shelterId)
  local rank = shelterId and registry:has("objects", shelterId) and registry:get("objects", shelterId).shelterRank
  local best
  for _, def in ipairs(registry:all("objects")) do
    if def.shelter and rank and (def.shelterRank or 0) > rank and (not best or def.shelterRank < best.shelterRank) then
      best = def
    end
  end
  return best
end

--- The rescue's words for a cause (pure; D99, #216): { icon, line, hint, page? }. `line` names what
--- failed and where the night was spent, `hint` points at the journal page or the next rung.
function Run.failureText(registry, tuning, cause)
  local t = tuning.ui.failure
  local shelter = cause.shelter
    and registry:has("objects", cause.shelter)
    and registry:get("objects", cause.shelter).name:lower()
  if cause.kind == "cold" or cause.kind == "both" then
    local next = Run.nextRung(registry, cause.shelter)
    local line = shelter and string.format(cause.kind == "both" and t.bothIn or t.coldIn, shelter)
      or (cause.kind == "both" and t.both or t.cold)
    local hint = next and string.format(t.coldNext, next.name:lower()) or t.coldTop
    return { icon = "icon_cold", line = line, hint = hint, page = "shelter" }
  elseif cause.kind == "thirst" then
    return { icon = "icon_water", line = t.thirst, hint = t.thirstHint }
  elseif cause.kind == "hunger" then
    return { icon = "icon_food", line = t.hunger, hint = t.hungerHint }
  end
  return { icon = "icon_unknown", line = t.unknown, hint = t.unknownHint }
end

--- The one suggestion on the first recovery of a slot (D99, #173): a first change for the next run.
function Run.firstChange(registry, tuning, cause)
  local t = tuning.ui.failure
  if cause.kind == "cold" or cause.kind == "both" then
    local next = Run.nextRung(registry, cause.shelter)
    return next and string.format(t.firstColdNext, next.name:lower()) or t.firstColdTop
  elseif cause.kind == "thirst" then
    return t.firstThirst
  elseif cause.kind == "hunger" then
    return t.firstHunger
  end
  return t.firstUnknown
end

--- The progress table of the recovery screen (D117, #275), words from tuning.ui.progress:
--- { first = bool, columns = { label, ... }, rows = { { label, cells = { text, ... }, newBest = bool }, ... } }.
--- Column 1 is this run, 2 the previous run and 3 the slot's best (both left out on a slot's first run).
--- `summary` is the run being reviewed (the last of the history).
function Run.progressTable(tuning, career, summary)
  local t = tuning.ui.progress
  local history = career.history
  local previous = history[#history - 1]
  local first = previous == nil
  local best = career.best or { years = 0, yearIncome = 0 }
  local flags = summary.newBest or {}
  local function row(label, format, field, bestField, flag)
    local cells = { string.format(format, summary[field] or 0) }
    if not first then
      cells[2] = string.format(format, previous[field] or 0)
      cells[3] = string.format(format, best[bestField])
    end
    return { label = label, cells = cells, newBest = flag == true }
  end
  local columns = { t.colThis }
  if not first then
    columns[2], columns[3] = t.colPrevious, t.colBest
  end
  local rows = {
    row(t.yearsLabel, t.yearsFormat, "yearsSurvived", "years", flags.years),
    row(t.incomeLabel, t.incomeFormat, "bestYearIncome", "yearIncome", flags.yearIncome),
  }
  -- The Great Winter row (D117, #277) shows once the slot has lived through one; before that it is no news.
  if summary.greatWinter or best.greatWinter then
    local g = tuning.ui.greatWinter
    local function cell(done)
      return done and g.surviveYes or g.surviveNo
    end
    local cells = { cell(summary.greatWinter) }
    if not first then
      cells[2], cells[3] = cell(previous.greatWinter), cell(best.greatWinter)
    end
    rows[#rows + 1] = { label = g.surviveLabel, cells = cells, newBest = false }
  end
  return { first = first, columns = columns, rows = rows }
end

--- The slot screen's journal line from a slot header, or nil when the header has no figures.
--- Whole percent, rounded down so 100% means everything is known; never names a node.
function Run.journalLine(tuning, header)
  if not header or not header.journalTotal or header.journalTotal <= 0 then
    return nil
  end
  local pct = math.floor((header.journalKnown or 0) * 100 / header.journalTotal)
  return string.format(tuning.ui.progress.journalLine, pct)
end

--- The run is over (Condition hit zero). Records it and discards the run state. `depleted` is the
--- needs.depleted payload (optional: tools that end a run without it record an unknown cause).
function Run.fail(data, world, depleted)
  assert(not data.meta.sandbox, "a sandbox slot never fails a run (D134)")
  local summary = Run.summary(world)
  summary.cause = Run.cause(world.tuning, depleted)
  local career = Run.career(data.meta)
  -- Beating the slot's best earns a marker on the recovery screen; the first run has nothing to beat.
  if #career.history > 0 then
    summary.newBest = {
      years = summary.yearsSurvived > career.best.years,
      yearIncome = summary.bestYearIncome > career.best.yearIncome,
    }
  end
  career.best.greatWinter = career.best.greatWinter or summary.greatWinter or nil
  career.best.years = math.max(career.best.years, summary.yearsSurvived)
  career.best.yearIncome = math.max(career.best.yearIncome, summary.bestYearIncome)
  career.history[#career.history + 1] = summary
  Wardrobe.evaluate(world) -- being rescued earns clothes (D152): the run's clothes are named on the recovery screen
  -- A study in progress finishes while you recover (GDD §8.1).
  local finished = Journal.finishStudy(world)
  data.meta.recovery = { summary = summary, finishedStudy = finished, freeStudyUsed = false }
  data.run = nil
  if data.header then
    data.header.recovering = true
    Journal.summarize(world, data.header)
  end
  return summary
end

function Run.isRecovering(data)
  return data.meta ~= nil and data.meta.recovery ~= nil
end

--- How many times search & rescue has found you on this slot.
function Run.rescues(meta)
  return #Run.career(meta).history
end

--- Learn one idea for free during recovery (GDD §4.3). Returns true, or false + reason.
function Run.freeStudy(data, metaWorld, id)
  local recovery = data.meta.recovery
  if not recovery then
    return false, "not recovering"
  end
  if recovery.freeStudyUsed then
    return false, "used"
  end
  local ok, reason = Journal.learnNow(metaWorld, id)
  if ok then
    recovery.freeStudyUsed = true
    recovery.freeStudy = id
    if data.header then
      Journal.summarize(metaWorld, data.header) -- the slot screen's journal line follows what was just learned
    end
  end
  return ok, reason
end

--- Leave town for new land: the next run begins when the session sees data.run == nil.
function Run.startNext(data)
  local career = Run.career(data.meta)
  career.runs = career.runs + 1
  Ftue.endForRun(data.meta) -- the tip cards are for the first run only (D69)
  data.meta.recovery = nil
  data.run = nil
  if data.header then
    data.header.recovering = nil
  end
end

return Run
