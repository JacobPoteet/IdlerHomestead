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
local Sleep = require("src.sim.systems.sleep")
local Actors = require("src.sim.systems.actors")
local Grid = require("src.sim.grid")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")
local Inventory = require("src.sim.systems.inventory")
local Tasks = require("src.sim.systems.tasks")
local Weather = require("src.sim.systems.weather")
local Food = require("src.sim.systems.food")

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
  Spoilage.ageStock(world, "radish", Spoilage.shelfLife(world, "radish"))
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

T.test("study: progresses only while the homesteader sleeps, then the item is known", function()
  local world = newWorld(1)
  local learned = collect(world, "journal.learned")
  world.meta.journal.notes.first_catch = { day = 1 }
  world.meta.journal.notes.fish_spoil = { day = 1 }
  T.truthy(Journal.study(world, "smoker"))
  setTime(world, 1, 9)
  run(world, HOUR * 4)
  T.eq(Journal.progress(world, "smoker"), 0, "no study during the day")
  -- Two spring nights in bed at the reference length finish a 2-night study.
  local nights = reg:get("catalog", "smoker").studyNights
  local bed, wake = Sleep.bedtimeHours(world)
  T.eq(wake + 24 - bed, tun.study.nightHours, "a spring night in bed is the reference length")
  setTime(world, 1, bed)
  run(world, HOUR * (24 - bed + wake))
  T.near(Journal.progress(world, "smoker"), 1 / nights, 0.01)
  T.eq(Journal.status(world, "smoker"), "studying")
  setTime(world, 2, bed)
  run(world, HOUR * (24 - bed + wake) + 1)
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

-- Sleep -----------------------------------------------------------------------------------

local function nearTruck(world, actor)
  local truck = world.state.land.truck
  local tx, ty = Grid.coords(world.state.grid, truck)
  return math.abs(actor.x - tx) <= 2.5 and math.abs(actor.y - ty) <= 1.5
end

T.test("sleep: the homesteader goes to bed in the truck and wakes at sunrise", function()
  local world = newWorld(4)
  world.control = "idle"
  local started, woke = collect(world, "sleep.started"), collect(world, "sleep.woke")
  local hs = Actors.homesteader(world)
  local bed, wake = Sleep.bedtimeHours(world)
  setTime(world, 1, bed - 1)
  run(world, HOUR * 0.5)
  T.falsy(hs.asleep, "still up in the evening")
  setTime(world, 1, bed)
  run(world, HOUR * 2)
  T.truthy(hs.asleep, "in bed")
  T.eq(#started, 1)
  T.truthy(nearTruck(world, hs), "sleeps at the truck")
  T.eq(hs.job, nil, "no routine work at night")
  setTime(world, 2, wake - 0.1)
  run(world, HOUR * 0.5)
  T.falsy(hs.asleep, "up at sunrise")
  T.eq(#woke, 1)
end)

T.test("sleep: a player order wakes the homesteader, who then goes back to bed", function()
  local world = newWorld(4)
  local hs = Actors.homesteader(world)
  local bed = Sleep.bedtimeHours(world)
  setTime(world, 1, bed)
  run(world, HOUR * 2)
  T.truthy(hs.asleep)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local target
  for r = 3, 8 do
    local i = Grid.index(grid, sx, sy + r)
    if Grid.inBounds(grid, sx, sy + r) and Grid.walkable(world, i) then
      target = i
      break
    end
  end
  T.truthy(target, "found somewhere to walk")
  T.truthy(Actors.order(world, hs, target))
  run(world, 0.1)
  T.falsy(hs.asleep, "woken by the order")
  run(world, HOUR * 1.5)
  T.truthy(hs.asleep, "back in bed once the order is done")
end)

T.test("sleep: winter means a longer night in bed", function()
  local world = newWorld(1)
  local bed, wake = Sleep.bedtimeHours(world)
  setTime(world, tun.time.daysPerSeason * 3 + 1, 12)
  local wbed, wwake = Sleep.bedtimeHours(world)
  T.truthy(wwake + 24 - wbed > wake + 24 - bed + 3)
end)

-- Wood & warmth -----------------------------------------------------------------------

local function objectAnchor(world, id)
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == id then
      return anchor
    end
  end
end

-- A world with no fuel in stock (the starting kit carries some firewood).
local function noFuelWorld(seed)
  local world = newWorld(seed)
  for _, res in ipairs(reg:all("resources")) do
    if res.heat then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  return world
end

local function dayIn(season)
  for n, s in ipairs(tun.time.seasons) do
    if s == season then
      return (n - 1) * tun.time.daysPerSeason + 2
    end
  end
end

T.test("wood: the starting kit has a campfire, and wood is the one fuel (D104)", function()
  local world = newWorld(2)
  T.truthy(objectAnchor(world, "campfire"))
  T.falsy(objectAnchor(world, "chopping_block"), "no chopping block any more")
  T.falsy(reg:has("resources", "firewood"))
  T.falsy(reg:has("resources", "seasoned_firewood"))
  T.eq(Needs.fuelId(world), "wood")
  local fuels = 0
  for _, res in ipairs(reg:all("resources")) do
    if res.heat then
      fuels = fuels + 1
    end
  end
  T.eq(fuels, 1)
  for _, cat in ipairs(reg:all("task_categories")) do
    T.truthy(cat.id ~= "fuel", "the split category is gone")
  end
  T.falsy((pcall(Tasks.get, world, "split_wood")), "and so is the split task")
end)

T.test("warmth: cold nights burn wood; nothing to burn costs condition", function()
  local world = noFuelWorld(2)
  local warmed = collect(world, "needs.warmed")
  setTime(world, dayIn("autumn") + 4, 12) -- late autumn
  local need = Needs.warmthNeeded(world)
  T.truthy(need > 0, "autumn nights need a fire")
  local perWood = Needs.warmthPerWood(world)
  T.near(perWood, reg:get("resources", "wood").heat * reg:get("objects", "campfire").heatSource.efficiency, 1e-9)
  local logs = math.ceil(need / perWood - 1e-9)
  Ledger.add(world, "wood", logs + 5)
  T.eq(Needs.warm(world), 0)
  T.eq(Ledger.get(world, "wood"), 5, "just enough logs burn")
  T.eq(warmed[1].burned, logs)
  T.truthy(Journal.hasNote(world, "first_fire"))
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  local before = world.state.needs.condition
  T.eq(Needs.warm(world), 1)
  T.eq(world.state.needs.condition, before - tun.needs.coldDamage)
  T.truthy(Journal.hasNote(world, "cold_night"))
end)

T.test("warmth: summer needs no fire; without a heat source wood doesn't help", function()
  local world = newWorld(2)
  setTime(world, dayIn("summer"), 12)
  T.eq(Needs.warmthNeeded(world), 0)
  T.eq(Needs.warm(world), 0)
  setTime(world, dayIn("winter"), 12)
  Grid.removeObject(world, objectAnchor(world, "campfire"))
  Ledger.add(world, "wood", 20)
  T.eq(Needs.warm(world), 1, "no fire to burn it in")
  T.eq(Ledger.get(world, "wood"), 24, "the wood is not burned (4 from the kit)")
end)

-- D104: the seasonal curve --------------------------------------------------------------------

--- The warmth a night needs at severity 1: the curve, before severity, snap and insulation.
local function curve(season, day)
  return Weather.baseWarmth(newWorld(2), season, day)
end

T.test("warmth curve: summer is zero, spring and autumn partial, winter large (D104)", function()
  local peak = tun.needs.warmthPeak
  for d = 1, tun.time.daysPerSeason do
    T.eq(curve("summer", d), 0, "summer day " .. d)
  end
  local function mean(season)
    local sum = 0
    for d = 1, tun.time.daysPerSeason do
      sum = sum + curve(season, d)
    end
    return sum / tun.time.daysPerSeason
  end
  T.truthy(mean("spring") > 0 and mean("spring") < peak * 0.5, "spring is partial")
  T.truthy(mean("autumn") > 0 and mean("autumn") < peak * 0.5, "autumn is partial")
  T.truthy(mean("winter") > peak * 0.7, "winter is large")
  T.near(curve("winter", 3), peak, 1e-9, "deep winter is the full peak")
  T.truthy(mean("autumn") < mean("winter") and mean("spring") < mean("winter"))
  -- Smooth: no night differs from the next by more than half the peak, across the year wrap too.
  local previous = curve("winter", tun.time.daysPerSeason)
  for _, season in ipairs(tun.time.seasons) do
    for d = 1, tun.time.daysPerSeason do
      local now = curve(season, d)
      T.truthy(math.abs(now - previous) <= peak / 2 + 1e-9, season .. d .. " jumps")
      previous = now
    end
  end
end)

T.test("warmth curve: severity, cold snap and shelter insulation scale the curve (D37, D82)", function()
  local world = newWorld(9)
  local w = Weather.winter(world)
  local first = dayIn("winter") - 1
  setTime(world, first + 3, 12) -- winter day 4, outside any snap unless the roll puts one there
  local day = Calendar.now(world).dayOfSeason
  local snap = Weather.isColdSnap(world)
  local expected = Weather.baseWarmth(world, "winter", day) * w.severity * (snap and tun.weather.snapMultiplier or 1)
  T.near(Needs.warmthNeeded(world), expected * Shelter.insulation(world), 1e-9)
  -- Spring and autumn ignore severity (the winter's roll is a winter thing).
  setTime(world, dayIn("autumn") + 3, 12)
  T.near(Weather.warmthNeed(world), Weather.baseWarmth(world, "autumn", Calendar.now(world).dayOfSeason), 1e-9)
end)

T.test("warmth: an uncovered spring night costs health through the fed-and-warm rules (D104)", function()
  local world = noFuelWorld(2)
  setTime(world, 1, 12) -- the first spring day: the thaw still bites
  T.truthy(Needs.warmthNeeded(world) > 0, "spring has a real need")
  Ledger.add(world, "canned_food", 10)
  world.state.needs.condition = 50
  Needs.daily(world)
  T.truthy(world.state.needs.condition < 50, "no wood, a cold night, a fed day: health falls")
  -- With wood the same night costs nothing and the fed, warm day restores condition.
  local warm = noFuelWorld(2)
  setTime(warm, 1, 12)
  Ledger.add(warm, "canned_food", 10)
  Ledger.add(warm, "wood", 10)
  warm.state.needs.condition = 50
  Needs.daily(warm)
  T.truthy(warm.state.needs.condition > 50, "covered, fed: recovery")
end)

T.test("wood: the base cap holds without a woodshed and each shed raises it (D104)", function()
  local world = noFuelWorld(2)
  local base = reg:get("resources", "wood").capacity
  T.eq(Ledger.capacity(world, "wood"), base, "no shed: the base cap (the shack no longer stores wood)")
  Ledger.add(world, "wood", base + 20)
  T.eq(Ledger.get(world, "wood"), base, "added wood stops at the cap")
  T.truthy(Ledger.isFull(world, "wood"))
  Inventory.addObject(world, "woodshed")
  local spot
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "woodshed", i) then
      spot = i
      break
    end
  end
  T.truthy(Inventory.place(world, "woodshed", spot))
  local shed = reg:get("objects", "woodshed").storage.wood
  T.eq(Ledger.capacity(world, "wood"), base + shed, "one shed")
  Ledger.add(world, "wood", shed)
  T.eq(Ledger.get(world, "wood"), base + shed)
  T.falsy(reg:get("objects", "woodshed").station, "it is dry storage, not a station")
end)

T.test("wood outlook: stock, tonight's burn and nights left, one accessor (D104)", function()
  local world = noFuelWorld(2)
  setTime(world, dayIn("summer"), 12)
  Ledger.add(world, "wood", 10)
  local o = Needs.woodOutlook(world)
  T.eq(o.stock, 10)
  T.eq(o.perNight, 0)
  T.eq(o.nights, math.huge, "no fire in summer")
  T.eq(Needs.fuelNights(world), math.huge)
  setTime(world, dayIn("winter"), 12)
  o = Needs.woodOutlook(world)
  local need = Needs.warmthNeeded(world)
  T.truthy(need > 0)
  T.eq(o.perNight, math.ceil(need / Needs.warmthPerWood(world) - 1e-9))
  T.near(o.nights, 10 * Needs.warmthPerWood(world) / need, 1e-9)
  T.eq(Needs.fuelNights(world), o.nights)
  local stove = reg:get("objects", "wood_stove").heatSource.efficiency
  T.truthy(stove > reg:get("objects", "campfire").heatSource.efficiency)
  -- Readiness reports the same stock and a per-night figure for the winter.
  local Readiness = require("src.sim.systems.readiness")
  local r = Readiness.winter(world)
  T.eq(r.fuel.wood, 10)
  T.truthy(r.fuel.perNight >= 1)
  T.truthy(r.fuel.woodNeed >= r.fuel.perNight * 3)
end)

T.test("wood outlook: the same seed gives the same figures (determinism)", function()
  local a, b = noFuelWorld(5), noFuelWorld(5)
  setTime(a, dayIn("winter"), 12)
  setTime(b, dayIn("winter"), 12)
  Ledger.add(a, "wood", 17)
  Ledger.add(b, "wood", 17)
  T.eq(serialize.encode(Needs.woodOutlook(a)), serialize.encode(Needs.woodOutlook(b)))
  run(a, HOUR * 30)
  run(b, HOUR * 30)
  T.eq(serialize.encode(a.state.ledger), serialize.encode(b.state.ledger))
end)

T.test("warmth: a fed but cold day doesn't restore condition", function()
  local world = noFuelWorld(2)
  setTime(world, dayIn("winter"), 12)
  world.state.needs.condition = 50
  Ledger.add(world, "canned_food", 10)
  Needs.daily(world)
  T.eq(world.state.needs.condition, 50 - tun.needs.coldDamage)
end)

T.test("wood: an axe halves felling time", function()
  local world = newWorld(2)
  local clear = Tasks.get(world, "clear")
  local tree = objectAnchor(world, "tree")
  T.truthy(tree, "the plot has trees")
  local bare = clear.workTime(world, nil, tree)
  Inventory.addEquipment(world, "axe")
  T.near(clear.workTime(world, nil, tree), bare / 2, 1e-9)
end)

-- Winter ----------------------------------------------------------------------------------

--- Tick across midnight into `day` (so newDay/newSeason events fire), landing at 01:00.
local function arriveOn(world, day)
  setTime(world, day - 1, 23.5)
  run(world, HOUR * 1.5)
end

T.test("winter: each year rolls a winter, harsher as years go by", function()
  local world = newWorld(9)
  local w1 = Weather.winter(world, 1)
  T.truthy(w1.severity >= tun.weather.severityMin and w1.severity <= tun.weather.severityMax)
  T.truthy(w1.snapStart >= tun.weather.snapStartMin and w1.snapStart <= tun.weather.snapStartMax)
  local avg1, avg5 = 0, 0
  for seed = 1, 20 do
    local w = newWorld(seed)
    avg1 = avg1 + Weather.winter(w, 1).severity
    avg5 = avg5 + Weather.winter(w, 5).severity
  end
  T.truthy(avg5 > avg1, "later winters are harsher")
  T.eq(Weather.winter(world, 1), w1, "rolled once and remembered")
end)

T.test("winter: autumn reveals the forecast in pieces", function()
  local world = newWorld(9)
  local pieces = collect(world, "weather.forecast")
  local autumn = dayIn("autumn") - 1 -- day 1 of autumn
  arriveOn(world, autumn)
  T.eq(Weather.forecast(world).severity, nil, "nothing known yet")
  for d = 1, tun.time.daysPerSeason - 1 do
    arriveOn(world, autumn + d)
  end
  local f = Weather.forecast(world)
  local w = Weather.winter(world)
  T.eq(#pieces, #tun.weather.forecastDays)
  T.eq(f.severity, w.severity)
  T.eq(f.snapStart, w.snapStart)
  T.eq(f.snapDays, w.snapDays)
end)

T.test("winter: frost kills crops, nothing grows or gets planted", function()
  local world = newWorld(9)
  local frosted = collect(world, "crop.frosted")
  local grid = world.state.grid
  local tile
  for i = 1, #grid.terrain do
    if Grid.terrain(world, i).tillable and not world.occupancy[i] then
      tile = i
      break
    end
  end
  world.state.fields.tilled[tile] = true
  world.state.crops[tile] = { id = "potato", growth = 0.5, moisture = 1 }
  arriveOn(world, dayIn("winter") - 1)
  T.eq(world.state.crops[tile], nil, "the frost killed it")
  T.eq(#frosted, 1)
  T.truthy(Journal.hasNote(world, "first_frost"))
  Ledger.add(world, "seed_radish", 5)
  T.falsy(Tasks.get(world, "plant").canDo(world, Actors.homesteader(world), tile, { crop = "radish" }))
  world.state.crops[tile] = { id = "radish", growth = 0.2, moisture = 1 }
  run(world, HOUR * 6)
  T.eq(world.state.crops[tile].growth, 0.2, "no growth while frozen")
end)

T.test("winter: the cold snap multiplies the warmth need", function()
  local world = newWorld(9)
  local w = Weather.winter(world)
  local first = dayIn("winter") - 1
  setTime(world, first + w.snapStart - 2, 12)
  local normal = Needs.warmthNeeded(world)
  T.near(normal, Weather.baseWarmth(world, "winter", w.snapStart - 1) * w.severity * Shelter.insulation(world), 1e-9)
  T.falsy(Weather.isColdSnap(world))
  setTime(world, first + w.snapStart - 1, 12)
  T.truthy(Weather.isColdSnap(world))
  T.near(Needs.warmthNeeded(world), normal * tun.weather.snapMultiplier, 1e-9)
end)

T.test("winter: fishing and fetching water cut an ice hole first", function()
  local world = newWorld(9)
  setTime(world, dayIn("winter"), 12)
  local fish = Tasks.get(world, "fish")
  local water
  for i = 1, #world.state.grid.terrain do
    if world.state.grid.terrain[i] == "water" then
      water = i
      break
    end
  end
  local actor = Actors.homesteader(world)
  local cold = fish.workTime(world, actor, water)
  T.near(cold, tun.fishing.idleAttemptTime + tun.weather.iceCutTime, 1e-9)
  Weather.openHole(world, water)
  T.near(fish.workTime(world, actor, water), tun.fishing.idleAttemptTime, 1e-9)
  T.falsy(
    Weather.waterTarget(world, water + 1) and world.state.grid.terrain[water + 1] == "water" and water + 1 ~= water,
    "the routine sticks to open holes"
  )
  T.truthy(Weather.waterTarget(world, water))
end)

T.test("winter: solar output drops", function()
  local world = newWorld(9)
  setTime(world, 2, 12)
  local spring = Power.sun(world)
  setTime(world, dayIn("winter"), 12)
  T.truthy(Power.sun(world) < spring * 0.75)
end)

T.test("food: potatoes count toward the winter stock instead of being sold", function()
  local world = newWorld(9)
  Ledger.remove(world, "canned_food", Ledger.get(world, "canned_food")) -- no preserved stock
  Ledger.add(world, "potato", 50)
  Ledger.add(world, "radish", 50)
  local daily = tun.needs.dailyCalories
  local radishes = math.ceil(tun.food.defaultPantryDays * daily / reg:get("resources", "radish").calories)
  T.eq(Food.keep(world, "radish"), radishes, "radishes fill the pantry")
  T.eq(Food.surplus(world, "radish"), 50 - radishes, "and don't keep for winter")
  local potatoes = math.ceil(tun.food.defaultWinterDays * daily / reg:get("resources", "potato").calories)
  T.eq(Food.keep(world, "potato"), potatoes, "potatoes fill the winter stock")
  T.eq(Food.surplus(world, "potato"), 50 - potatoes)
end)

T.test("lighting: the authored day stretches to the season's sunrise and sunset", function()
  local Lighting = require("src.render.lighting")
  T.near(Lighting.remap(8, 8, 17, 6, 20), 6, 1e-9, "winter sunrise lands on the authored sunrise")
  T.near(Lighting.remap(17, 8, 17, 6, 20), 20, 1e-9, "winter sunset lands on the authored sunset")
  T.near(Lighting.remap(12.5, 8, 17, 6, 20), 13, 1e-9, "midday stays midday")
  T.near(Lighting.remap(0.5, 8, 17, 6, 20), 1, 1e-9, "midnight-ish maps across the night")
  local side, height = Lighting.sun(12.5, 8, 17)
  T.near(side, 0, 1e-9, "the sun is due south at midday")
  T.near(height, 1, 1e-9, "and at its highest")
  T.near(Lighting.sun(8.45, 8, 17), -0.9, 1e-9, "shadows point west in the morning")
  T.eq(Lighting.sun(20, 8, 17), nil, "no sun at night")
  T.near(Lighting.remap(10, 6, 20, 6, 20), 10, 1e-9, "spring is the authored day")
end)

T.test("forecast: words follow the revealed pieces", function()
  local Forecast = require("src.ui.forecast")
  local world = newWorld(9)
  T.eq(Forecast.summary(world), nil)
  world.state.weather.revealed[1] = 3
  local text = Forecast.summary(world)
  T.truthy(text:find("winter") and text:find("cold snap"), text)
end)

-- Perks -----------------------------------------------------------------------------------

local Stats = require("src.sim.stats")
local Inv = require("src.sim.systems.inventory")

T.test("perks content: valid references, one id space with the catalog", function()
  local sprites = require("assets.manifest").sprites
  for _, perk in ipairs(reg:all("perks")) do
    T.falsy(reg:has("catalog", perk.id), perk.id .. " collides with a catalog id")
    T.truthy(sprites[perk.icon], perk.id .. ".icon")
    for _, note in ipairs(perk.needs) do
      T.truthy(reg:has("notes", note), perk.id .. ".needs." .. note)
    end
    for res in pairs(perk.startingResources or {}) do
      T.truthy(reg:has("resources", res), perk.id .. ".startingResources." .. res)
    end
    for _, id in ipairs(perk.startingEquipment or {}) do
      T.truthy(reg:has("catalog", id) and reg:get("catalog", id).equipment, perk.id .. ".startingEquipment." .. id)
    end
  end
end)

T.test("perks: they become ideas and are studied like catalog items", function()
  local world = newWorld(3)
  world.meta.journal.notes.first_trip = { day = 1, run = 1 }
  T.eq(Journal.status(world, "charge_before_leaving"), "idea")
  local found = false
  for _, def in ipairs(Journal.ideas(world)) do
    found = found or def.id == "charge_before_leaving"
  end
  T.truthy(found, "perks are listed among ideas")
  T.truthy(Journal.study(world, "charge_before_leaving"))
  T.eq(Journal.finishStudy(world), "charge_before_leaving")
  T.eq(Journal.status(world, "charge_before_leaving"), "known")
end)

T.test("perks: known perks give head starts at the start of each run, once", function()
  local base = newWorld(3)
  local meta = { journal = { notes = {}, counts = {}, known = {}, queue = {}, progress = {} } }
  meta.journal.known.pack_axe = true
  meta.journal.known.trail_rations = true
  meta.journal.known.charge_before_leaving = true
  local world = newWorld(3, meta)
  T.truthy(Inv.hasEquipment(world, "axe"))
  T.eq(Ledger.get(world, "canned_food"), Ledger.get(base, "canned_food") + 4)
  T.eq(Power.charge(world, world.state.land.truck), reg:get("perks", "charge_before_leaving").truckCharge)
  -- Loading the same run again doesn't hand them out twice.
  local again =
    World.new({ registry = reg, tuning = tun, meta = meta }, serialize.decode(serialize.encode(world.state)))
  T.eq(Ledger.get(again, "canned_food"), Ledger.get(world, "canned_food"))
end)

T.test("perks: habits and weather sense change stats", function()
  local meta = { journal = { notes = {}, counts = {}, known = {}, queue = {}, progress = {} } }
  local world = newWorld(3, meta)
  T.eq(Stats.modifier(world, "forecastLead"), 0)
  meta.journal.known.weather_sense = true
  meta.journal.known.steady_routine = true
  meta.journal.known.good_habits = true
  T.eq(Stats.modifier(world, "forecastLead"), 2)
  T.near(Stats.modifier(world, "idleEfficiency"), 0.1, 1e-9)
  T.eq(Stats.modifier(world, "idleTakeover"), 10)
  -- Weather sense: the first forecast piece arrives two days early.
  local pieces = collect(world, "weather.forecast")
  local autumn = dayIn("autumn") - 1
  setTime(world, autumn - 1, 23.5)
  run(world, HOUR * 1.5)
  T.truthy(#pieces >= 1, "severity known on the first day of autumn")
end)
