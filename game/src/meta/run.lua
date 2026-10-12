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
-- meta.career = { runs = number of the current run (1-based), history = { summary, ... } }
-- meta.recovery = { summary, finishedStudy = itemId?, freeStudyUsed = bool } while recovering.

local Calendar = require("src.sim.systems.calendar")
local Events = require("src.core.events")
local Ftue = require("src.sim.systems.ftue")
local Journal = require("src.sim.systems.journal")

local Run = {}

--- The slot's career record, created on first use.
function Run.career(meta)
  meta.career = meta.career or { runs = 1, history = {} }
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
    notes = notes,
  }
end

--- The run is over (Condition hit zero). Records it and discards the run state.
function Run.fail(data, world)
  local summary = Run.summary(world)
  local career = Run.career(data.meta)
  career.history[#career.history + 1] = summary
  -- A study in progress finishes while you recover (GDD §8.1).
  local finished = Journal.finishStudy(world)
  data.meta.recovery = { summary = summary, finishedStudy = finished, freeStudyUsed = false }
  data.run = nil
  if data.header then
    data.header.recovering = true
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
