-- Growing-season threats and yearly escalation (GDD §4.1, §7.9, D67): the seeded schedule, the
-- weather weighting (#97), countermeasures, drought, warnings, notes and saves.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Threats = require("src.sim.systems.threats")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local YEAR = DPS * #tun.time.seasons
local SUMMER, AUTUMN = DPS + 1, 2 * DPS + 1

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function force(world, kind)
  world.state.weather.sky.days[1] = kind
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

--- Replace this year's schedule with one threat (white box: lets a test pick the threat and day).
local function only(world, id, start, days)
  local year = math.floor((start - 1) / YEAR) + 1
  world.state.threats.years[year] = {
    {
      id = id,
      start = start,
      days = days or 1,
      status = "waiting",
      warned = false,
      rollDay = 0,
      struck = false,
      lost = 0,
      damaged = 0,
      saved = 0,
      broken = false,
    },
  }
  return world.state.threats.years[year][1]
end

--- Plant `n` crops (growth `growth`, moist) on free tillable tiles. Returns the tiles.
local function plant(world, n, growth)
  local tiles = {}
  for i = 1, #world.state.grid.terrain do
    if #tiles >= n then
      break
    end
    if Grid.terrain(world, i).tillable and not world.occupancy[i] then
      world.state.crops[i] = { id = "radish", growth = growth or 0.5, moisture = 1 }
      tiles[#tiles + 1] = i
    end
  end
  return tiles
end

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- Run the threats system alone from (day, hour) for `hours` in-game hours.
local function run(world, day, hour, hours)
  setTime(world, day, hour)
  local ticks = math.floor(hours * tun.time.dayLength / 24 / STEP + 0.5)
  for _ = 1, ticks do
    world.state.calendar.elapsed = world.state.calendar.elapsed + STEP
    Threats.tick(world, STEP)
  end
end

-- Schedule ------------------------------------------------------------------------------------------

T.test("threats: the yearly schedule is deterministic per seed and differs between seeds", function()
  local function plan(seed)
    local world = newWorld(seed)
    local out = {}
    for year = 1, 5 do
      for _, e in ipairs(Threats.schedule(world, year)) do
        out[#out + 1] = string.format("%d:%s@%d+%d", year, e.id, e.start, e.days)
      end
    end
    return table.concat(out, " ")
  end
  T.eq(plan(7), plan(7))
  local differs = false
  for seed = 8, 14 do
    differs = differs or plan(seed) ~= plan(7)
  end
  T.truthy(differs, "other seeds roll other schedules")
end)

T.test("threats: their own stream leaves the sky, winters and land untouched", function()
  local a, b = newWorld(4), newWorld(4)
  for year = 1, 4 do
    Threats.schedule(a, year)
  end
  T.same(a.state.weather.sky, b.state.weather.sky)
  T.same(Weather.winter(a, 1), Weather.winter(b, 1))
  T.eq(serialize.encode(a.state.grid), serialize.encode(b.state.grid))
end)

T.test("threats: year 1 is gentle and late; later years bring more and stronger threats", function()
  local cfg = tun.threats
  for year = 2, 6 do
    T.truthy(Threats.count(newWorld(1), year) >= Threats.count(newWorld(1), year - 1), "count never drops")
    T.truthy(Threats.strength(newWorld(1), year) >= Threats.strength(newWorld(1), year - 1), "strength never drops")
  end
  T.eq(Threats.count(newWorld(1), 1), cfg.count[1])
  T.truthy(Threats.strength(newWorld(1), 1) < Threats.strength(newWorld(1), 3), "year 3 is harder than year 1")
  T.truthy(Threats.strength(newWorld(1), 50) <= cfg.maxStrength, "strength is capped")
  local total = { 0, 0, 0 }
  for seed = 1, 30 do
    local world = newWorld(seed)
    for year = 1, 3 do
      local list = Threats.schedule(world, year)
      total[year] = total[year] + #list
      for n, e in ipairs(list) do
        local def = reg:get("threats", e.id)
        T.truthy(def.minYear <= year, e.id .. " respects minYear")
        if year == 1 then
          T.truthy(e.start >= SUMMER, "no threat in the first spring")
        end
        local yearStart = (year - 1) * YEAR
        T.truthy(e.start > yearStart and e.start + e.days - 1 <= yearStart + YEAR, "inside its year")
        if n > 1 then
          local prev = list[n - 1]
          T.truthy(e.start > prev.start + prev.days - 1 + cfg.gapDays, "threats do not overlap")
        end
      end
    end
  end
  T.truthy(total[1] < total[2] and total[2] < total[3], "more threats each year")
end)

T.test("threats: winters get longer cold snaps from year 2 on (year 1 unchanged)", function()
  local grow = tun.threats.winter
  local world = newWorld(3)
  T.truthy(Weather.winter(world, 1).snapDays <= tun.weather.snapDaysMax, "year 1 snap in the base range")
  local extra3 = math.min(grow.maxExtraSnapDays, math.floor(grow.snapDaysPerYear * 2))
  T.truthy(extra3 > 0, "tuning adds nights by year 3")
  for seed = 1, 10 do
    local w = newWorld(seed)
    T.truthy(Weather.winter(w, 3).snapDays >= tun.weather.snapDaysMin + extra3, "year 3 snap is longer")
  end
end)

-- Weather weighting (#97) -----------------------------------------------------------------------------

T.test("threats: hail odds follow Weather.threat, storms bring it", function()
  local world = newWorld(2)
  force(world, "clear")
  local clear = Threats.strikeChance(world, "hail", 0)
  force(world, "windy")
  local windy = Threats.strikeChance(world, "hail", 0)
  force(world, "storm")
  local storm = Threats.strikeChance(world, "hail", 0)
  T.truthy(clear < windy and windy < storm, "clear < windy < storm")
  T.truthy(storm > 0.9, "a storm day in hail season almost always hails")
  T.eq(Threats.strikeChance(world, "locusts", 0), nil, "locusts are not weather-driven")
  -- Over many seeds, hail lands on stormy days far more often than their share of days.
  local stormStrikes, strikes = 0, 0
  for seed = 1, 60 do
    local w = newWorld(seed)
    local e = only(w, "hail", SUMMER + 1, 4)
    for day = SUMMER + 1, SUMMER + 4 do
      force(w, day % 3 == 0 and "storm" or "clear")
      run(w, day, 0, 24)
      if e.struck then
        strikes = strikes + 1
        stormStrikes = stormStrikes + (day % 3 == 0 and 1 or 0)
        break
      end
    end
  end
  T.truthy(strikes > 0 and stormStrikes / strikes > 0.6, "most hail falls on storm days")
end)

T.test("threats: the outlook shows a hail risk on a forecast storm day", function()
  local world = newWorld(5)
  only(world, "hail", SUMMER + 2, 3)
  local sky = world.state.weather.sky
  setTime(world, SUMMER, 8)
  sky.first = SUMMER
  sky.days = { "clear", "clear", "clear", "storm", "clear", "clear", "clear", "clear" }
  Threats.tick(world, STEP)
  local out = Threats.outlook(world)
  T.eq(#out, 1, "the warned threat is listed")
  T.eq(out[1].id, "hail")
  T.eq(out[1].active, false)
  T.eq(out[1].inDays, 2)
  T.eq(out[1].riskIn, 3, "the storm day is the risky one")
  T.truthy(out[1].risk > 0.9)
end)

-- Effects ---------------------------------------------------------------------------------------------

T.test("threats: locusts kill a share of crops, scaled by the year's strength", function()
  local world = newWorld(1)
  local e = only(world, "locusts", YEAR + SUMMER + 3, 1) -- year 2
  plant(world, 40)
  local ended = collect(world, "threat.ended")
  run(world, YEAR + SUMMER + 3, 0, 24)
  T.eq(#ended, 1)
  T.truthy(e.lost > 0, "some crops were lost")
  T.eq(40 - e.lost, count(world.state.crops))
  local share = reg:get("threats", "locusts").damage.share * Threats.strength(world, 2)
  T.truthy(e.lost < 40 * share * 1.8 and e.lost > 40 * share * 0.3, "about the scaled share: " .. e.lost)
  T.eq(e.status, "done")
end)

T.test("threats: a countermeasure saves crops (same seed, same rolls)", function()
  local function lostWith(netting)
    local world = newWorld(9)
    local e = only(world, "hail", SUMMER + 2, 1)
    plant(world, 40, 1)
    if netting then
      Inventory.addEquipment(world, "hail_netting")
    end
    force(world, "storm")
    run(world, SUMMER + 2, 0, 24)
    T.truthy(e.struck, "the storm brought hail")
    return e
  end
  local bare, netted = lostWith(false), lostWith(true)
  T.truthy(bare.damaged > 0)
  T.truthy(netted.damaged < bare.damaged, "netting turns hail aside")
  T.eq(netted.damaged + netted.saved, bare.damaged, "every crop the netting saved would have been hit")
  T.eq(bare.saved, 0)
end)

T.test("threats: hail knocks crops back but does not kill them; early frost spares ripe crops", function()
  local world = newWorld(2)
  local e = only(world, "hail", SUMMER + 2, 1)
  plant(world, 30, 1)
  force(world, "storm")
  run(world, SUMMER + 2, 0, 24)
  T.eq(count(world.state.crops), 30, "nothing killed")
  local unripe = 0
  for _, crop in pairs(world.state.crops) do
    unripe = unripe + (crop.growth < 1 and 1 or 0)
  end
  T.eq(unripe, e.damaged)

  local frost = newWorld(2)
  local f = only(frost, "early_frost", AUTUMN + 3, 1)
  plant(frost, 20, 1)
  run(frost, AUTUMN + 3, 0, 24)
  T.eq(f.lost, 0, "ripe crops survive an early frost")
  T.eq(count(frost.state.crops), 20)
end)

T.test("threats: nothing in the ground means no effect, but the threat still comes and goes", function()
  local world = newWorld(4)
  local e = only(world, "locusts", YEAR + SUMMER + 3, 1)
  local struck, ended, lost = collect(world, "threat.struck"), collect(world, "threat.ended"), collect(world, "crop.lost")
  run(world, YEAR + SUMMER + 3, 0, 24)
  T.eq(#struck, 1)
  T.eq(#ended, 1)
  T.eq(#lost, 0)
  T.eq(e.lost + e.damaged + e.saved, 0)
  T.eq(count(world.state.crops), 0)
  T.truthy(Journal.hasNote(world, "locust_swarm"), "the strike writes its note")
  T.truthy(Journal.isIdea(world, "row_covers"), "which makes the countermeasure an idea")
end)

T.test("threats: a hail season without a storm can pass harmlessly", function()
  local world = newWorld(6)
  local e = only(world, "hail", SUMMER + 2, 2)
  plant(world, 10)
  local ended = collect(world, "threat.ended")
  local passed = false
  for _ = 1, 200 do -- clear days: 12% a day, so some seeds see two clear days with no hail
    e.status, e.rollDay, e.struck, e.damaged = "waiting", 0, false, 0
    for day = SUMMER + 2, SUMMER + 3 do
      force(world, "clear")
      run(world, day, 0, 24)
    end
    run(world, SUMMER + 4, 0, 1)
    if not e.struck then
      passed = true
      break
    end
  end
  T.truthy(passed)
  T.eq(ended[#ended].struck, false)
  T.eq(e.status, "done")
end)

T.test("threats: a drought dries the beds fast, withers neglected crops, mulch slows it", function()
  local function droughtWorld(mulch)
    local world = newWorld(3)
    local e = only(world, "drought", SUMMER + 2, 3)
    plant(world, 6, 0.2)
    if mulch then
      Inventory.addEquipment(world, "straw_mulch")
    end
    force(world, "clear")
    return world, e
  end
  local world, e = droughtWorld(false)
  local d = reg:get("threats", "drought")
  run(world, SUMMER + 2, d.hour, 6)
  T.eq(e.status, "active")
  local wet = 0
  for _, crop in pairs(world.state.crops) do
    wet = wet + crop.moisture
  end
  local mulched = droughtWorld(true)
  run(mulched, SUMMER + 2, d.hour, 6)
  local wetMulch = 0
  for _, crop in pairs(mulched.state.crops) do
    wetMulch = wetMulch + crop.moisture
  end
  T.truthy(wetMulch > wet, "mulched beds hold more water")
  -- Left unwatered for the whole drought, the crops wither.
  run(world, SUMMER + 2, d.hour + 6, 30)
  T.truthy(e.lost > 0, "neglected crops withered")
  T.truthy(count(world.state.crops) < 6)
end)

T.test("threats: rain breaks a drought early", function()
  local world = newWorld(3)
  local e = only(world, "drought", SUMMER + 2, 4)
  local d = reg:get("threats", "drought")
  force(world, "clear")
  run(world, SUMMER + 2, d.hour, 2)
  T.eq(e.status, "active")
  force(world, "rain")
  run(world, SUMMER + 2, d.hour + 2, 1)
  T.eq(e.status, "done")
  T.eq(e.broken, true)
end)

T.test("threats: warned ahead (more with weather sense), then a summary when it ends", function()
  local world = newWorld(8)
  local start = YEAR + SUMMER + 5
  only(world, "locusts", start, 1)
  local warned, ended = collect(world, "threat.warned"), collect(world, "threat.ended")
  run(world, start - tun.threats.warnDays - 1, 12, 1)
  T.eq(#warned, 0, "not yet")
  run(world, start - tun.threats.warnDays, 12, 1)
  T.eq(#warned, 1)
  T.eq(warned[1].days, tun.threats.warnDays)
  T.eq(#Threats.outlook(world), 1)
  run(world, start, 0, 24)
  T.eq(#ended, 1)
  T.eq(#Threats.outlook(world), 0, "gone from the forecast once over")
  T.eq(Threats.history(world)[#Threats.history(world)].id, "locusts")
end)

-- Saves -------------------------------------------------------------------------------------------------

T.test("threats: state survives a save round-trip and plays out the same", function()
  local world = newWorld(11)
  only(world, "drought", SUMMER + 2, 3)
  plant(world, 8, 0.3)
  local d = reg:get("threats", "drought")
  force(world, "clear")
  run(world, SUMMER + 2, d.hour, 4)
  world.state.weather.sky.first = SUMMER + 2 -- the forced sky is today's, so a load keeps it
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(serialize.encode(restored.state.threats), serialize.encode(world.state.threats))
  run(world, SUMMER + 2, d.hour + 4, 12)
  run(restored, SUMMER + 2, d.hour + 4, 12)
  T.eq(serialize.encode(restored.state.threats), serialize.encode(world.state.threats))
  T.eq(serialize.encode(restored.state.crops), serialize.encode(world.state.crops))
end)

T.test("threats: a save from before threats loads mid-year and skips what is past", function()
  local world = newWorld(12)
  setTime(world, YEAR + AUTUMN + 6, 12) -- late in year 2
  local state = serialize.decode(serialize.encode(world.state))
  state.threats = nil
  local loaded = World.new({ registry = reg, tuning = tun }, state)
  local list = Threats.schedule(loaded, 2)
  for _, e in ipairs(list) do
    if e.start + e.days - 1 < YEAR + AUTUMN + 6 then
      T.eq(e.status, "done", "past threats are skipped")
    end
  end
  local struck = collect(loaded, "threat.struck")
  loaded:tick(STEP)
  T.eq(#struck, 0, "nothing past strikes on load")
end)

T.test("threats: content is consistent (counters guard their threat, icons exist)", function()
  local sprites = require("assets.manifest").sprites
  for _, d in ipairs(reg:all("threats")) do
    local counter = reg:get("catalog", d.counter)
    T.truthy(counter.equipment and counter.modifiers[d.guard], d.id .. ": its counter carries " .. d.guard)
    T.truthy(sprites[d.icon], d.id .. " icon")
    T.truthy(sprites["icon_" .. d.counter], d.counter .. " icon")
    T.truthy((d.damage ~= nil) ~= (d.drought ~= nil), d.id .. " has exactly one effect")
    local noteFound = false
    for _, note in ipairs(reg:all("notes")) do
      if note.event == "threat.struck" and note.match and note.match.threat == d.id then
        noteFound = true
        local needs = counter.needs or {}
        T.eq(needs[1], note.id, d.counter .. " is learned from the threat's own note")
      end
    end
    T.truthy(noteFound, d.id .. " writes a note")
  end
end)
