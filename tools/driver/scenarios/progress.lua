-- Progress metrics (D117, #275): the recovery screen with years survived and best year's income on a
-- slot's first run (one column, nothing to beat) and on a later run (previous run and slot best, with a
-- "New best!" marker), and the slot screen with the journal completion line. The deaths are raised on
-- the event bus and the clock is set to the year reached; sales are the real sale events. The scenes,
-- the run loop and the saved header are the real ones.
local Save = require("src.core.save")
local serialize = require("src.core.serialize")

local function setDay(world, day)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + 0.5) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function yearStart(world, year)
  local t = world.tuning.time
  return (year - 1) * t.daysPerSeason * #t.seasons + 1
end

local function die(d, year, income)
  local world = d:world()
  setDay(world, yearStart(world, year) + 5)
  if income > 0 then
    world.events:emit("market.sold", { earnings = income, units = 10 })
  end
  world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
  d:frames(4)
  d:frames(150, 1 / 30)
  d:click(40, 40) -- the rescue: a tap moves on
  d:frames(4)
end

return function(d)
  -- Two other slots with a journal line, planted in the in-memory store.
  local other = Save.newSlotData("Hilltop")
  other.header = { playtime = 5400, year = 2, season = "autumn", journalKnown = 14, journalTotal = 60 }
  d.backend.files["slot2.sav"] = serialize.encode(other)
  local fresh = Save.newSlotData("Creek bend")
  fresh.header = { playtime = 300, year = 1, season = "spring", journalKnown = 9, journalTotal = 60 }
  d.backend.files["slot3.sav"] = serialize.encode(fresh)

  d:newGame()
  die(d, 2, 85)
  d:shot("recovery_first_run") -- one column and the "first run" line
  d:press("Head out")
  d:frames(4)
  d:advance(0.1)

  die(d, 3, 210)
  d:shot("recovery_later_run") -- previous run, slot best and the new-best markers
  d:press("Head out")
  d:frames(4)
  d:advance(0.1)

  die(d, 2, 40)
  d:shot("recovery_not_a_best") -- a worse run: no markers

  -- The slot screen: the recovering slot and the two planted ones, each with its journal line.
  d.game.app:switch(require("src.scenes.slots").new())
  d:frames(4)
  d:shot("slots_journal_line")
end
