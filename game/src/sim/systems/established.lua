-- "Established", the soft win (GDD §4.4, D117, #277): living through the Great Winter, the winter of
-- tuning.progress.greatWinterYear (see weather.lua), to the first thaw. The thaw is the first day after the
-- frozen seasons end. Play goes on afterwards and nothing mechanical is awarded.
--
-- Emits "progress.established" { year = the winter's year, run, first } at every run's thaw of that year;
-- `first` is true for the one that marks the slot. The slot mark is
--   meta.established = { run = run number, year = the winter's year, seen = bool (the card was shown) }
-- set once per slot, by the first run to get there. The celebration card shows once, from the mark's `seen`
-- flag, so it survives a save and load between the thaw and the card.

local Calendar = require("src.sim.systems.calendar")
local Weather = require("src.sim.systems.weather")

local Established = {}

--- The slot's mark ({ run, year, seen }), or nil while the slot has not been established.
function Established.mark(meta)
  return meta.established
end

--- True while the slot has an Established mark whose celebration card has not been shown yet.
function Established.cardDue(meta)
  return meta.established ~= nil and not meta.established.seen
end

--- The card has been shown: it never shows again on this slot.
function Established.cardShown(meta)
  if meta.established then
    meta.established.seen = true
  end
end

--- Did the run reach the first thaw after the Great Winter? `year` is the game year the run has reached.
function Established.survived(tuning, year)
  return year > tuning.progress.greatWinterYear
end

function Established.init(world)
  world.events:on("calendar.newSeason", function(e)
    local seasons = world.tuning.time.seasons
    local index = Calendar.now(world).seasonIndex
    local previous = seasons[(index - 2) % #seasons + 1]
    if Weather.isFrozenSeason(world, e.season) or not Weather.isFrozenSeason(world, previous) then
      return -- not the first thaw
    end
    -- Winter belongs to the year it started in; a thaw in the first season of a year closes the year before.
    local year = index == 1 and e.year - 1 or e.year
    if not Weather.isGreatWinterYear(world, year) then
      return
    end
    local meta = world.meta
    local run = meta.career and meta.career.runs or 1
    local first = meta.established == nil
    if first then
      meta.established = { run = run, year = year, seen = false }
    end
    world.events:emit("progress.established", { year = year, run = run, first = first })
  end)
end

return Established
