-- Balance harness core (issue #31, GDD §12.5): plays whole runs headless with the real World,
-- Session, tuning and content, then aggregates survival / money / food / warmth / knowledge.
--
-- Pure Lua apart from the game modules it requires; no rendering, no mocks. Deterministic per
-- (seed, policy, tuning): all randomness is the sim's seeded streams plus a seeded policy stream.

local Calendar = require("src.sim.systems.calendar")
local EventPolicy = require("event_policy")
local Events = require("src.sim.systems.events")
local Features = require("features")
local Finds = require("src.sim.systems.finds")
local Footing = require("src.sim.systems.footing")
local Gates = require("gates")
local Inventory = require("src.sim.systems.inventory")
local Market = require("src.sim.systems.market")
local Machines = require("src.sim.systems.machines")
local Power = require("src.sim.systems.power")
local Soil = require("src.sim.systems.soil")
local Stand = require("src.sim.systems.stand")
local Wardrobe = require("src.sim.systems.wardrobe")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Policies = require("policies")
local Registry = require("src.core.registry")
local Run = require("src.meta.run")
local Save = require("src.core.save")
local Status = require("src.sim.systems.status")
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

--- 0 Footing not held, 1 held, 2 held but slipped (the CSV column).
local function footingCode(world)
  local s = world.state.footing
  return s.held and (s.slipped and 2 or 1) or 0
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
    footing = footingCode(world),
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
local function playRun(ctx, session, policyName, seed, years, features, eventMode)
  if eventMode == "off" then
    eventMode = nil
  end
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
      harvests = 0, -- rotation (D179): harvests, those repeating the tile's last family, the yield share pest pressure cut (summed), harvests that gave nothing, pest hits, blight outbreaks
      harvestsRepeat = 0,
      pressureCut = 0,
      zeroYields = 0,
      pestHits = 0,
      blightOutbreaks = 0,
      weedCut = 0, -- weeds and compost (D180, D181): the yield share weeds cut (summed over harvests), tiles pulled, overgrown tile-days, compost made and spread
      weedsPulled = 0,
      weedyDays = 0,
      compostMade = 0,
      compostSpread = 0,
      qualityFine = 0, -- crop quality (D182): harvests graded fine (the rest are normal; D182, D185)
      fruitFirst = 0, -- perennials (D183): harvests of the young first crop and of established plants, units of fruit picked
      fruitFull = 0,
      fruitUnits = 0,
      plantsPlanted = 0,
      plantsRemoved = 0,
      fruitLost = 0,
      rainDays = 0,
      cloudyDays = 0,
      brownouts = 0,
    },
    finds = {}, -- find id -> times picked
    spoiledBy = {}, -- resource id -> units spoiled (D73)
    soldBy = {}, -- resource id -> units sold by the truck and the stand (D75)
    -- Crop income (D177, #363): $ the truck and the stand paid, at the price of the moment: `all` for every good,
    -- `crops` for crop produce, `starter` for the starter field's crops (tuning.farming.starterField). The check
    -- behind "starting-crop income must not fund the mid game" (#263): reporting only, no target.
    sales = { all = 0, crops = 0, starter = 0 },
    plantedByYear = {}, -- game year -> crop id -> plantings (how many kinds the player grows once the others are known)
    daysTotal = daysTotal,
    features = Features.label(features or {}),
    -- Events (D169, #347): only when an event-choice policy is chosen. What came, how it was answered, and the spiral
    -- measures: the lowest Condition, the days spent with a status, the most statuses at once.
    events = eventMode
        and {
          mode = eventMode,
          offered = 0,
          chosen = 0,
          ignored = 0,
          by = {}, -- event id -> { offered, chosen, ignored }
          minCondition = 100,
          statusDays = 0,
          maxStatuses = 0,
          statusHist = {}, -- statuses active at a dawn -> days (the median of the days, B6 #350)
        }
      or nil,
    -- Footing (D165, #344): the day it was first earned (nil if never), slips and regains, the dusk nights judged
    -- before it was earned, how many of them failed each of the four tests, and the first frozen season's first day.
    footing = {
      slips = 0,
      regains = 0,
      nights = 0,
      fail = { shelter = 0, water = 0, fuel = 0, food = 0 },
      failFuel = {}, -- season -> nights short of fuel before Footing was earned
    },
  }
  for n, season in ipairs(tuning.time.seasons) do
    if Weather.isFrozenSeason(world, season) then
      result.footing.winterDay = (n - 1) * tuning.time.daysPerSeason + 1
      break
    end
  end
  local produceOf, starterProduce = {}, {} -- resource id -> true, for crop produce and for the starter field's
  for _, crop in ipairs(ctx.registry:all("crops")) do
    produceOf[crop.produce] = true
  end
  for _, entry in ipairs(tuning.farming.starterField) do
    starterProduce[ctx.registry:get("crops", entry.crop).produce] = true
  end
  local hourSeconds = tuning.time.dayLength / 24
  local damage = { hunger = 0, cold = 0, thirst = 0 } -- Condition lost since the last day with no damage
  local last = { hunger = 0, cold = 0, thirst = 0 }
  local failed = false

  local events = world.events
  events:on("needs.ate", function(e)
    last.hunger = e.shortfall
  end)
  events:on("needs.warmed", function(e)
    last.cold = e.shortfall
  end)
  events:on("needs.drank", function(e)
    last.thirst = e.damage -- already Condition (it builds over a run of dry days), not a share
  end)
  events:on("needs.depleted", function()
    failed = true
  end)
  events:on("crop.harvested", function(e)
    local c = result.counters
    c.harvested = c.harvested + e.amount
    c.harvests = c.harvests + 1
    c.harvestsRepeat = c.harvestsRepeat + (e.repeated and 1 or 0)
    c.pressureCut = c.pressureCut + tuning.soil.pressureCut * e.pressure
    c.zeroYields = c.zeroYields + (e.amount < 1 and 1 or 0)
    c.weedCut = c.weedCut + tuning.soil.weedCut * e.weeds
    if e.stage then
      c.fruitFirst = c.fruitFirst + (e.stage == "first" and 1 or 0)
      c.fruitFull = c.fruitFull + (e.stage == "mature" and 1 or 0)
      c.fruitUnits = c.fruitUnits + e.amount
    end
    c.qualityFine = c.qualityFine + (e.quality == "fine" and 1 or 0)
  end)
  events:on("crop.planted", function(e)
    local c = result.counters
    c.plantsPlanted = c.plantsPlanted + (ctx.registry:get("crops", e.crop).perennial and 1 or 0)
  end)
  events:on("crop.removed", function(e)
    local c = result.counters
    c.plantsRemoved = c.plantsRemoved + (ctx.registry:get("crops", e.crop).perennial and 1 or 0)
  end)
  events:on("crop.lost", function(e)
    local c = result.counters
    c.fruitLost = c.fruitLost + (ctx.registry:get("crops", e.crop).perennial and 1 or 0)
  end)
  events:on("weed.pulled", function()
    result.counters.weedsPulled = result.counters.weedsPulled + 1
  end)
  events:on("compost.done", function(e)
    result.counters.compostMade = result.counters.compostMade + e.count
  end)
  events:on("compost.spread", function()
    result.counters.compostSpread = result.counters.compostSpread + 1
  end)
  events:on("pest.struck", function(e)
    result.counters.pestHits = result.counters.pestHits + (e.saved and 0 or 1)
  end)
  events:on("threat.struck", function(e)
    result.counters.blightOutbreaks = result.counters.blightOutbreaks + (e.threat == "blight" and 1 or 0)
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
      local price = e.reason == "stand" and Stand.unitPrice(world, e.id) or Market.sellPrice(world, e.id)
      local worth = -e.delta * price
      result.sales.all = result.sales.all + worth
      if produceOf[e.id] then
        result.sales.crops = result.sales.crops + worth
        if starterProduce[e.id] then
          result.sales.starter = result.sales.starter + worth
        end
      end
    end
  end)
  events:on("crop.planted", function(e)
    local year = Calendar.now(world).year
    local by = result.plantedByYear[year] or {}
    result.plantedByYear[year] = by
    by[e.crop] = (by[e.crop] or 0) + 1
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
  events:on("footing.gained", function(e)
    result.footing.gainedDay = result.footing.gainedDay or e.day
  end)
  events:on("footing.slipped", function()
    result.footing.slips = result.footing.slips + 1
  end)
  events:on("footing.regained", function()
    result.footing.regains = result.footing.regains + 1
  end)
  if result.events then
    local function tally(id, field)
      local by = result.events.by
      by[id] = by[id] or { offered = 0, chosen = 0, ignored = 0 }
      by[id][field] = by[id][field] + 1
      result.events[field] = result.events[field] + 1
    end
    events:on("event.offered", function(e)
      tally(e.id, "offered")
    end)
    events:on("event.chosen", function(e)
      tally(e.id, "chosen")
    end)
    events:on("event.ignored", function(e)
      tally(e.id, "ignored")
    end)
  end
  events:on("power.brownout", function()
    result.counters.brownouts = result.counters.brownouts + 1
  end)
  events:on("finds.picked", function(e)
    result.finds[e.find] = (result.finds[e.find] or 0) + 1
  end)
  -- Registered after the sim's own handlers, so it sees the state after the night's food and warmth.
  events:on("calendar.newDay", function(e)
    local needs = tuning.needs
    local hunger, cold, thirst = last.hunger * needs.hungerDamage, last.cold * needs.coldDamage, last.thirst
    if hunger + cold + thirst > 0 then
      damage.hunger, damage.cold, damage.thirst = damage.hunger + hunger, damage.cold + cold, damage.thirst + thirst
    else
      damage.hunger, damage.cold, damage.thirst = 0, 0, 0
    end
    if not failed then
      result.snaps[e.day] = snapshot(world)
      if result.events then
        local x, active = result.events, Status.count(world)
        x.minCondition = math.min(x.minCondition, result.snaps[e.day].condition)
        x.statusDays = x.statusDays + (active > 0 and 1 or 0)
        x.maxStatuses = math.max(x.maxStatuses, active)
        x.statusHist[active] = (x.statusHist[active] or 0) + 1
      end
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
    for _, i in ipairs(Soil.weedTiles(world)) do -- after the dawn's growth: tiles the routine has let get overgrown
      if Soil.weeds(world, i) >= tuning.soil.weedHigh then
        result.counters.weedyDays = result.counters.weedyDays + 1
      end
    end
  end)

  local eventPolicy = EventPolicy.new(eventMode, seed)
  local ticksRun = 0
  local lastJudged = world.state.footing.last
  while ticksRun < capTicks and not failed do
    -- A find is a modal for a player; the policy answers at once (by need, or the first option).
    local offer = Finds.pending(world)
    if offer then
      Finds.choose(world, policy:chooseFind(world, offer))
    end
    -- An event card is answered by the event-choice policy; its real-time floor runs at the sim's own pace (1x).
    local card = eventPolicy and Events.pending(world)
    if card and eventPolicy.answered ~= result.events.offered then
      eventPolicy.answered = result.events.offered -- one answer per card; a card left to run out is not asked again
      local answer = EventPolicy.answer(eventPolicy, card)
      if policy.dropsCard and policy:dropsCard() then
        answer = nil -- a person who does not look at the card: the window runs out (the human policy)
      end
      if answer == "ignore" then
        Events.ignore(world)
      elseif answer then
        Events.choose(world, answer)
      end
    end
    Events.advanceReal(world, step)
    if ticksRun % decisionTicks == 0 then
      policy:step(world)
    end
    world:tick(step)
    ticksRun = ticksRun + 1
    -- A dusk judgement just ran: note which of its four tests failed while Footing is still to be earned. Reads
    -- the same checks the sim just used, in the same tick, and changes nothing.
    local judged = world.state.footing.last
    if judged ~= lastJudged then
      lastJudged = judged
      local f = result.footing
      if not f.gainedDay then
        f.nights = f.nights + 1
        local season = Calendar.now(world).season
        for _, c in ipairs(Footing.checks(world)) do
          if not c.ok then
            f.fail[c.id] = f.fail[c.id] + 1
            if c.id == "fuel" then
              f.failFuel[season] = (f.failFuel[season] or 0) + 1
            end
          end
        end
      end
    end
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
    local total = damage.hunger + damage.cold + damage.thirst
    if damage.cold >= total * 0.65 then
      result.cause = "cold"
    elseif damage.hunger >= total * 0.65 then
      result.cause = "hunger"
    elseif damage.thirst >= total * 0.65 then
      result.cause = "thirst"
    else
      result.cause = "both"
    end
  end
  -- Spiral facts (#410): was Footing held but slipped when the run ended, and the mornings spent slipped.
  local fs = world.state.footing
  result.spiral = { diedSlipped = failed and fs.held and fs.slipped or false, slippedDays = 0 }
  for _, snap in pairs(result.snaps) do
    if snap.footing == 2 then
      result.spiral.slippedDays = result.spiral.slippedDays + 1
    end
  end
  result.final = snapshot(world)
  result.final.truckEarned = result.counters.earned
  result.final.standEarned = Stand.total(world).earned
  -- Per-run facts read through public accessors.
  local water = Features.waterStats(world)
  result.counters.waterHand, result.counters.waterDrip = water.hand, water.drip
  result.counters.waterSprinkler = water.sprinkler
  result.counters.waterPumped, result.counters.waterRained = water.pumped, water.rained
  result.counters.standUnits = Stand.total(world).units
  result.counters.machineHarvests = Machines.done(world)
  result.owned = {}
  for _, id in ipairs({
    "camp",
    "shack",
    "woodshed",
    "wood_stove",
    "shelter_cat",
    "chicken_coop",
    "chicken_fence",
    "goat_pen",
    "goat_trailer",
    "cheese_press",
    "roadside_stand",
    "stand_sign",
    "stand_cooler",
    "stand_display",
    "well",
    "cistern",
    "dc_pump",
    "sprinkler",
    "drip_line",
    "hand_pump",
    "solar_array",
    "battery_bank",
    "wind_turbine",
    "micro_hydro",
    "generator",
    "electric_heater",
    "lamp",
    "chest_freezer",
    "auto_harvester",
  }) do
    if Inventory.owns(world, id) then
      result.owned[id] = true
    end
  end
  return result
end

--- Dress the homesteader in a whole outfit of one weight class ("light", "mid" or "heavy"): the first garment
--- of that class in each slot, earned through the wardrobe's own grant and put on with its own wear, so the
--- rules (owned, right slot, today's outfit in the opening window) apply as they do for a player.
function Balance.dress(world, class)
  local outfit = {}
  for _, def in ipairs(world.registry:all("garments")) do
    if def.class == class and not outfit[def.slot] then
      outfit[def.slot] = def.id
    end
  end
  assert(next(outfit), "outfit=" .. tostring(class) .. ": expected light, mid or heavy")
  for _, slot in ipairs(Wardrobe.slots(world)) do
    Wardrobe.grant(world, outfit[slot])
  end
  local ok, reason = Wardrobe.wear(world, outfit)
  assert(ok, "outfit=" .. class .. ": " .. tostring(reason))
end

--- The facts of an events-off run kept beside its events-on twin (#410): enough for the paired report, no snapshots.
local function offLeg(r)
  return {
    alive = r.alive,
    failDay = r.failDay,
    failYear = r.failYear,
    failSeason = r.failSeason,
    cause = r.cause,
    footingDay = r.footing.gainedDay,
    slips = r.footing.slips,
    money = r.final.money,
    condition = r.final.condition,
  }
end

--- Play one seed twice on the same seed, once with events disabled and once with events on under `eventMode` (a
--- choice policy), and return the events-on results; each carries `off`, the facts of the events-off run with the same
--- run index (nil when that career ended sooner). The two careers are independent: a run that dies in one has its own
--- recovery and next run, so only run indexes both legs reached are paired.
function Balance.playPair(ctx, policyName, seed, years, runs, features, outfit, eventMode)
  assert(eventMode and eventMode ~= "off", "a paired run needs an event policy (events=ignore|careful|bold|random)")
  local off = Balance.playSeed(ctx, policyName, seed, years, runs, features, outfit, "off")
  local on = Balance.playSeed(ctx, policyName, seed, years, runs, features, outfit, eventMode)
  for _, r in ipairs(on) do
    r.off = off[r.run] and offLeg(off[r.run]) or nil
  end
  return on
end

--- Play one seed. With `runs` > 1, a failed run is followed by recovery (the policy's free study)
--- and a fresh run on new land with the knowledge kept (GDD §4.3); a run that survives the span
--- ends the career there. `outfit` ("light", "mid" or "heavy", optional) dresses the homesteader in the first
--- garment of that weight class in every slot at the start of each run (Balance.dress). Returns a list of run
--- results.
function Balance.playSeed(ctx, policyName, seed, years, runs, features, outfit, eventMode, pair)
  if pair then
    return Balance.playPair(ctx, policyName, seed, years, runs, features, outfit, eventMode)
  end
  if eventMode ~= nil then
    ctx.tuning.events.enabled = eventMode ~= "off" -- the engine follows the mode (a paired run plays both ways in one process)
  end
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
    if outfit then
      Balance.dress(session.world, outfit)
    end
    local result = playRun(ctx, session, policyName, runSeed, years, features, eventMode)
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

--- Events across runs (D169, #347), only when an event-choice policy was used (nil otherwise, so the default report is
--- unchanged): totals per run, the spiral measures and the share of runs that failed with an event answered in their last
--- week (a first look for "an event kills a run"; the plan's gate is the cause split in the failure report).
function Balance.eventsSummary(results)
  if not (results[1] and results[1].events) then
    return nil
  end
  local out = {
    mode = results[1].events.mode,
    n = #results,
    offered = 0,
    chosen = 0,
    ignored = 0,
    by = {},
    statusDays = 0,
    maxStatuses = 0,
    minCondition = 100,
    statusHist = {},
  }
  for _, r in ipairs(results) do
    local x = r.events
    out.offered, out.chosen, out.ignored = out.offered + x.offered, out.chosen + x.chosen, out.ignored + x.ignored
    out.statusDays = out.statusDays + x.statusDays
    out.maxStatuses = math.max(out.maxStatuses, x.maxStatuses)
    out.minCondition = math.min(out.minCondition, x.minCondition)
    for count, days in pairs(x.statusHist) do
      out.statusHist[count] = (out.statusHist[count] or 0) + days
    end
    for id, by in pairs(x.by) do
      local sum = out.by[id] or { offered = 0, chosen = 0, ignored = 0 }
      out.by[id] = sum
      sum.offered, sum.chosen, sum.ignored = sum.offered + by.offered, sum.chosen + by.chosen, sum.ignored + by.ignored
    end
  end
  out.offeredPerRun, out.statusDaysPerRun = out.offered / out.n, out.statusDays / out.n
  -- The median number of statuses active at a dawn, over every day of every run: 0 means most days are clear.
  local days = 0
  for _, n in pairs(out.statusHist) do
    days = days + n
  end
  local seen, median = 0, 0
  for count = 0, out.maxStatuses do
    seen = seen + (out.statusHist[count] or 0)
    if seen * 2 >= days then
      median = count
      break
    end
  end
  out.medianStatuses = median
  out.shareWithStatus = days > 0 and out.statusDays / days or 0
  return out
end

--- Footing across runs (D165, #344), every run counted: how many earned it, the day (median, p10, p90 of those that
--- did), how many did so before the first frozen season began, slips per run, and the mean number of dusk nights
--- (before it was earned) that failed each of the four tests. Reporting only: nothing gates on it.
function Balance.footingSummary(results)
  local f = { n = #results, reached = 0, beforeWinter = 0, slippedRuns = 0 }
  local days, slips = {}, {}
  local fail, failFuel, nights = { shelter = 0, water = 0, fuel = 0, food = 0 }, {}, 0
  for _, r in ipairs(results) do
    local x = r.footing
    slips[#slips + 1] = x.slips
    if x.slips > 0 then
      f.slippedRuns = f.slippedRuns + 1
    end
    if x.gainedDay then
      f.reached = f.reached + 1
      days[#days + 1] = x.gainedDay
      if x.winterDay and x.gainedDay < x.winterDay then
        f.beforeWinter = f.beforeWinter + 1
      end
    end
    nights = nights + x.nights
    for id, count in pairs(x.fail) do
      fail[id] = fail[id] + count
    end
    for season, count in pairs(x.failFuel) do
      failFuel[season] = (failFuel[season] or 0) + count
    end
  end
  local n = math.max(1, #results)
  f.reachedFraction = f.reached / n
  f.beforeWinterFraction = f.beforeWinter / n
  f.day = quantiles(days) -- nil when no run reached it
  f.slips = quantiles(slips)
  local sum = 0
  for _, v in ipairs(slips) do
    sum = sum + v
  end
  f.slipsMean = sum / n
  f.nightsMean = nights / n
  f.failMean, f.failFuelMean = {}, {}
  for id, count in pairs(fail) do
    f.failMean[id] = count / n
  end
  for season, count in pairs(failFuel) do
    f.failFuelMean[season] = count / n
  end
  return f
end

--- Crops across runs (D177, #363), reporting only: the starter crops' share of what the farm sold (the check that
--- starting-crop income does not fund the mid game, #263) and how many kinds were planted each year.
function Balance.cropsSummary(ctx, results, years)
  local perYear = #ctx.tuning.time.seasons * ctx.tuning.time.daysPerSeason
  local shares, starterSales, allSales = {}, 0, 0
  for _, r in ipairs(results) do
    local s = r.sales or { all = 0, crops = 0, starter = 0 }
    starterSales, allSales = starterSales + s.starter, allSales + s.all
    if s.all > 0 then
      shares[#shares + 1] = s.starter / s.all
    end
  end
  local out = {
    starterShare = quantiles(shares), -- per run: starter-crop sales / all sales, runs that sold anything
    starterSalesMean = starterSales / math.max(1, #results), -- $ per run
    salesMean = allSales / math.max(1, #results), -- $ per run, every good
    starterCrops = #ctx.tuning.farming.starterField,
    planted = {}, -- year -> { kinds = quantiles of distinct crops planted, beyondStarters = share of runs planting another }
  }
  local starter = {}
  for _, entry in ipairs(ctx.tuning.farming.starterField) do
    starter[entry.crop] = true
  end
  for year = 1, years do
    local kinds, beyond, n = {}, 0, 0
    for _, r in ipairs(results) do
      if r.snaps[(year - 1) * perYear + 1] or year == 1 then
        local count, other = 0, false
        for crop in pairs((r.plantedByYear or {})[year] or {}) do
          count = count + 1
          other = other or not starter[crop]
        end
        kinds[#kinds + 1] = count
        beyond, n = beyond + (other and 1 or 0), n + 1
      end
    end
    if n > 0 then
      out.planted[year] = { kinds = quantiles(kinds), beyondStarters = beyond / n, n = n }
    end
  end
  return out
end

--- Spiral measures across runs (#410, PLAN_DEPTH §15), every run counted. A slip is Footing lost after it was held; a
--- spiral is a run that slipped and then died while still slipped. Reporting plus the gate in gates.lua.
function Balance.spiralSummary(results)
  local out = {
    n = #results,
    slippedRuns = 0,
    slips = 0,
    diedSlipped = 0, -- runs that ended in death with Footing held but slipped
    diedNeverFooted = 0, -- runs that died before they ever earned Footing
    slippedDays = 0, -- mornings spent slipped, summed
    yearOneStarved = 0, -- runs that died of hunger in year 1
    yearOneFailed = 0,
  }
  for _, r in ipairs(results) do
    local x = r.footing
    out.slips = out.slips + x.slips
    out.slippedRuns = out.slippedRuns + (x.slips > 0 and 1 or 0)
    out.slippedDays = out.slippedDays + (r.spiral and r.spiral.slippedDays or 0)
    if not r.alive then
      out.diedSlipped = out.diedSlipped + (r.spiral and r.spiral.diedSlipped and 1 or 0)
      out.diedNeverFooted = out.diedNeverFooted + (x.gainedDay and 0 or 1)
      if r.failYear == 1 then
        out.yearOneFailed = out.yearOneFailed + 1
        out.yearOneStarved = out.yearOneStarved + (r.cause == "hunger" and 1 or 0)
      end
    end
  end
  local n = math.max(1, #results)
  out.slipsPerRun = out.slips / n
  out.slippedDaysPerRun = out.slippedDays / n
  out.slipToDeath = out.slippedRuns > 0 and out.diedSlipped / out.slippedRuns or nil -- nil: nothing slipped
  return out
end

--- The paired events-on/off comparison (#410) over runs that carry their events-off twin (nil when none do). The share that
--- fail with events on and live with them off is the measure of event-caused failure (PLAN_DEPTH §15).
function Balance.pairedSummary(results)
  local out = {
    n = 0,
    mode = results[1] and results[1].events and results[1].events.mode or nil,
    bothAlive = 0,
    bothFailed = 0,
    onlyOnFailed = 0, -- the event-caused failures
    onlyOffFailed = 0, -- the opposite (noise: the runs diverge as soon as an event lands)
    onlyOn = {}, -- the seeds behind onlyOnFailed, as { seed, run, day, cause }
    causes = {}, -- failure cause of the event-caused failures
  }
  for _, r in ipairs(results) do
    if r.off then
      out.n = out.n + 1
      if r.alive and r.off.alive then
        out.bothAlive = out.bothAlive + 1
      elseif not r.alive and not r.off.alive then
        out.bothFailed = out.bothFailed + 1
      elseif not r.alive then
        out.onlyOnFailed = out.onlyOnFailed + 1
        out.causes[r.cause] = (out.causes[r.cause] or 0) + 1
        out.onlyOn[#out.onlyOn + 1] = { seed = r.baseSeed, run = r.run, day = r.failDay, cause = r.cause }
      else
        out.onlyOffFailed = out.onlyOffFailed + 1
      end
    end
  end
  if out.n == 0 then
    return nil
  end
  out.eventCausedShare = out.onlyOnFailed / out.n
  out.onFailedShare = (out.bothFailed + out.onlyOnFailed) / out.n
  out.offFailedShare = (out.bothFailed + out.onlyOffFailed) / out.n
  return out
end

--- Aggregate run results (all of one policy and run index) into a summary table.
function Balance.summarize(ctx, results, years, policyName)
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
  summary.footing = Balance.footingSummary(results)
  summary.crops = Balance.cropsSummary(ctx, results, years)
  summary.events = Balance.eventsSummary(results)
  summary.spiral = Balance.spiralSummary(results)
  summary.paired = Balance.pairedSummary(results)
  summary.gates = Gates.evaluate(policyName or results[1].policy, summary)
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

--- The events block of a summary (nothing when events were off).
function Balance.printEvents(e)
  if not e then
    return
  end
  line("")
  line(
    string.format(
      "Events (%s): %.1f offered per run (all runs: chosen %d, ignored %d); days with a status per run %.1f (%.0f%% of days); median statuses active %d; most statuses at once %d; lowest Condition %.0f",
      e.mode,
      e.offeredPerRun,
      e.chosen,
      e.ignored,
      e.statusDaysPerRun,
      e.shareWithStatus * 100,
      e.medianStatuses,
      e.maxStatuses,
      e.minCondition
    )
  )
  local ids = {}
  for id in pairs(e.by) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local by = e.by[id]
    line(string.format("  %-20s offered %d  chosen %d  ignored %d", id, by.offered, by.chosen, by.ignored))
  end
end

--- The Footing block of a summary (D165, #344): reporting only, no target.
function Balance.printFooting(ctx, f)
  local d = f.day
  line("")
  line(
    string.format(
      "Footing: reached %d/%d runs (%s), before the first winter %d/%d (%s); day of Footing median %s  p10 %s  p90 %s (of those that reached it)",
      f.reached,
      f.n,
      pct(f.reachedFraction),
      f.beforeWinter,
      f.n,
      pct(f.beforeWinterFraction),
      d and num(d.p50, 1) or "never",
      d and num(d.p10, 1) or "-",
      d and num(d.p90, 1) or "-"
    )
  )
  line(
    string.format(
      "  slips per run: mean %.2f  median %s  p90 %s  (%d runs slipped at least once)",
      f.slipsMean,
      num(f.slips.p50, 1),
      num(f.slips.p90, 1),
      f.slippedRuns
    )
  )
  local fuel = {}
  for _, season in ipairs(ctx.tuning.time.seasons) do
    if f.failFuelMean[season] then
      fuel[#fuel + 1] = string.format("%s %.1f", season, f.failFuelMean[season])
    end
  end
  line(
    string.format(
      "  dusk nights judged before Footing, per run: %.1f; failing shelter %.1f, water %.1f, fuel %.1f, food %.1f; short of fuel by season: %s",
      f.nightsMean,
      f.failMean.shelter,
      f.failMean.water,
      f.failMean.fuel,
      f.failMean.food,
      #fuel > 0 and table.concat(fuel, ", ") or "none"
    )
  )
end

--- The spiral, paired and gate blocks of a summary (#410). Gates print for every policy; the paired block only for a
--- paired run (`pair=1`).
function Balance.printSpiral(sp)
  line("")
  line(
    string.format(
      "Spiral: %.2f slips per run, %.1f mornings slipped per run; %s; died before ever earning Footing %d/%d; year-1 deaths %d (hunger %d)",
      sp.slipsPerRun,
      sp.slippedDaysPerRun,
      sp.slipToDeath
          and string.format("slip-to-death %d/%d runs (%s)", sp.diedSlipped, sp.slippedRuns, pct(sp.slipToDeath))
        or "no run slipped",
      sp.diedNeverFooted,
      sp.n,
      sp.yearOneFailed,
      sp.yearOneStarved
    )
  )
end

function Balance.printPaired(p)
  if not p then
    return
  end
  line("")
  line(
    string.format(
      "Paired events off/on (%s) over %d seeds: fail with events on %s, off %s; both live %d, both fail %d, "
        .. "fail only with events on %d (%s), fail only with them off %d",
      p.mode or "?",
      p.n,
      pct(p.onFailedShare),
      pct(p.offFailedShare),
      p.bothAlive,
      p.bothFailed,
      p.onlyOnFailed,
      pct(p.eventCausedShare),
      p.onlyOffFailed
    )
  )
  for _, f in ipairs(p.onlyOn) do
    line(
      string.format(
        "  event-caused failure: seed %d run %d, day %s, %s",
        f.seed,
        f.run,
        tostring(f.day),
        tostring(f.cause)
      )
    )
  end
end

function Balance.printGates(gates)
  if not gates or #gates == 0 then
    return
  end
  line("")
  line("Gates (first-guess limits in tools/balance/gates.lua):")
  for _, g in ipairs(gates) do
    local tag = g.pass == nil and "n/a " or (g.pass and "PASS" or "FAIL")
    if g.value == nil then
      line(string.format("  [%s] %s: %s", tag, g.text, g.note or "nothing to measure"))
    else
      line(
        string.format(
          "  [%s] %s: %s (need %s %s)",
          tag,
          g.text,
          pct(g.value),
          g.atLeast and "at least" or "at most",
          pct(g.limit)
        )
      )
    end
  end
end

--- Print the human-readable report for one (policy, run index) summary.
function Balance.printSummary(ctx, policyName, runIndex, summary, years)
  line("")
  line(string.rep("=", 100))
  line(
    string.format(
      "policy %-9s run %d   seeds: %d   (%s)",
      policyName,
      runIndex,
      summary.n,
      Policies.describe[policyName]
    )
  )
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
    for _, c in ipairs({ "cold", "hunger", "thirst", "both" }) do
      if summary.causes[c] then
        causes[#causes + 1] = string.format("%s: %d", c, summary.causes[c])
      end
    end
    line("Failure causes (dominant source of Condition loss): " .. table.concat(causes, "   "))
  end

  Balance.printFooting(ctx, summary.footing)
  Balance.printEvents(summary.events)
  Balance.printSpiral(summary.spiral)
  Balance.printPaired(summary.paired)
  Balance.printGates(summary.gates)

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
      "Water per run (mean): waterings by hand %.0f, by sprinkler %.0f, by drip %.0f; cistern units pumped %.0f, rained %.0f; rain days %.1f, cloudy days %.1f",
      q("waterHand").mean,
      q("waterSprinkler").mean,
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
  local harvests = math.max(1, q("harvests").mean)
  line(
    string.format(
      "Rotation per run (mean): %.0f harvests, %.0f%% repeating the tile's family, yield cut by pest pressure %.1f%% on average, "
        .. "zero-yield harvests %.0f, pest hits %.1f, blight outbreaks %.2f",
      q("harvests").mean,
      100 * q("harvestsRepeat").mean / harvests,
      100 * q("pressureCut").mean / harvests,
      q("zeroYields").mean,
      q("pestHits").mean,
      q("blightOutbreaks").mean
    )
  )
  line(
    string.format(
      "Weeds and compost per run (mean): yield cut by weeds %.1f%% on average, %.0f tiles pulled, %.1f overgrown tile-days, "
        .. "compost made %.1f and spread on %.1f tiles",
      100 * q("weedCut").mean / harvests,
      q("weedsPulled").mean,
      q("weedyDays").mean,
      q("compostMade").mean,
      q("compostSpread").mean
    )
  )
  line(
    string.format(
      "Quality per run (mean): %.0f%% of harvests fine (healthy soil earns it, whoever tends it, D185)",
      100 * q("qualityFine").mean / harvests
    )
  )
  line(
    string.format(
      "Perennials per run (mean): %.1f planted, %.1f young and %.1f established harvests, %.0f fruit picked, "
        .. "%.1f built over or pulled, %.1f crops stripped by a threat",
      q("plantsPlanted").mean,
      q("fruitFirst").mean,
      q("fruitFull").mean,
      q("fruitUnits").mean,
      q("plantsRemoved").mean,
      q("fruitLost").mean
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
  Balance.printCrops(summary.crops, years)
end

--- The crops block of a summary (D177, #363): reporting only, no target. The share is the check behind #263: how much
--- of what the farm sold came from the two starter crops, which must not carry the mid game.
function Balance.printCrops(c, years)
  if not c then
    return
  end
  local share = c.starterShare
  line(
    string.format(
      "Starter-crop income (the #263 check): %s of sales value median%s, $%.0f of $%.0f per run (mean)",
      share and pct(share.p50) or "-",
      share and string.format(" [p25-p75 %s-%s]", pct(share.p25), pct(share.p75)) or "",
      c.starterSalesMean,
      c.salesMean
    )
  )
  for year = 1, years do
    local p = c.planted[year]
    if p then
      line(
        string.format(
          "Crop kinds planted year %d (median of %d): %s; runs that planted a crop beyond the starters %s",
          year,
          p.n,
          num(p.kinds.p50, 0),
          pct(p.beyondStarters)
        )
      )
    end
  end
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

--- CSV with one row per seed per run per day snapshot. `footing` is 0 not held, 1 held, 2 slipped on that morning;
--- `footingDay` (empty if never earned) and `footingSlips` are the run's totals, repeated on each row.
function Balance.writeCsv(path, all)
  local fh = assert(io.open(path, "w"))
  fh:write(
    "policy,seed,run,day,year,season,dayOfSeason,condition,money,foodDays,warmth,warmthNights,notes,known,ideas,failedAtEnd,footing,footingDay,footingSlips\n"
  )
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
          "%s,%d,%d,%d,%d,%s,%d,%.1f,%d,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%s,%d\n",
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
          r.alive and 0 or 1,
          s.footing,
          r.footing.gainedDay and tostring(r.footing.gainedDay) or "",
          r.footing.slips
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
  line(
    string.format(
      "trace: policy %s seed %d run %d  %s",
      r.policy,
      r.baseSeed,
      r.run,
      r.alive and "survived" or ("failed on day " .. r.failDay .. " (" .. tostring(r.cause) .. ")")
    )
  )
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
        day,
        x.season,
        x.condition,
        x.money,
        x.foodDays,
        x.warmth,
        x.notes,
        x.known,
        x.ideas
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
    footing = r.footing,
    spiral = r.spiral,
    events = r.events,
    off = r.off,
  }
end

return Balance
