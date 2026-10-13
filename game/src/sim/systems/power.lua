-- Power network (GDD §7.5, §7.6). Sources make power, batteries buffer it, sinks draw it, and a
-- priority list decides who is served first when there is not enough.
--
-- Content (data/content/objects.lua):
--   source  { curve = "solar"|"wind"|"hydro"|"fuel", peak kW }   (fuel adds fuel, fuelPerKwh)
--   battery kWh, with optional maxRate (kW), efficiency (kept fraction when charging), vehicle
--   sink    { tier, draw kW, schedule = "always"|"dark"|"heat"|"fill"|"demand", inertia hours, effects }
--           ("fill" wants power only while resource `fills` has storage room: pumps, #35;
--           "demand" wants power only while its owner asks for it with Power.request: machines, #42)
-- Knobs live in data/tuning/power.lua; weather inputs come from Weather.powerInputs (#39).
--
-- Each tick, in priority order (state.order: sink tiers and the charge tiers "bank"/"truck"):
--   1. Generation (solar, wind, hydro) is handed out: a sink tier takes what it wants, a charge
--      tier fills its batteries (losing a little to the battery's efficiency).
--   2. A sink tier still short is topped up from batteries (home bank first, then the truck, but
--      only charge above the truck's trip reserve), then by a generator if one has fuel.
--   3. Whatever is left over is wasted (every battery full or rate-limited).
-- A tier's satisfaction is served / wanted; every sink in the tier gets that ratio. Systems that
-- run on power (pumps #35, machines #42) read `Power.sinkRatio(world, anchor)` and slow down by it.
-- The truck is just a vehicle battery: sinks are served before the truck charges (unless the player
-- moves "truck" up the list), so a heavy winter load starves the charging for a trip.
--
-- State: world.state.power = {
--   charge = { [anchor] = kWh }, off = { [anchor] = true } (switched off by the player),
--   order = { tier ids }, truckLends = bool, held = { [anchor] = 0..1 } (smoothed satisfaction),
--   wind = { value, target, hour }, tank = fuel units in the generator, warmth = warmth made by
--   electric heating since the last night, full = { [anchor] = true }, warned = { [tier] = day },
--   requests = { [anchor] = true } ("demand" sinks asking for power on the next tick),
--   flow = last tick's numbers for the UI (see emptyFlow) }
-- Emits "power.full" { battery } when a battery fills, "power.brownout" { tier, ratio } at most
-- once a day per tier when a tier is served less than it wants.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Shelter = require("src.sim.systems.shelter")
local Weather = require("src.sim.systems.weather")

local Power = {}

local function state(world)
  return world.state.power
end

local function emptyFlow()
  return {
    generation = 0, -- kW made by sources this tick
    demand = 0, -- kW the sinks wanted
    served = 0, -- kW the sinks got
    charging = 0, -- kW that went into batteries
    discharging = 0, -- kW taken from batteries
    wasted = 0, -- kW generated with nowhere to go
    tiers = {}, -- tier id -> { demand, served, charging } (charging: kW a charge tier put into batteries)
    sinks = {}, -- anchor -> { demand, ratio }
    sources = {}, -- anchor -> kW now
    rates = {}, -- battery anchor -> net kW stored this tick (charging after efficiency, less what was drawn)
    effects = {}, -- effect name -> strength (sum over sinks of effect * held satisfaction)
  }
end

local function reconcileOrder(world, order)
  local cfg = world.tuning.power
  local known, result = {}, {}
  for _, id in ipairs(cfg.defaultOrder) do
    known[id] = true
  end
  for _, id in ipairs(order or {}) do
    if known[id] then
      result[#result + 1] = id
      known[id] = nil
    end
  end
  for _, id in ipairs(cfg.defaultOrder) do
    if known[id] then
      result[#result + 1] = id
    end
  end
  return result
end

function Power.init(world)
  local s = world.state.power or {}
  world.state.power = s
  -- A fresh run starts empty: fill in the fields.
  s.charge = s.charge or {}
  s.off = s.off or {}
  s.held = s.held or {}
  s.full = s.full or {}
  s.warned = s.warned or {}
  s.requests = s.requests or {}
  if s.truckLends == nil then
    s.truckLends = true
  end
  s.wind = s.wind or { value = world.tuning.power.wind.start, target = world.tuning.power.wind.start, hour = -1 }
  s.tank = s.tank or 0
  s.warmth = s.warmth or 0
  s.flow = s.flow or emptyFlow()
  s.order = reconcileOrder(world, s.order)
end

-- Sources -------------------------------------------------------------------------------------

--- Solar intensity 0..1 for the current hour: a sine arc between the season's sunrise and sunset,
--- scaled by the season's output (low sun and snow on the panels in winter) and by cloud cover.
local function sunAt(world, now, env)
  local daylight = world.tuning.time.daylight[now.season]
  local sunrise, sunset = daylight[1], daylight[2]
  if now.hour <= sunrise or now.hour >= sunset then
    return 0
  end
  local arc = math.sin(math.pi * (now.hour - sunrise) / (sunset - sunrise))
  return arc * world.tuning.power.seasonalOutput[now.season] * (1 - env.cloud)
end

function Power.sun(world)
  return sunAt(world, Calendar.now(world), Weather.powerInputs(world))
end

--- Wind strength 0..1 right now (the model behind turbine output).
function Power.wind(world)
  return state(world).wind.value
end

-- A new random wind target each in-game hour; the wind eases toward it.
local function updateWind(world, hours, now)
  local wind, cfg = state(world).wind, world.tuning.power.wind
  local hour = (now.day - 1) * 24 + math.floor(now.hour)
  if hour ~= wind.hour then
    wind.hour = hour
    wind.target = world:rng("wind"):float()
  end
  wind.value = wind.value + (wind.target - wind.value) * math.min(1, hours / cfg.easeHours)
end

-- kW a non-fuel source makes at its peak scaled by the current conditions.
local function sourceOutput(world, src, now, env)
  local cfg = world.tuning.power
  local season = now.season
  if src.curve == "solar" then
    return src.peak * sunAt(world, now, env)
  elseif src.curve == "wind" then
    local w = cfg.wind
    return src.peak * cfg.curves.wind[season] * (w.floor + (1 - w.floor) * state(world).wind.value) * env.wind
  elseif src.curve == "hydro" then
    return src.peak * cfg.curves.hydro[season] * env.flow
  end
  error("unknown power curve '" .. tostring(src.curve) .. "'")
end

-- Anchors of power objects (sources, batteries, sinks), sorted so every pass is deterministic.
-- The lists are Grid's cached index (read-only), not rebuilt every tick.
local function scan(world)
  return Grid.anchorsWith(world, "source"), Grid.anchorsWith(world, "sink"), Grid.anchorsWith(world, "battery")
end

local function defAt(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id)
end

--- Peak kW of every source (all panels in full sun, turbines in a steady breeze, ...).
function Power.peak(world)
  local total = 0
  for _, obj in pairs(world.state.grid.objects) do
    local src = world.registry:get("objects", obj.id).source
    if src then
      total = total + src.peak
    end
  end
  return total
end

--- kW all sources are making right now (generators only while they run).
function Power.output(world)
  return state(world).flow.generation
end

-- Batteries -----------------------------------------------------------------------------------

function Power.charge(world, anchor)
  return state(world).charge[anchor] or 0
end

function Power.capacity(world, anchor)
  local obj = world.state.grid.objects[anchor]
  return obj and world.registry:get("objects", obj.id).battery or 0
end

--- Net kW going into a battery as of the last tick (negative while it lends power). 0 for a save
--- from before this was tracked, until its next tick.
function Power.chargeRate(world, anchor)
  local rates = state(world).flow.rates
  return rates and rates[anchor] or 0
end

--- In-game hours until a battery holds `target` kWh at its current net rate: 0 when it already does,
--- nil when it is not charging (or `target` is more than it can hold).
function Power.hoursToCharge(world, anchor, target)
  local charge = Power.charge(world, anchor)
  if charge >= target then
    return 0
  end
  local rate = Power.chargeRate(world, anchor)
  if rate <= 0 or target > Power.capacity(world, anchor) then
    return nil
  end
  return (target - charge) / rate
end

--- Remove `amount` kWh from a battery. Returns true if it had enough.
function Power.drain(world, anchor, amount)
  local charge = Power.charge(world, anchor)
  if charge < amount then
    return false
  end
  state(world).charge[anchor] = charge - amount
  return true
end

--- Add `amount` kWh to a battery, limited by its capacity. Returns the amount stored.
function Power.add(world, anchor, amount)
  local stored = math.max(0, math.min(amount, Power.capacity(world, anchor) - Power.charge(world, anchor)))
  state(world).charge[anchor] = Power.charge(world, anchor) + stored
  return stored
end

--- Forget everything the network holds for the object at `anchor` (it was picked up, D98).
function Power.forget(world, anchor)
  local s = state(world)
  s.charge[anchor], s.off[anchor], s.held[anchor], s.full[anchor], s.requests[anchor] = nil, nil, nil, nil, nil
end

--- Carry what the network holds for the object at `from` (charge, switched-off, smoothed satisfaction) to
--- `to`, where it was moved (D98). Nothing is left at `from`.
function Power.relocate(world, from, to)
  local s = state(world)
  for _, key in ipairs({ "charge", "off", "held", "full" }) do
    s[key][to], s[key][from] = s[key][from], nil
  end
  s.requests[from] = nil
end

--- Charge and capacity (kWh) of the home batteries (everything but the truck): { charge, capacity }.
function Power.bank(world)
  local charge, capacity = 0, 0
  local _, _, banks = scan(world)
  for _, anchor in ipairs(banks) do
    if not defAt(world, anchor).vehicle then
      charge = charge + Power.charge(world, anchor)
      capacity = capacity + Power.capacity(world, anchor)
    end
  end
  return { charge = charge, capacity = capacity }
end

-- Sinks ---------------------------------------------------------------------------------------

--- Has the player left this sink or generator switched on?
function Power.isEnabled(world, anchor)
  return not state(world).off[anchor]
end

function Power.setEnabled(world, anchor, enabled)
  state(world).off[anchor] = (not enabled) or nil
end

--- Does the truck lend charge above its trip reserve to the homestead?
function Power.truckLends(world)
  return state(world).truckLends
end

function Power.setTruckLends(world, lends)
  state(world).truckLends = lends and true or false
end

--- Priority order of tier ids (read-only copy), first served first.
function Power.order(world)
  local copy = {}
  for i, id in ipairs(state(world).order) do
    copy[i] = id
  end
  return copy
end

--- Move a tier up (delta -1) or down (delta 1) the priority list. Returns true if it moved.
function Power.moveTier(world, id, delta)
  local order = state(world).order
  for i, tier in ipairs(order) do
    if tier == id then
      local j = i + delta
      if j < 1 or j > #order then
        return false
      end
      order[i], order[j] = order[j], order[i]
      return true
    end
  end
  return false
end

function Power.tierName(world, id)
  return world.tuning.power.tierNames[id]
end

--- Ask for power for a "demand" sink (a machine with work, #42) from the next tick on, or stop
--- asking. The request is saved with the power state, so a loaded game draws exactly as before.
function Power.request(world, anchor, wants)
  state(world).requests[anchor] = wants and true or nil
end

--- Is this "demand" sink asking for power?
function Power.requested(world, anchor)
  return state(world).requests[anchor] == true
end

--- Does this sink want power right now? (Not counting the player's switch.)
local function wantsPower(world, sink, now, thermostat, anchor)
  local daylight = world.tuning.time.daylight[now.season]
  local dark = now.hour < daylight[1] or now.hour >= daylight[2]
  if sink.schedule == "always" then
    return true
  elseif sink.schedule == "dark" then
    return dark
  elseif sink.schedule == "heat" then
    -- Heats in the dark of cold seasons until tonight's warmth is made (a thermostat).
    return dark and thermostat.need > 0 and state(world).warmth < thermostat.need
  elseif sink.schedule == "fill" then
    -- Runs while there is room in the store it fills (a pump with an empty cistern; sink.fills is a resource id).
    return Ledger.room(world, sink.fills) > 0
  elseif sink.schedule == "demand" then
    -- Runs only while its owner has work and asks (a machine; see Power.request).
    return state(world).requests[anchor] == true
  end
  error("unknown sink schedule '" .. tostring(sink.schedule) .. "'")
end

--- Satisfaction (0..1) of a tier last tick: served / wanted (1 when nothing is wanted).
function Power.tierRatio(world, id)
  local t = state(world).flow.tiers[id]
  if not t or t.demand <= 0 then
    return 1
  end
  return t.served / t.demand
end

--- Satisfaction (0..1) of a sink last tick (1 when it wanted nothing). Powered systems scale their
--- work by this.
function Power.sinkRatio(world, anchor)
  local s = state(world).flow.sinks[anchor]
  return s and s.ratio or 1
end

--- Overall satisfaction (0..1): power served / power wanted across all sinks (1 when idle).
function Power.satisfaction(world)
  local flow = state(world).flow
  if flow.demand <= 0 then
    return 1
  end
  return flow.served / flow.demand
end

--- What a sink is doing: "off" (switched off), "idle" (nothing to do right now), "ok", "short".
function Power.sinkState(world, anchor)
  if not Power.isEnabled(world, anchor) then
    return "off"
  end
  local s = state(world).flow.sinks[anchor]
  if not s or s.demand <= 0 then
    return "idle"
  end
  return s.ratio >= 1 - world.tuning.power.overdrawEpsilon and "ok" or "short"
end

--- Sinks in anchor order: { anchor, id, name, tier, draw, demand, ratio, state, enabled }.
function Power.sinkList(world)
  local list = {}
  local _, sinks = scan(world)
  for _, anchor in ipairs(sinks) do
    local def = defAt(world, anchor)
    local s = state(world).flow.sinks[anchor]
    list[#list + 1] = {
      anchor = anchor,
      id = def.id,
      name = def.name,
      tier = def.sink.tier,
      draw = def.sink.draw,
      demand = s and s.demand or 0,
      ratio = s and s.ratio or 1,
      state = Power.sinkState(world, anchor),
      enabled = Power.isEnabled(world, anchor),
    }
  end
  return list
end

--- Sources in anchor order: { anchor, id, name, curve, peak, output, enabled (generators) }.
function Power.sourceList(world)
  local list = {}
  local sources = scan(world)
  for _, anchor in ipairs(sources) do
    local def = defAt(world, anchor)
    list[#list + 1] = {
      anchor = anchor,
      id = def.id,
      name = def.name,
      curve = def.source.curve,
      peak = def.source.peak,
      output = state(world).flow.sources[anchor] or 0,
      enabled = Power.isEnabled(world, anchor),
    }
  end
  return list
end

--- kW one source is making right now (0 for a generator that is not running).
function Power.outputOf(world, anchor)
  return state(world).flow.sources[anchor] or 0
end

--- Last tick's flows: { generation, demand, served, charging, discharging, wasted, tiers = { id ->
--- { demand, served } } } in kW. Read-only.
function Power.flow(world)
  return state(world).flow
end

--- Strength of an effect from powered sinks (see sink.effects in content), e.g. "studySpeed" or
--- "spoilSlow": the sum over sinks of effect * how well each is powered.
function Power.effect(world, name)
  return state(world).flow.effects[name] or 0
end

--- Warmth made by electric heating since it was last taken, then reset. The night's warmth need
--- calls this, so heaters stand in for firewood (GDD §4.2).
function Power.takeWarmth(world)
  local s = state(world)
  local warmth = s.warmth
  s.warmth = 0
  return warmth
end

-- The tick ------------------------------------------------------------------------------------

-- Fill batteries of one class (vehicle or home) from `avail` kW. Returns kW used.
-- `commit` false solves without changing any stored charge (the on-demand refresh, Power.refresh).
local function chargeBatteries(world, banks, vehicle, avail, hours, flow, commit)
  local used = 0
  local s = state(world)
  for _, anchor in ipairs(banks) do
    local def = defAt(world, anchor)
    if avail - used > 0 and (def.vehicle == true) == vehicle then
      local room = def.battery - (s.charge[anchor] or 0)
      local eff = def.efficiency or 1
      local power = math.min(avail - used, room / (hours * eff), def.maxRate or math.huge)
      if power > 0 then
        if commit then
          s.charge[anchor] = (s.charge[anchor] or 0) + power * hours * eff
        end
        flow.rates[anchor] = (flow.rates[anchor] or 0) + power * eff
        used = used + power
      end
    end
  end
  return used
end

-- kW a battery can give now (rate- and charge-limited; the truck keeps its trip reserve).
local function dischargeLimit(world, anchor, hours)
  local s, cfg = state(world), world.tuning.power
  local def = defAt(world, anchor)
  local floor = 0
  if def.vehicle then
    if not s.truckLends then
      return 0
    end
    floor = cfg.truckReserveKwh
  end
  return math.min(math.max(0, (s.charge[anchor] or 0) - floor) / hours, def.maxRate or math.huge)
end

-- Draw up to `need` kW from batteries, home bank first. Returns kW delivered.
local function dischargeBatteries(world, banks, need, hours, flow, commit)
  local s = state(world)
  local got = 0
  for pass = 1, 2 do
    for _, anchor in ipairs(banks) do
      local vehicle = defAt(world, anchor).vehicle == true
      if need - got > 0 and vehicle == (pass == 2) then
        local power = math.min(need - got, dischargeLimit(world, anchor, hours))
        if power > 0 then
          if commit then
            s.charge[anchor] = s.charge[anchor] - power * hours
          end
          flow.rates[anchor] = (flow.rates[anchor] or 0) - power
          got = got + power
        end
      end
    end
  end
  return got
end

-- Run generators for up to `need` kW (fuel permitting). `left` tracks each generator's spare kW
-- this tick. Returns kW delivered.
local function runGenerators(world, gens, left, need, hours, flow, commit, spent)
  local s = state(world)
  local got = 0
  for _, anchor in ipairs(gens) do
    local src = defAt(world, anchor).source
    if need - got > 0 and Power.isEnabled(world, anchor) and left[anchor] > 0 then
      -- A refresh burns nothing, so it tracks the fuel earlier generators would have used in `spent`.
      local fuelUnits = s.tank + Ledger.get(world, src.fuel) - (commit and 0 or spent.fuel)
      local power = math.min(need - got, left[anchor], fuelUnits / (src.fuelPerKwh * hours))
      if power > 0 then
        local burn = power * hours * src.fuelPerKwh
        if commit then
          while s.tank < burn and Ledger.remove(world, src.fuel, 1, "generator") do
            s.tank = s.tank + 1
          end
          s.tank = math.max(0, s.tank - burn)
        else
          spent.fuel = spent.fuel + burn
        end
        left[anchor] = left[anchor] - power
        flow.sources[anchor] = (flow.sources[anchor] or 0) + power
        got = got + power
      end
    end
  end
  return got
end

local scratchTiers = {}

-- One solve of the network over `hours`. With `commit` it is the real tick (batteries, fuel, wind,
-- held satisfaction, warmth and announcements all change); without, it only rebuilds state.flow, so
-- the panel can show the effect of a player change while the game is paused (Power.refresh).
local function solve(world, hours, commit)
  local s, cfg = state(world), world.tuning.power
  local now = Calendar.now(world)
  local env = Weather.powerInputs(world)
  if commit then
    updateWind(world, hours, now)
  end
  local sources, sinks, banks = scan(world)

  local flow = emptyFlow()
  s.flow = flow
  local spent = { fuel = 0 }

  -- Generation from the weather-driven sources; generators wait until they are needed.
  local gens, left = {}, {}
  local generation = 0
  for _, anchor in ipairs(sources) do
    local src = defAt(world, anchor).source
    if src.curve == "fuel" then
      gens[#gens + 1] = anchor
      left[anchor] = src.peak
      flow.sources[anchor] = 0
    else
      local out = sourceOutput(world, src, now, env)
      flow.sources[anchor] = out
      generation = generation + out
    end
  end

  -- Demand per tier.
  local thermostat = { need = 0 }
  for _, anchor in ipairs(sinks) do
    if defAt(world, anchor).sink.schedule == "heat" then
      thermostat.need = Weather.warmthNeed(world) * Shelter.insulation(world)
      break
    end
  end
  -- Per-tick scratch (never saved, never read after this tick): reused so a tick allocates less.
  local tiers = scratchTiers
  for _, id in ipairs(s.order) do
    local tier = tiers[id]
    if not tier then
      tier = {}
      tiers[id] = tier
    end
    tier.demand, tier.served, tier.direct, tier.charging = 0, 0, 0, 0
  end
  local demanded = {}
  for _, anchor in ipairs(sinks) do
    local sink = defAt(world, anchor).sink
    local want = Power.isEnabled(world, anchor) and wantsPower(world, sink, now, thermostat, anchor) and sink.draw or 0
    demanded[anchor] = want
    tiers[sink.tier].demand = tiers[sink.tier].demand + want
  end

  -- Pass 1: generation, in priority order.
  local avail = generation
  for _, id in ipairs(s.order) do
    local tier = tiers[id]
    if tier.demand > 0 then
      tier.direct = math.min(avail, tier.demand)
      avail = avail - tier.direct
    elseif rawget(cfg.chargeTiers, id) ~= nil then -- a charge tier (the strict table errors on other ids)
      local used = chargeBatteries(world, banks, rawget(cfg.chargeTiers, id), avail, hours, flow, commit)
      tier.charging = used
      avail = avail - used
      flow.charging = flow.charging + used
    end
  end

  -- Pass 2: tiers still short draw on batteries, then generators.
  local generated = generation
  for _, id in ipairs(s.order) do
    local tier = tiers[id]
    tier.served = tier.direct
    local need = tier.demand - tier.direct
    if need > cfg.overdrawEpsilon then
      local fromBattery = dischargeBatteries(world, banks, need, hours, flow, commit)
      flow.discharging = flow.discharging + fromBattery
      local fromGenerator = runGenerators(world, gens, left, need - fromBattery, hours, flow, commit, spent)
      generated = generated + fromGenerator
      tier.served = tier.direct + fromBattery + fromGenerator
    end
    flow.tiers[id] = { demand = tier.demand, served = tier.served, charging = tier.charging }
    flow.demand = flow.demand + tier.demand
    flow.served = flow.served + tier.served
  end
  flow.generation = generated
  flow.wasted = math.max(0, avail)

  -- Per-sink results, held satisfaction, effects and warmth.
  local day = now.day
  for _, anchor in ipairs(sinks) do
    local def = defAt(world, anchor)
    local sink = def.sink
    local tier = tiers[sink.tier]
    local want = demanded[anchor]
    local ratio = tier.demand > 0 and tier.served / tier.demand or 1
    flow.sinks[anchor] = { demand = want, ratio = ratio }
    local target = want > 0 and ratio or 0
    local held = s.held[anchor] or 0
    if commit then
      held = sink.inertia and (held + (target - held) * math.min(1, hours / sink.inertia)) or target
      s.held[anchor] = held
    end
    for name, amount in pairs(sink.effects or {}) do
      if name == "warmthPerKwh" then
        if commit then
          s.warmth = s.warmth + want * ratio * hours * amount * Shelter.heatReach(world, anchor) -- a heater outside the shelter's heater slot warms less (D82)
        end
      else
        flow.effects[name] = (flow.effects[name] or 0) + amount * held
      end
    end
  end
  if not commit then
    return
  end

  -- Announcements: a tier served less than it wants (once a day), a battery filling up.
  for _, id in ipairs(s.order) do
    local tier = flow.tiers[id]
    if tier.demand > 0 and tier.served < tier.demand - cfg.overdrawEpsilon and s.warned[id] ~= day then
      s.warned[id] = day
      world.events:emit("power.brownout", { tier = id, ratio = tier.served / tier.demand })
    end
  end
  for _, anchor in ipairs(banks) do
    local fraction = Power.charge(world, anchor) / Power.capacity(world, anchor)
    if fraction >= cfg.fullFraction and not s.full[anchor] then
      s.full[anchor] = true
      world.events:emit("power.full", { battery = anchor })
    elseif fraction < cfg.refullFraction then
      s.full[anchor] = nil
    end
  end
end

function Power.tick(world, dt)
  solve(world, dt / Calendar.hourLength(world), true)
end

--- Rebuild the network numbers (state.flow) for the current switches and priorities without
--- advancing anything: no charge moves, no fuel burns, nothing is announced. The power panel calls it
--- after the player flips a device or reorders the list, so a paused game shows the new picture.
--- The numbers are the same ones the next tick would compute for a very short step.
function Power.refresh(world)
  solve(world, world.tuning.power.refreshHours, false)
end

return Power
