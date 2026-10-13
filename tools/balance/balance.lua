-- Balance harness core (issue #31, GDD §12.5): plays whole runs headless with the real World,
-- Session, tuning and content, then aggregates survival / money / food / warmth / knowledge.
--
-- Pure Lua apart from the game modules it requires; no rendering, no mocks. Deterministic per
-- (seed, policy, tuning): all randomness is the sim's seeded streams plus a seeded policy stream.

local Calendar = require("src.sim.systems.calendar")
local Features = require("features")
local Finds = require("src.sim.systems.finds")
local Inventory = require("src.sim.systems.inventory")
local Machines = require("src.sim.systems.machines")
local Power = require("src.sim.systems.power")
local Stand = require("src.sim.systems.stand")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Policies = require("policies")
local Registry = require("src.core.registry")
local Run = require("src.meta.run")
local Save = require("src.core.save")
local Session = require("src.session")
local Weather = require("src.sim.systems.weather")

local Balance = {}

-- Setup --------------------------------------------------------------------------------------

--- Apply "domain.key[.key...]=number" overrides to the raw tuning tables (what-if runs). Must be
--- called before Balance.context. Errors on unknown keys.
function Balance.applyOverrides(list)
  for _, spec in ipairs(list or {}) do
    local path, value = spec:match("^([%w_%.]+)=(.+)$")
    local number = value and tonumber(value)
    assert(path and number, "bad override '" .. spec .. "' (expected domain.key=number)")
    local parts = {}
    for part in path:gmatch("[^%.]+") do
      parts[#parts + 1] = part
    end
    local node = require("data.tuning." .. parts[1])
    for n = 2, #parts - 1 do
      node = node[parts[n]]
      assert(type(node) == "table", "override '" .. spec .. "': no such table")
    end
    local key = parts[#parts]
    if rawget(node, key) == nil and tonumber(key) then
      key = tonumber(key) -- a list entry, e.g. threats.count.1
    end
    assert(#parts >= 2 and type(rawget(node, key)) == "number", "override '" .. spec .. "': no such number")
    node[key] = number
  end
end

--- Registry + tuning, loaded once and shared by every simulated run.
function Balance.context()
  local tuning = require("src.core.tuning").load()
  return { registry = Registry.new():loadAll(), tuning = tuning }
end

-- Statistics ---------------------------------------------------------------------------------

--- Linear-interpolated percentile (p in 0..1) of an unsorted list; nil for an empty list.
function Balance.percentile(values, p)
  local n = #values
  if n == 0 then
    return nil
  end
  local sorted = { unpack(values) }
  table.sort(sorted)
  local pos = 1 + (n - 1) * p
  local lo = math.floor(pos)
  local hi = math.min(n, lo + 1)
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
end

-- Simulating one run --------------------------------------------------------------------------

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local function snapshot(world)
  local now = Calendar.now(world)
  local j = world.meta.journal
  local needs = world.tuning.needs
  local warmth = Needs.warmthInStock(world)
  return {
    day = now.day,
    year = now.year,
    season = now.season,
    dayOfSeason = now.dayOfSeason,
    condition = world.state.needs.condition,
    money = Ledger.get(world, "money"),
    foodDays = Needs.foodDays(world),
    warmth = warmth,
    warmthNights = warmth / needs.warmthPeak, -- full winter nights (severity 1) the wood covers
    notes = countKeys(j.notes),
    known = countKeys(j.known),
    ideas = #Journal.ideas(world),
  }
end

-- What the winter ahead will ask of the fuel pile, from the world's own roll (diagnostic only).
local function winterNeed(world, year)
  local winter = world.state.weather.winters[year]
  if not winter then
    return nil
  end
  local weather = world.tuning.weather
  local sum = 0
  for d = 1, world.tuning.time.daysPerSeason do
    sum = sum + Weather.baseWarmth(world, "winter", d)
    if d >= winter.snapStart and d < winter.snapStart + winter.snapDays then
      sum = sum + Weather.baseWarmth(world, "winter", d) * (weather.snapMultiplier - 1)
    end
  end
  return sum * winter.severity
end

--- Simulate one run to its end or `years` years. Returns a result table:
---   alive, failDay, failSeason, failYear, cause, snaps[day], counters, winters[year].
--- `session` carries the slot data (a fresh Session per run).
local function playRun(ctx, session, policyName, seed, years, features)
  local world = session.world
  local tuning = ctx.tuning
  local tickRate = tuning.time.tickRate
  local step = 1 / tickRate
  local policy = Policies.new(policyName, world, seed, features)
  local decisionTicks = math.max(1, math.floor(tuning.idle.recheckInterval * tickRate + 0.5))
  local daysTotal = years * #tuning.time.seasons * tuning.time.daysPerSeason
  -- Day N+1 begins (daysTotal + 1 - startHour/24) days after the start.
  local capTicks = math.ceil((daysTotal + 1 - tuning.time.startHour / 24) * tuning.time.dayLength * tickRate) + 2

  local result = {
    seed = seed,
    policy = policyName,
    alive = true,
    snaps = {},
    winters = {},
    counters = {
      harvested = 0,
      fish = 0,
      earned = 0, -- $ from truck sales
      trips = 0,
      kwhMade = 0, -- power: generated, wanted by sinks, served to sinks, wasted (full batteries)
      kwhWanted = 0,
      kwhServed = 0,
      kwhWasted = 0,
      warmNights = 0, -- nights that needed warmth, and how many were covered fully by electric heaters
      electricNights = 0,
      electricWarmth = 0,
      miceRaids = 0, -- raids that cost food, raids the cat caught, units of food lost
      miceCaught = 0,
      miceLost = 0,
      spoiled = 0, -- units of fresh food that spoiled overnight (#151)
      eggs = 0, -- chickens: eggs collected, hens lost to predators / hunger / thirst, raids the coop turned back
      hensLost = 0,
      foxStopped = 0,
      milk = 0, -- goats: milk collected, goats lost to predators / hunger / thirst
      goatsLost = 0,
      threats = 0, -- growing-season threats (D67): scheduled ones that ran, ones that struck, crops lost / knocked back
      threatsStruck = 0,
      threatLost = 0,
      threatDamaged = 0,
      rainDays = 0,
      cloudyDays = 0,
      brownouts = 0,
    },
    finds = {}, -- find id -> times picked
    spoiledBy = {}, -- resource id -> units spoiled (D73)
    soldBy = {}, -- resource id -> units sold by the truck and the stand (D75)
    daysTotal = daysTotal,
    features = Features.label(features or {}),
  }
  local hourSeconds = tuning.time.dayLength / 24
  local damage = { hunger = 0, cold = 0 } -- Condition lost since the last day with no damage
  local last = { hunger = 0, cold = 0 }
  local failed = false

  local events = world.events
  events:on("needs.ate", function(e)
    last.hunger = e.shortfall
  end)
  events:on("needs.warmed", function(e)
    last.cold = e.shortfall
  end)
  events:on("needs.depleted", function()
    failed = true
  end)
  events:on("crop.harvested", function(e)
    result.counters.harvested = result.counters.harvested + e.amount
  end)
  events:on("fish.caught", function()
    result.counters.fish = result.counters.fish + 1
  end)
  events:on("market.sold", function(e)
    result.counters.earned = result.counters.earned + e.earnings
  end)
  events:on("market.trip", function()
    result.counters.trips = result.counters.trips + 1
  end)
  events:on("needs.warmed", function(e)
    local c = result.counters
    if e.needed > 0 then
      c.warmNights = c.warmNights + 1
      c.electricWarmth = c.electricWarmth + e.electric
      if e.electric >= e.needed - 1e-6 then
        c.electricNights = c.electricNights + 1
      end
    end
  end)
  events:on("mice.raided", function(e)
    result.counters.miceRaids = result.counters.miceRaids + 1
    result.counters.miceLost = result.counters.miceLost + e.units
  end)
  events:on("food.spoiled", function(e)
    result.counters.spoiled = result.counters.spoiled + e.amount
    result.spoiledBy[e.resource] = (result.spoiledBy[e.resource] or 0) + e.amount
  end)
  events:on("ledger.changed", function(e)
    if (e.reason == "sold" or e.reason == "stand") and e.delta < 0 then
      result.soldBy[e.id] = (result.soldBy[e.id] or 0) - e.delta
    end
  end)
  events:on("mice.caught", function()
    result.counters.miceCaught = result.counters.miceCaught + 1
  end)
  events:on("threat.ended", function(e)
    local c = result.counters
    c.threats = c.threats + 1
    c.threatsStruck = c.threatsStruck + (e.struck and 1 or 0)
    c.threatLost = c.threatLost + e.lost
    c.threatDamaged = c.threatDamaged + e.damaged
  end)
  events:on("animals.collected", function(e)
    result.counters.eggs = result.counters.eggs + e.count
  end)
  events:on("animals.milked", function(e)
    result.counters.milk = result.counters.milk + e.count
  end)
  events:on("animals.predator", function(e)
    local field = e.kind == "goats" and "goatsLost" or "hensLost"
    result.counters[field] = result.counters[field] + e.killed
    result.counters.foxStopped = result.counters.foxStopped + (e.stopped and 1 or 0)
  end)
  events:on("animals.lost", function(e)
    local field = e.kind == "goats" and "goatsLost" or "hensLost"
    result.counters[field] = result.counters[field] + 1
  end)
  events:on("power.brownout", function()
    result.counters.brownouts = result.counters.brownouts + 1
  end)
  events:on("finds.picked", function(e)
    result.finds[e.find] = (result.finds[e.find] or 0) + 1
  end)
  -- Registered after the sim's own handlers, so it sees the state after the night's food and warmth.
  events:on("calendar.newDay", function(e)
    local needs = tuning.needs
    local hunger, cold = last.hunger * needs.hungerDamage, last.cold * needs.coldDamage
    if hunger + cold > 0 then
      damage.hunger, damage.cold = damage.hunger + hunger, damage.cold + cold
    else
      damage.hunger, damage.cold = 0, 0
    end
    if not failed then
      result.snaps[e.day] = snapshot(world)
      result.snaps[e.day].truckEarned = result.counters.earned
      result.snaps[e.day].standEarned = Stand.total(world).earned
      local kind = Weather.kind(world)
      if Weather.isRaining(world) then
        result.counters.rainDays = result.counters.rainDays + 1
      elseif kind == "cloudy" then
        result.counters.cloudyDays = result.counters.cloudyDays + 1
      end
      local dayOfSeason = result.snaps[e.day].dayOfSeason
      -- First day of winter: how ready is the homestead?
      if dayOfSeason == 1 and Weather.isFrozenSeason(world, e.season) then
        local snap = result.snaps[e.day]
        result.winters[e.year] = {
          warmth = snap.warmth,
          need = winterNeed(world, e.year),
          foodDays = snap.foodDays,
          severity = world.state.weather.winters[e.year].severity,
          snapDays = world.state.weather.winters[e.year].snapDays,
        }
      end
    end
  end)

  events:on("calendar.newDay", function()
    if not failed then
      policy:daily(world)
    end
  end)

  local ticksRun = 0
  while ticksRun < capTicks and not failed do
    -- A find is a modal for a player; the policy answers at once (by need, or the first option).
    local offer = Finds.pending(world)
    if offer then
      Finds.choose(world, policy:chooseFind(world, offer))
    end
    if ticksRun % decisionTicks == 0 then
      policy:step(world)
    end
    world:tick(step)
    ticksRun = ticksRun + 1
    -- Energy ledger (kW of the last tick x hours): made, wanted, served, wasted.
    local flow, c = Power.flow(world), result.counters
    local hours = step / hourSeconds
    c.kwhMade = c.kwhMade + flow.generation * hours
    c.kwhWanted = c.kwhWanted + flow.demand * hours
    c.kwhServed = c.kwhServed + flow.served * hours
    c.kwhWasted = c.kwhWasted + (flow.wasted or 0) * hours
  end

  if failed then
    local now = Calendar.now(world)
    result.alive = false
    result.failDay = now.day
    result.failSeason = now.season
    result.failYear = now.year
    local total = damage.hunger + damage.cold
    if damage.cold >= total * 0.65 then
      result.cause = "cold"
    elseif damage.hunger >= total * 0.65 then
      result.cause = "hunger"
    else
      result.cause = "both"
    end
  end
  result.final = snapshot(world)
  result.final.truckEarned = result.counters.earned
  result.final.standEarned = Stand.total(world).earned
  -- Per-run facts read through public accessors.
  local water = Features.waterStats(world)
  result.counters.waterHand, result.counters.waterDrip = water.hand, water.drip
  result.counters.waterPumped, result.counters.waterRained = water.pumped, water.rained
  result.counters.standUnits = Stand.total(world).units
  result.counters.machineHarvests = Machines.done(world)
  result.owned = {}
  for _, id in ipairs({ "camp", "shack", "shelter_cat", "chicken_coop", "chicken_fence", "goat_pen", "goat_trailer", "cheese_press", "roadside_stand", "stand_sign", "stand_cooler", "stand_display", "well", "cistern", "dc_pump", "drip_line", "hand_pump", "solar_array", "battery_bank", "wind_turbine", "micro_hydro", "generator", "electric_heater", "lamp", "chest_freezer", "auto_harvester" }) do
    if Inventory.owns(world, id) then
      result.owned[id] = true
    end
  end
  return result
end

--- Play one seed. With `runs` > 1, a failed run is followed by recovery (the policy's free study)
--- and a fresh run on new land with the knowledge kept (GDD §4.3); a run that survives the span
--- ends the career there. Returns a list of run results.
function Balance.playSeed(ctx, policyName, seed, years, runs, features)
  local data = Save.newSlotData("balance")
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local results = {}
  for r = 1, runs or 1 do
    local runSeed = seed + (r - 1) * 7919
    local session = Session.new({
      store = store,
      slot = 1,
      data = data,
      registry = ctx.registry,
      tuning = ctx.tuning,
      seed = runSeed,
    })
    local result = playRun(ctx, session, policyName, runSeed, years, features)
    result.run = r
    result.baseSeed = seed
    result.notesThisRun = 0
    results[#results + 1] = result
    if result.alive then
      break
    end
    Run.fail(data, session.world)
    local metaWorld = Run.metaWorld(ctx, data.meta)
    local idea = Policies.freeStudy(metaWorld)
    if idea then
      Run.freeStudy(data, metaWorld, idea)
    end
    Run.startNext(data)
  end
  return results
end

-- Aggregation ---------------------------------------------------------------------------------

local METRICS = { "money", "foodDays", "warmthNights", "condition", "notes", "known", "ideas" }
Balance.METRICS = METRICS

--- Sample points: the start of the day after each season ends, as { day, year, season } where
--- `season` is the season that just finished.
function Balance.samplePoints(ctx, years)
  local time = ctx.tuning.time
  local points = {}
  for n = 1, years * #time.seasons do
    points[#points + 1] = {
      day = n * time.daysPerSeason + 1,
      year = math.floor((n - 1) / #time.seasons) + 1,
      season = time.seasons[(n - 1) % #time.seasons + 1],
    }
  end
  return points
end

local function quantiles(values)
  if #values == 0 then
    return nil
  end
  return {
    n = #values,
    p10 = Balance.percentile(values, 0.10),
    p25 = Balance.percentile(values, 0.25),
    p50 = Balance.percentile(values, 0.50),
    p75 = Balance.percentile(values, 0.75),
    p90 = Balance.percentile(values, 0.90),
  }
end

--- Aggregate run results (all of one policy and run index) into a summary table.
function Balance.summarize(ctx, results, years)
  local points = Balance.samplePoints(ctx, years)
  local n = #results
  local summary = { n = n, points = {}, daysSurvived = nil, causes = {}, failSeasons = {}, winter = {} }

  local days = {}
  local failed = 0
  for _, r in ipairs(results) do
    days[#days + 1] = r.alive and r.daysTotal or (r.failDay - 1)
    if not r.alive then
      failed = failed + 1
      summary.causes[r.cause] = (summary.causes[r.cause] or 0) + 1
      local key = string.format("%s Y%d", r.failSeason, r.failYear)
      summary.failSeasons[key] = (summary.failSeasons[key] or 0) + 1
    end
  end
  summary.failed = failed
  summary.daysSurvived = quantiles(days)

  for _, point in ipairs(points) do
    local entry = { point = point, alive = 0, metrics = {} }
    local values = {}
    for _, m in ipairs(METRICS) do
      values[m] = {}
    end
    for _, r in ipairs(results) do
      local snap = r.snaps[point.day]
      if snap then
        entry.alive = entry.alive + 1
        for _, m in ipairs(METRICS) do
          values[m][#values[m] + 1] = snap[m]
        end
      end
    end
    for _, m in ipairs(METRICS) do
      entry.metrics[m] = quantiles(values[m])
    end
    summary.points[#summary.points + 1] = entry
  end

  -- Winter readiness at the first winter day, among runs that got there.
  for year = 1, years do
    local ready, fuelRatio, food, need, severity = {}, {}, {}, {}, {}
    for _, r in ipairs(results) do
      local w = r.winters[year]
      if w then
        ready[#ready + 1] = w
        fuelRatio[#fuelRatio + 1] = w.warmth / w.need
        food[#food + 1] = w.foodDays
        need[#need + 1] = w.need
        severity[#severity + 1] = w.severity
      end
    end
    if #ready > 0 then
      local covered = 0
      for _, ratio in ipairs(fuelRatio) do
        if ratio >= 1 then
          covered = covered + 1
        end
      end
      summary.winter[year] = {
        n = #ready,
        coverage = quantiles(fuelRatio),
        foodDays = quantiles(food),
        need = quantiles(need),
        severity = quantiles(severity),
        coveredFraction = covered / #ready,
      }
    end
  end
  -- Income by source per year, among runs alive at the end of that year (cumulative at the year's
  -- last morning minus the year before).
  local perYear = #ctx.tuning.time.seasons * ctx.tuning.time.daysPerSeason
  summary.income = {}
  for year = 1, years do
    local truck, stand = {}, {}
    local from, to = (year - 1) * perYear + 1, year * perYear + 1
    for _, r in ipairs(results) do
      local a, b = r.snaps[from] or (year == 1 and { truckEarned = 0, standEarned = 0 }), r.snaps[to]
      if a and b then
        truck[#truck + 1] = b.truckEarned - a.truckEarned
        stand[#stand + 1] = b.standEarned - a.standEarned
      end
    end
    if #truck > 0 then
      summary.income[year] = { n = #truck, truck = quantiles(truck), stand = quantiles(stand) }
    end
  end

  -- Per-run totals over the whole span (every seed, dead ones count for the days they lived).
  local keys = {}
  for k in pairs(results[1] and results[1].counters or {}) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  summary.totals, summary.owned, summary.finds, summary.spoiledBy, summary.soldBy = {}, {}, {}, {}, {}
  for _, k in ipairs(keys) do
    local values = {}
    for _, r in ipairs(results) do
      values[#values + 1] = r.counters[k] or 0
    end
    summary.totals[k] = quantiles(values)
    local sum = 0
    for _, v in ipairs(values) do
      sum = sum + v
    end
    summary.totals[k].mean = sum / #values
  end
  for _, r in ipairs(results) do
    for id in pairs(r.owned or {}) do
      summary.owned[id] = (summary.owned[id] or 0) + 1
    end
    for id, count in pairs(r.finds or {}) do
      summary.finds[id] = (summary.finds[id] or 0) + count
    end
    for id, count in pairs(r.spoiledBy or {}) do
      summary.spoiledBy[id] = (summary.spoiledBy[id] or 0) + count
    end
    for id, count in pairs(r.soldBy or {}) do
      summary.soldBy[id] = (summary.soldBy[id] or 0) + count
    end
  end
  summary.features = results[1] and results[1].features or "none"
  return summary
end

-- Reporting -------------------------------------------------------------------------------------

local function pct(x)
  return string.format("%3.0f%%", x * 100)
end

local function num(x, digits)
  if x == nil then
    return "-"
  end
  if math.abs(x) >= 100 or digits == 0 then
    return string.format("%.0f", x)
  end
  return string.format("%." .. (digits or 1) .. "f", x)
end

local function label(point)
  local names = { spring = "Sp", summer = "Su", autumn = "Au", winter = "Wi" }
  return string.format("%s%d", names[point.season] or point.season, point.year)
end

local function pad(s, width)
  s = tostring(s)
  return string.rep(" ", math.max(0, width - #s)) .. s
end

local function line(...)
  io.write(table.concat({ ... }), "\n")
end

local METRIC_NAMES = {
  money = "money ($)",
  foodDays = "food (days in stock)",
  warmthNights = "fuel (winter nights covered)",
  condition = "condition (0-100)",
  notes = "journal notes",
  known = "journal nodes learned",
  ideas = "ideas waiting",
}

--- Print the human-readable report for one (policy, run index) summary.
function Balance.printSummary(ctx, policyName, runIndex, summary, years)
  line("")
  line(string.rep("=", 100))
  line(string.format("policy %-9s run %d   seeds: %d   (%s)", policyName, runIndex, summary.n, Policies.describe[policyName]))
  line(string.rep("=", 100))
  local seasons = #ctx.tuning.time.seasons
  local points = summary.points

  -- Survival: share of seeds still alive when each season ends.
  line("Alive when the season ends (share of seeds)")
  local head, row = { pad("", 10) }, { pad("alive", 10) }
  for _, entry in ipairs(points) do
    head[#head + 1] = pad(label(entry.point), 7)
    row[#row + 1] = pad(pct(entry.alive / summary.n), 7)
  end
  line(table.concat(head))
  line(table.concat(row))

  -- Days survived.
  local d = summary.daysSurvived
  local span = years * seasons * ctx.tuning.time.daysPerSeason
  line("")
  line(
    string.format(
      "Days survived (cap %d, survivors counted at the cap): p10 %s  p25 %s  median %s  p75 %s  p90 %s   failed: %d/%d",
      span,
      num(d.p10, 0),
      num(d.p25, 0),
      num(d.p50, 0),
      num(d.p75, 0),
      num(d.p90, 0),
      summary.failed,
      summary.n
    )
  )

  -- Failure breakdown.
  if summary.failed > 0 then
    local keys = {}
    for k in pairs(summary.failSeasons) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      local ay, by = tonumber(a:match("Y(%d+)")), tonumber(b:match("Y(%d+)"))
      if ay ~= by then
        return ay < by
      end
      local ai, bi = 0, 0
      for n, s in ipairs(ctx.tuning.time.seasons) do
        if a:find("^" .. s) then
          ai = n
        end
        if b:find("^" .. s) then
          bi = n
        end
      end
      return ai < bi
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = string.format("%s: %d", k, summary.failSeasons[k])
    end
    line("Failures by season: " .. table.concat(parts, "   "))
    local causes = {}
    for _, c in ipairs({ "cold", "hunger", "both" }) do
      if summary.causes[c] then
        causes[#causes + 1] = string.format("%s: %d", c, summary.causes[c])
      end
    end
    line("Failure causes (dominant source of Condition loss): " .. table.concat(causes, "   "))
  end

  -- Curves: median [p25-p75] among seeds alive at each point.
  for _, m in ipairs(METRICS) do
    line("")
    line(METRIC_NAMES[m] .. "   median [p25-p75] of seeds alive at season end")
    for year = 1, years do
      local head2, row2 = { pad("", 10) }, { pad("median", 10) }
      local range = { pad("p25-p75", 10) }
      for s = 1, seasons do
        local entry = points[(year - 1) * seasons + s]
        if entry then
          local q = entry.metrics[m]
          head2[#head2 + 1] = pad(label(entry.point), 13)
          row2[#row2 + 1] = pad(q and num(q.p50) or "-", 13)
          range[#range + 1] = pad(q and (num(q.p25) .. "-" .. num(q.p75)) or "-", 13)
        end
      end
      line(table.concat(head2))
      line(table.concat(row2))
      line(table.concat(range))
    end
  end

  -- Winter readiness.
  for year = 1, years do
    local w = summary.winter[year]
    if w then
      line("")
      line(
        string.format(
          "Winter %d readiness on its first day (%d seeds got there): fuel warmth / winter need median %.2f [p25 %.2f, p75 %.2f], covered fully: %s; "
            .. "winter need median %s warmth (severity median %.2f); food median %s days",
          year,
          w.n,
          w.coverage.p50,
          w.coverage.p25,
          w.coverage.p75,
          pct(w.coveredFraction),
          num(w.need.p50),
          w.severity.p50,
          num(w.foodDays.p50)
        )
      )
    end
  end
end

--- The per-feature metrics block of a summary: income by source, power, water, mice, finds, kit.
function Balance.printFeatures(summary, years)
  line("")
  line("Features: " .. tostring(summary.features))
  local function q(key)
    return summary.totals[key]
  end
  for year = 1, years do
    local inc = summary.income[year]
    if inc then
      local truck, stand = inc.truck.p50, inc.stand.p50
      local share = truck + stand > 0 and stand / (truck + stand) or 0
      line(
        string.format(
          "Income year %d (median of %d alive): truck $%s [p25-p75 %s-%s], stand $%s [%s-%s], stand share of the two %s",
          year,
          inc.n,
          num(truck, 0),
          num(inc.truck.p25, 0),
          num(inc.truck.p75, 0),
          num(stand, 0),
          num(inc.stand.p25, 0),
          num(inc.stand.p75, 0),
          pct(share)
        )
      )
    end
  end
  line(
    string.format(
      "Per run (mean): trips %.1f, truck $%.0f, stand units %.0f, harvested %.0f (crops picked by machines %.0f), fish %.0f",
      q("trips").mean,
      q("earned").mean,
      q("standUnits").mean,
      q("harvested").mean,
      q("machineHarvests").mean,
      q("fish").mean
    )
  )
  line(
    string.format(
      "Power kWh per run (mean): made %.0f, wanted %.0f, served %.0f, shed %.0f, wasted %.0f; brownout days %.1f; "
        .. "nights needing warmth %.1f, fully electric %.1f (electric warmth %.0f)",
      q("kwhMade").mean,
      q("kwhWanted").mean,
      q("kwhServed").mean,
      q("kwhWanted").mean - q("kwhServed").mean,
      q("kwhWasted").mean,
      q("brownouts").mean,
      q("warmNights").mean,
      q("electricNights").mean,
      q("electricWarmth").mean
    )
  )
  line(
    string.format(
      "Water per run (mean): waterings by hand %.0f, by drip %.0f; cistern units pumped %.0f, rained %.0f; rain days %.1f, cloudy days %.1f",
      q("waterHand").mean,
      q("waterDrip").mean,
      q("waterPumped").mean,
      q("waterRained").mean,
      q("rainDays").mean,
      q("cloudyDays").mean
    )
  )
  line(
    string.format(
      "Food per run (mean): %.1f units spoiled. Mice: raids that took food %.1f (%.1f food units lost), raids the cat caught %.1f",
      q("spoiled").mean,
      q("miceRaids").mean,
      q("miceLost").mean,
      q("miceCaught").mean
    )
  )
  line(
    string.format(
      "Threats per run (mean): %.1f came, %.1f struck; crops lost %.1f, knocked back %.1f (policies buy no countermeasures)",
      q("threats").mean,
      q("threatsStruck").mean,
      q("threatLost").mean,
      q("threatDamaged").mean
    )
  )
  line(
    string.format(
      "Chickens per run (mean): eggs collected %.0f, hens lost %.1f, raids the coop turned back %.1f",
      q("eggs").mean,
      q("hensLost").mean,
      q("foxStopped").mean
    )
  )
  line(string.format("Goats per run (mean): milk collected %.0f, goats lost %.1f", q("milk").mean, q("goatsLost").mean))
  local owned, finds = {}, {}
  for id, n in pairs(summary.owned) do
    owned[#owned + 1] = string.format("%s %d%%", id, math.floor(100 * n / summary.n + 0.5))
  end
  table.sort(owned)
  for id, n in pairs(summary.finds) do
    finds[#finds + 1] = string.format("%s %.1f", id, n / summary.n)
  end
  table.sort(finds)
  line("Owned at the end (share of seeds): " .. (#owned > 0 and table.concat(owned, ", ") or "-"))
  line("Finds picked per run (mean): " .. (#finds > 0 and table.concat(finds, ", ") or "-"))
  local spoiled = {}
  for id, n in pairs(summary.spoiledBy) do
    spoiled[#spoiled + 1] = string.format("%s %.1f", id, n / summary.n)
  end
  table.sort(spoiled)
  line("Spoiled per run by food (mean units): " .. (#spoiled > 0 and table.concat(spoiled, ", ") or "-"))
  local sold = {}
  for id, n in pairs(summary.soldBy) do
    sold[#sold + 1] = string.format("%s %.1f", id, n / summary.n)
  end
  table.sort(sold)
  line("Sold per run by good, truck and stand (mean units): " .. (#sold > 0 and table.concat(sold, ", ") or "-"))
end

-- File output -------------------------------------------------------------------------------------

local function jsonEncode(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return "null"
    end
    return string.format("%.6g", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    local inner = indent .. "  "
    local parts = {}
    if #v > 0 or next(v) == nil then
      for _, item in ipairs(v) do
        parts[#parts + 1] = inner .. jsonEncode(item, inner)
      end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local value = v[k] ~= nil and v[k] or v[tonumber(k)]
      parts[#parts + 1] = inner .. jsonEncode(k) .. ": " .. jsonEncode(value, inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "null"
end
Balance.jsonEncode = jsonEncode

--- CSV with one row per seed per run per season-start snapshot (day 1, 2, ...).
function Balance.writeCsv(path, all)
  local fh = assert(io.open(path, "w"))
  fh:write("policy,seed,run,day,year,season,dayOfSeason,condition,money,foodDays,warmth,warmthNights,notes,known,ideas,failedAtEnd\n")
  for _, r in ipairs(all) do
    local days = {}
    for day in pairs(r.snaps) do
      days[#days + 1] = day
    end
    table.sort(days)
    for _, day in ipairs(days) do
      local s = r.snaps[day]
      fh:write(
        string.format(
          "%s,%d,%d,%d,%d,%s,%d,%.1f,%d,%.2f,%.2f,%.2f,%d,%d,%d,%d\n",
          r.policy,
          r.baseSeed,
          r.run,
          s.day,
          s.year,
          s.season,
          s.dayOfSeason,
          s.condition,
          s.money,
          s.foodDays,
          s.warmth,
          s.warmthNights,
          s.notes,
          s.known,
          s.ideas,
          r.alive and 0 or 1
        )
      )
    end
  end
  fh:close()
end

--- JSON with the per-policy summaries and one compact record per run.
function Balance.writeJson(path, report)
  local fh = assert(io.open(path, "w"))
  fh:write(jsonEncode(report), "\n")
  fh:close()
end

--- Print one run day by day (for working out why a seed lived or died).
function Balance.printTrace(r)
  line(string.format("trace: policy %s seed %d run %d  %s", r.policy, r.baseSeed, r.run, r.alive and "survived" or ("failed on day " .. r.failDay .. " (" .. tostring(r.cause) .. ")")))
  line("  day  season    cond  money  foodDays  warmth  notes known ideas")
  local days = {}
  for day in pairs(r.snaps) do
    days[#days + 1] = day
  end
  table.sort(days)
  for _, day in ipairs(days) do
    local x = r.snaps[day]
    line(
      string.format(
        "  %3d  %-8s %5.1f %6d %9.1f %7.1f %6d %5d %5d",
        day, x.season, x.condition, x.money, x.foodDays, x.warmth, x.notes, x.known, x.ideas
      )
    )
  end
  local c = r.counters
  line(string.format("  harvested %d, fish %d, earned $%d, trips %d", c.harvested, c.fish, c.earned, c.trips))
end

--- A compact per-run record for the JSON output (no per-day snapshots).
function Balance.runRecord(r)
  return {
    seed = r.baseSeed,
    run = r.run,
    alive = r.alive,
    failDay = r.failDay,
    failSeason = r.failSeason,
    failYear = r.failYear,
    cause = r.cause,
    final = r.final,
    counters = r.counters,
  }
end

return Balance
