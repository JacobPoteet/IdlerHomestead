-- The night's account (D70, #159): what the homesteader slept, studied, ate, burned and lost between
-- going to bed and waking at sunrise, collected from events so the scene can show one morning report
-- instead of silence. It owns no gameplay: it only listens.
--
-- Events are gathered into an open ledger as they happen (midnight's food and fuel, a raid, the
-- night's spoilage). The ledger closes at the first tick after sunrise with the homesteader out of
-- bed, not when a player order wakes them in the small hours ("stay up", D35): that stretch is added
-- to the same night. A night the player never slept at all carries into the next report.
--
-- State: world.state.nightly = { open = { ... }, ready = { ... }? }
--   open  = { ate = { [food id] = n }, burned = { [fuel id] = n }, calories, hungry (shortfall sum 0..),
--             cold (shortfall sum), warmthNeeded, electric, raided = { [id] = n }, caught (mice the cat
--             caught), killed (hens lost to a fox), killedGoats (goats lost to one), stopped (fox raids turned back), spoil = { lost, total }?,
--             learned = { ids }, slept (game seconds), sleepAt (game seconds, set while in bed),
--             study = { id, name, from, total }?, condition0? }
--   ready = the closed ledger plus { day, hours, study = { id, name, from, to, total, learned }?,
--           conditionFrom, conditionTo } until the scene has shown it.
-- Emits "night.report" { day } when a report is ready.

local Calendar = require("src.sim.systems.calendar")
local Journal = require("src.sim.systems.journal")
local Needs = require("src.sim.systems.needs")
local Sleep = require("src.sim.systems.sleep")

local Nightly = {}

local function blank()
  return {
    ate = {},
    burned = {},
    calories = 0,
    hungry = 0,
    cold = 0,
    warmthNeeded = 0,
    electric = 0,
    raided = {},
    caught = 0,
    killed = 0,
    killedGoats = 0,
    stopped = 0,
    learned = {},
    slept = 0,
  }
end

local function state(world)
  return world.state.nightly
end

local function open(world)
  return state(world).open
end

local function add(map, id, n)
  map[id] = (map[id] or 0) + n
end

--- Is a morning report waiting to be shown?
function Nightly.hasReport(world)
  return state(world).ready ~= nil
end

--- The waiting report, or nil. It stays until Nightly.take.
function Nightly.report(world)
  return state(world).ready
end

--- Take the waiting report (nil if none), so it is shown once.
function Nightly.take(world)
  local st = state(world)
  local report = st.ready
  st.ready = nil
  return report
end

--- The bedtime line's facts: the study in progress ({ id, name, nights, total }) or nil.
function Nightly.bedtime(world)
  return Journal.studying(world)
end

local function close(world)
  local st = state(world)
  local acc = open(world)
  local now = Calendar.now(world)
  local report = acc
  report.day = now.day
  report.hours = report.slept / Calendar.hourLength(world)
  report.conditionTo = Needs.condition(world)
  report.conditionFrom = report.condition0 or report.conditionTo
  report.condition0 = nil
  report.sleepAt = nil
  local study = report.study
  if study then
    local learned = false
    for _, id in ipairs(report.learned) do
      if id == study.id then
        learned = true
      end
    end
    local head = Journal.studying(world)
    study.learned = learned
    study.to = learned and study.total or (head and head.id == study.id and head.nights or study.from)
  end
  st.ready = report
  st.open = blank()
  world.events:emit("night.report", { day = now.day })
end

function Nightly.init(world)
  local st = world.state.nightly or {}
  st.open = st.open or blank()
  world.state.nightly = st
  local ev = world.events

  ev:on("ledger.changed", function(e)
    if e.delta < 0 then
      if e.reason == "eat" then
        add(open(world).ate, e.id, -e.delta)
      elseif e.reason == "burn" then
        add(open(world).burned, e.id, -e.delta)
      end
    end
  end)
  ev:on("needs.ate", function(e)
    local acc = open(world)
    acc.calories = acc.calories + e.calories
    acc.hungry = acc.hungry + e.shortfall
  end)
  ev:on("needs.warmed", function(e)
    local acc = open(world)
    acc.cold = acc.cold + e.shortfall
    acc.warmthNeeded = acc.warmthNeeded + e.needed
    acc.electric = acc.electric + e.electric
  end)
  ev:on("food.spoilReport", function(e)
    open(world).spoil = { lost = e.lost, total = e.total }
  end)
  ev:on("mice.raided", function(e)
    local acc = open(world)
    for id, n in pairs(e.lost) do
      add(acc.raided, id, n)
    end
  end)
  ev:on("mice.caught", function()
    local acc = open(world)
    acc.caught = acc.caught + 1
  end)
  ev:on("animals.predator", function(e)
    local acc = open(world)
    if e.stopped then
      acc.stopped = acc.stopped + 1
    else
      local field = e.kind == "goats" and "killedGoats" or "killed"
      acc[field] = acc[field] + e.killed
    end
  end)
  ev:on("journal.learned", function(e)
    local acc = open(world)
    acc.learned[#acc.learned + 1] = e.item
  end)
  ev:on("sleep.started", function()
    local acc = open(world)
    if not acc.sleepAt then
      acc.sleepAt = Calendar.elapsed(world)
    end
    if acc.condition0 == nil then
      acc.condition0 = Needs.condition(world)
    end
    if not acc.study then
      local head = Journal.studying(world)
      if head then
        acc.study = { id = head.id, name = head.name, from = head.nights, total = head.total }
      end
    end
  end)
  ev:on("sleep.woke", function()
    local acc = open(world)
    if acc.sleepAt then
      acc.slept = acc.slept + (Calendar.elapsed(world) - acc.sleepAt)
      acc.sleepAt = nil
    end
    -- The report closes at sunrise (Nightly.tick), not here: a player order can wake the homesteader
    -- in the small hours, and the night is not over then.
  end)
end

--- Close the night once the homesteader is out of bed and the bedtime hours are over.
function Nightly.tick(world)
  local acc = open(world)
  if acc.condition0 ~= nil and not acc.sleepAt and not Sleep.isBedtime(world) then
    close(world)
  end
end

return Nightly
