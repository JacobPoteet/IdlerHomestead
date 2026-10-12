local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Journal = require("src.sim.systems.journal")
local Fishing = require("src.sim.systems.fishing")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Spoilage = require("src.sim.systems.spoilage")
local Power = require("src.sim.systems.power")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local HOUR = tun.time.dayLength / 24

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

--- Jump the clock to `hour` on day `day` (1-based) without ticking systems.
local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function collect(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

-- Content ---------------------------------------------------------------------------------

T.test("journal content: notes and learnable items are consistent", function()
  local sprites = require("assets.manifest").sprites
  for _, note in ipairs(reg:all("notes")) do
    T.truthy(#note.line > 0, note.id .. ".line")
    T.truthy(sprites[note.icon], note.id .. ".icon is in the asset manifest")
  end
  for _, item in ipairs(reg:all("catalog")) do
    if item.starter then
      T.eq(item.needs, nil, item.id .. ": starter items need no notes")
    else
      T.truthy(item.needs and #item.needs > 0, item.id .. ": learnable items list the notes they need")
      T.truthy(item.studyNights and item.studyNights > 0, item.id .. ".studyNights")
      for _, note in ipairs(item.needs) do
        T.truthy(reg:has("notes", note), item.id .. ".needs." .. note)
      end
    end
  end
end)

-- Notes -----------------------------------------------------------------------------------

T.test("notes: written from events, once, into meta", function()
  local meta = {}
  local world = newWorld(1, meta)
  local notes = collect(world, "journal.note")
  T.falsy(Journal.hasNote(world, "first_catch"))
  Fishing.land(world, "creek_chub", 12, "active")
  T.truthy(Journal.hasNote(world, "first_catch"))
  T.eq(meta.journal.notes.first_catch.day, 1)
  Fishing.land(world, "creek_chub", 12, "active")
  T.eq(#notes, 1, "a note is only written once")
end)

T.test("notes: count rules need several matching events", function()
  local world = newWorld(1)
  for _ = 1, 9 do
    Fishing.land(world, "creek_chub", 12, "idle")
  end
  T.falsy(Journal.hasNote(world, "ten_fish"))
  Fishing.land(world, "creek_chub", 12, "idle")
  T.truthy(Journal.hasNote(world, "ten_fish"))
end)

T.test("notes: match rules filter on event fields", function()
  local world = newWorld(1)
  Ledger.add(world, "radish", 40)
  Spoilage.daily(world)
  T.truthy(Journal.hasNote(world, "produce_spoils"))
  T.falsy(Journal.hasNote(world, "fish_spoil"), "radishes aren't fish")
  world.events:emit("needs.ate", { calories = 2000, shortfall = 0 })
  T.falsy(Journal.hasNote(world, "went_hungry"))
  world.events:emit("needs.ate", { calories = 500, shortfall = 0.75 })
  T.truthy(Journal.hasNote(world, "went_hungry"))
end)

T.test("notes: a lost fish is reported", function()
  local world = newWorld(1)
  Fishing.lose(world, "brook_trout", "slipped")
  T.truthy(Journal.hasNote(world, "one_got_away"))
end)

-- Ideas & study ----------------------------------------------------------------------------

T.test("ideas: an item becomes an idea once all its notes exist", function()
  local world = newWorld(1)
  local ideas = collect(world, "journal.idea")
  T.eq(Journal.status(world, "smoker"), "unknown")
  T.eq(Journal.status(world, "basic_rod"), "known", "starter items are known")
  T.falsy(Journal.needsChoice(world))
  Fishing.land(world, "creek_chub", 12, "active")
  T.eq(Journal.status(world, "smoker"), "unknown", "still needs a spoiled fish")
  world.events:emit("food.spoiled", { resource = "creek_chub", category = "fish", amount = 1 })
  T.eq(Journal.status(world, "smoker"), "idea")
  T.eq(#ideas, 1)
  T.eq(ideas[1].item, "smoker")
  T.truthy(Journal.needsChoice(world), "an idea and nothing queued prompts a choice")
  T.eq(Market.cannotBuy(world, "smoker", false), "unknown", "ideas can't be bought yet")
end)

T.test("study: the queue only takes ideas and has a limit", function()
  local world = newWorld(1)
  local j = world.meta.journal
  T.eq(select(2, Journal.study(world, "smoker")), "not an idea")
  T.eq(select(2, Journal.study(world, "basic_rod")), "known")
  for _, note in ipairs(reg:all("notes")) do
    j.notes[note.id] = { day = 1 }
  end
  local learnable = Journal.ideas(world)
  T.truthy(#learnable > tun.study.queueSize, "enough ideas to fill the queue")
  for n = 1, tun.study.queueSize do
    T.truthy(Journal.study(world, learnable[n].id))
  end
  T.eq(select(2, Journal.study(world, learnable[1].id)), "queued")
  T.eq(select(2, Journal.study(world, learnable[tun.study.queueSize + 1].id)), "queue full")
  T.eq(Journal.status(world, learnable[1].id), "studying")
  T.eq(Journal.status(world, learnable[2].id), "queued")
  T.truthy(Journal.unqueue(world, learnable[1].id))
  T.eq(Journal.status(world, learnable[2].id), "studying")
  T.eq(Journal.status(world, learnable[1].id), "idea")
end)

T.test("study: progresses only at night, then the item is known and buyable", function()
  local world = newWorld(1)
  local learned = collect(world, "journal.learned")
  world.meta.journal.notes.first_catch = { day = 1 }
  world.meta.journal.notes.fish_spoil = { day = 1 }
  T.truthy(Journal.study(world, "smoker"))
  setTime(world, 1, 9)
  run(world, HOUR * 4)
  T.eq(Journal.progress(world, "smoker"), 0, "no study during the day")
  -- Two spring nights (sunset to sunrise) at the reference night length finish a 2-night study.
  local nights = reg:get("catalog", "smoker").studyNights
  local sunrise, sunset = Calendar.daylight(world)
  T.eq(sunrise + 24 - sunset, tun.study.nightHours, "spring nights are the reference length")
  setTime(world, 1, sunset)
  run(world, HOUR * (24 - sunset + sunrise))
  T.near(Journal.progress(world, "smoker"), 1 / nights, 0.01)
  T.eq(Journal.status(world, "smoker"), "studying")
  setTime(world, 2, sunset)
  run(world, HOUR * (24 - sunset + sunrise) + 1)
  T.eq(Journal.status(world, "smoker"), "known")
  T.eq(#learned, 1)
  T.eq(#Journal.queue(world), 0)
  Ledger.add(world, "money", 100)
  T.eq(Market.cannotBuy(world, "smoker", false), nil, "known items are in the catalog")
end)

T.test("study: winter nights are longer and study faster", function()
  local function oneNight(dayOfYear)
    local world = newWorld(1)
    world.meta.journal.notes.first_catch = { day = 1 }
    world.meta.journal.notes.fish_spoil = { day = 1 }
    Journal.study(world, "smoker")
    setTime(world, dayOfYear, 12)
    run(world, tun.time.dayLength)
    return Journal.progress(world, "smoker")
  end
  local winterDay = tun.time.daysPerSeason * 3 + 2
  T.truthy(oneNight(winterDay) > oneNight(2) * 1.2, "winter night beats a spring night")
end)

T.test("study: knowledge outlives the run; an unfinished study finishes on recovery", function()
  local meta = {}
  local world = newWorld(1, meta)
  meta.journal.notes.first_catch = { day = 1 }
  meta.journal.notes.fish_spoil = { day = 1 }
  meta.journal.notes.first_trip = { day = 1 }
  Journal.study(world, "smoker")
  Journal.study(world, "used_panel")
  T.eq(Journal.finishStudy(world), "smoker")
  -- Next run, same slot: a fresh world on the same meta (after a save round-trip).
  local nextMeta = serialize.decode(serialize.encode(meta))
  local nextRun = newWorld(2, nextMeta)
  T.eq(Journal.status(nextRun, "smoker"), "known")
  T.eq(Journal.status(nextRun, "used_panel"), "studying")
  T.truthy(Journal.hasNote(nextRun, "first_trip"))
  local notes = collect(nextRun, "journal.note")
  Fishing.land(nextRun, "creek_chub", 10, "active")
  T.eq(#notes, 0, "notes from earlier runs aren't written again")
end)

-- Seasons ---------------------------------------------------------------------------------

T.test("calendar: daylight follows the season; solar follows daylight", function()
  local world = newWorld(1)
  world.state.grid.objects = {} -- no panels needed; sun() is just the curve
  setTime(world, 1, 12)
  T.falsy(Calendar.isNight(world))
  local winterDay = tun.time.daysPerSeason * 3 + 1
  local winterSunrise = tun.time.daylight.winter[1]
  setTime(world, winterDay, winterSunrise - 0.5)
  T.truthy(Calendar.isNight(world), "still dark on a winter morning")
  T.eq(Power.sun(world), 0)
  setTime(world, 1, winterSunrise - 0.5)
  T.truthy(Power.sun(world) > 0, "spring sun is already up")
end)
