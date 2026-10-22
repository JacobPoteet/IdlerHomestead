-- The night threat framework (D187, #355, docs/PLAN_DEPTH.md §5, §6.1, §6.5): what comes at the homestead in the night.
-- The threats are content (data/content/night_threats.lua: mice, the fox, the raccoon, deer and rabbits, the bear, the cold front, the pipe freeze); each names a handler (Cat, Animals, Raiders, Weather)
-- that owns its seeded stream and its effect through `nightPlan` and `nightLand`. This system decides which one comes,
-- when, and how it is told.
--
-- THE NIGHT. At sunset (the first tick at or after it, once a day) every threat's handler is asked to plan tonight, with
-- its chance scaled by exposure (Events.exposure for that threat: the shelter, the stores that attract animals, the
-- livestock, minus the guards that cover it) and by the mercy rules. A handler draws its own stream exactly as the old raid
-- roll did, so a seed gives the same raids when exposure is neutral. At most one threat comes a night: if several plans
-- hit, the "night" stream picks one by content weight (one roll a dusk, always drawn). The winner claims the night slot
-- (Events.claimSlot), which this system does before the events system draws at the same dusk, so no misfortune event is
-- drawn on top of it. It lands at its handler's hour (23:00 for both so far): turned away (the cat caught the mouse, the
-- door held) or landed. Either way the slot was used, so the pity timer resets (Events.slotOutcome); only a landed
-- threat starts the post-bad cooldown.
--
-- MERCY (PLAN_DEPTH 6.5). While Footing is slipped the chance is scaled by tuning.events.mercy.slippedThreatScale and a
-- threat whose landed outcome is `capital` (the fox: livestock) takes only its `lesser` stock, never the animals. While the
-- post-bad cooldown runs the chance is scaled by tuning.night.threats.coolingScale. A threat's own handler adds its
-- usual limits (a first day, the cat, the coop door).
--
-- THE DUSK SIGN. Once tonight's threat is drawn, NightThreats.sign gives its content `warn` line and the Tonight card says
-- it, so the player has the evening to act before bed. A threat that will be turned away is signed too (the work is
-- visible). The morning report (nightly.lua) lists what was turned away and what a slipped Footing spared.
--
-- THE WAKE HOOK. A threat's content `wake` names a night event offered after the threat resolves, through the event
-- engine's own road (Events.scheduleWake), so the event rules still hold: not before night 3, one wake a night, nothing
-- while Footing is slipped or Condition is low. No shipped threat uses it yet.
--
-- State: world.state.nightthreats = {
--   planDay   the day of the last dusk plan
--   tonight   { day, id, plan (the handler's own table), status ("pending" | "done"), outcome? ("turned" | "landed" |
--             "spared" | "none") } of the latest planned threat, or nil
--   tally     id -> { turned, landed } lifetime counts
--   history   { { day, id, outcome } } the last tuning.night.threats.history resolved threats }
-- Emits "nightthreat.resolved" { id, outcome, lost = { [resource] = n }, tiles? } (lost: what a spared threat took instead, or
-- what a landed raider of the stores took; tiles: crop tiles deer browsed, D188).

local Calendar = require("src.sim.systems.calendar")
local Animals = require("src.sim.systems.animals")
local Cat = require("src.sim.systems.cat")
local Events = require("src.sim.systems.events")
local Footing = require("src.sim.systems.footing")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Raiders = require("src.sim.systems.raiders")
local Weather = require("src.sim.systems.weather")

local NightThreats = {}

-- The handlers content names: each has nightHour(world, def), nightPlan(world, scale, def) and nightLand(world, plan, opts)
-- (and may have nightPlanned(world, plan, def), called once the plan has claimed the night: the cold front starts at dusk),
-- def being the threat's content entry (a handler that serves several threats, such as the raiders, reads its id).
local HANDLERS = { cat = Cat, animals = Animals, raiders = Raiders, weather = Weather }

-- What a handler's landing result means for the night.
local TURNED = { caught = true, stopped = true }

NightThreats.HANDLERS = HANDLERS

local function state(world)
  return world.state.nightthreats
end

local function def(world, id)
  return world.registry:get("night_threats", id)
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

--- Can this threat come tonight by its own content gates (season, first day, first year)?
local function open(world, d)
  local now = Calendar.now(world)
  return (d.seasons == nil or contains(d.seasons, now.season))
    and (d.minDay == nil or now.day >= d.minDay)
    and (d.minYear == nil or now.year >= d.minYear)
end

--- The multiplier on a threat's own chance tonight: exposure (as much of it as the threat's content `exposure` says), the
--- slipped-Footing scale and the cooling scale. 1 means the handler's own odds, unchanged.
function NightThreats.scale(world, d)
  local scale = Events.threatScale(world)
  if Events.cooling(world) then
    scale = scale * world.tuning.night.threats.coolingScale
  end
  return scale * (1 + (Events.exposure(world, d.id).multiplier - 1) * d.exposure)
end

-- Plan tonight: ask every handler, keep the plans that hit and are open, pick one, claim the slot.
local function plan(world)
  local s, now = state(world), Calendar.now(world)
  s.planDay = now.day
  local roll = world:rng("night"):float() -- always drawn, so the stream never depends on the homestead
  local hits, total = {}, 0
  for _, d in ipairs(world.registry:all("night_threats")) do
    local made = HANDLERS[d.handler].nightPlan(world, NightThreats.scale(world, d), d)
    if made and open(world, d) then
      hits[#hits + 1] = { def = d, plan = made }
      total = total + d.weight
    end
  end
  if #hits == 0 then
    return
  end
  local x, pick = roll * total, hits[#hits]
  for _, hit in ipairs(hits) do
    if x < hit.def.weight then
      pick = hit
      break
    end
    x = x - hit.def.weight
  end
  if not Events.claimSlot(world, "threat", pick.def.id) then
    return
  end
  s.tonight = { day = now.day, id = pick.def.id, plan = pick.plan, status = "pending" }
  local planned = HANDLERS[pick.def.handler].nightPlanned
  if planned then
    planned(world, pick.plan, pick.def)
  end
end

local function tally(world, id)
  local t = state(world).tally
  t[id] = t[id] or { turned = 0, landed = 0 }
  return t[id]
end

-- Land tonight's threat and tell everyone how it ended.
local function land(world)
  local s, c = state(world), world.tuning.night.threats
  local t = s.tonight
  local d = def(world, t.id)
  local landed = d.outcomes.landed
  local spare = landed.capital == true and Footing.paused(world)
  local result, took = HANDLERS[d.handler].nightLand(world, t.plan, { spare = spare })
  local outcome = "landed"
  if result == nil then
    outcome = "none" -- what it came for was gone by the hour: the slot was still used
  elseif TURNED[result] then
    outcome = "turned"
  elseif result == "spared" then
    outcome = "spared"
  end
  local lost = {}
  if outcome == "landed" and took and took.lost then
    lost = took.lost -- what a raider of the stores took (D188); the fox and the mice report through their own events
  end
  if outcome == "spared" and landed.lesser then
    for _, id in ipairs(sortedKeys(landed.lesser.lose or {})) do
      local amount = math.min(landed.lesser.lose[id], Ledger.get(world, id))
      if amount > 0 then
        Ledger.remove(world, id, amount, "predator")
        lost[id] = amount
      end
    end
  end
  t.status, t.outcome = "done", outcome
  local counts = tally(world, t.id)
  if outcome == "landed" or outcome == "spared" then
    counts.landed = counts.landed + 1
    if outcome == "landed" and d.journalNote then
      Journal.write(world, d.journalNote)
    end
  else
    counts.turned = counts.turned + 1
  end
  s.history[#s.history + 1] = { day = t.day, id = t.id, outcome = outcome }
  while #s.history > c.history do
    table.remove(s.history, 1)
  end
  Events.slotOutcome(world, (outcome == "landed" or outcome == "spared") and "landed" or "turned")
  world.events:emit("nightthreat.resolved", { id = t.id, outcome = outcome, lost = lost, tiles = took and took.tiles })
  if d.wake and outcome ~= "none" then
    Events.scheduleWake(world, d.wake)
  end
end

--- Tonight's planned threat, { id, status ("pending" | "done"), outcome? } , or nil (none planned for this night, or a
--- past night's). Read-only.
function NightThreats.tonight(world)
  local t = state(world).tonight
  if not t or t.day ~= Calendar.now(world).day then
    return nil
  end
  return { id = t.id, status = t.status, outcome = t.outcome }
end

--- The dusk sign for tonight, { id, line }, or nil: set once the threat is drawn at sunset and gone once it has landed.
function NightThreats.sign(world)
  local t = NightThreats.tonight(world)
  if not t or t.status ~= "pending" then
    return nil
  end
  return { id = t.id, line = def(world, t.id).warn.line }
end

--- Lifetime counts of a threat, { turned, landed }.
function NightThreats.counts(world, id)
  local t = state(world).tally[id]
  return { turned = t and t.turned or 0, landed = t and t.landed or 0 }
end

--- The threats resolved lately, oldest first: { { day, id, outcome } } (a plain copy).
function NightThreats.history(world)
  local out = {}
  for i, h in ipairs(state(world).history) do
    out[i] = { day = h.day, id = h.id, outcome = h.outcome }
  end
  return out
end

--- Run tonight's plan now (the dusk tick calls this once a day; public for tests).
function NightThreats.plan(world)
  plan(world)
end

--- Land tonight's pending threat now (the tick calls this at its hour; public for tests). False when none is pending.
function NightThreats.land(world)
  local t = state(world).tonight
  if not t or t.status ~= "pending" then
    return false
  end
  land(world)
  return true
end

--- A content audit (run in the tests): the problems found in the night threats content, as a list of strings.
function NightThreats.audit(world)
  local problems = {}
  local reg = world.registry
  for _, d in ipairs(reg:all("night_threats")) do
    local function bad(message)
      problems[#problems + 1] = d.id .. ": " .. message
    end
    local handler = HANDLERS[d.handler]
    if not handler then
      bad("unknown handler " .. tostring(d.handler))
    else
      for _, fn in ipairs({ "nightHour", "nightPlan", "nightLand" }) do
        if type(handler[fn]) ~= "function" then
          bad("handler " .. d.handler .. " has no " .. fn)
        end
      end
    end
    if d.exposure < 0 or d.exposure > 1 then
      bad("exposure is a weight from 0 to 1")
    end
    if d.weight <= 0 then
      bad("weight must be positive")
    end
    if type(d.warn.line) ~= "string" then
      bad("needs a warn line")
    end
    if not d.outcomes.turned or type(d.outcomes.turned.report) ~= "string" then
      bad("needs a turned report line")
    end
    local landed = d.outcomes.landed
    if not landed then
      bad("needs a landed outcome")
    elseif landed.capital then
      if not landed.lesser or not landed.lesser.lose or not landed.sparedReport then
        bad("destroys capital but has no lesser form and sparedReport (PLAN_DEPTH 6.5 rule 3)")
      end
    end
    for _, season in ipairs(d.seasons or {}) do
      if not contains(world.tuning.time.seasons, season) then
        bad("unknown season " .. season)
      end
    end
    if d.journalNote and not reg:has("notes", d.journalNote) then
      bad("unknown journalNote " .. d.journalNote)
    end
    if d.counter and not reg:has("catalog", d.counter) then
      bad("unknown counter " .. d.counter)
    end
    if d.guard and d.counter and reg:has("catalog", d.counter) then
      local item = reg:get("catalog", d.counter)
      if not (item.modifiers and item.modifiers[d.guard]) then
        bad("counter " .. d.counter .. " does not carry the guard stat " .. d.guard)
      end
    end
    for id in pairs(landed and landed.lesser and landed.lesser.lose or {}) do
      if not reg:has("resources", id) then
        bad("lesser form names the unknown resource " .. id)
      end
    end
    if d.wake then
      if not reg:has("events", d.wake) then
        bad("wakes the unknown event " .. d.wake)
      else
        local e = reg:get("events", d.wake)
        if not e.wake or e.when ~= "night" then
          bad("wake event " .. d.wake .. " must be a night event that may wake")
        end
      end
    end
  end
  return problems
end

function NightThreats.init(world)
  local s = world.state.nightthreats or {}
  world.state.nightthreats = s
  s.planDay = s.planDay or 0
  s.tally = s.tally or {}
  s.history = s.history or {}
  -- A loaded save may name a threat the content no longer has: forget it rather than fail.
  if s.tonight and not world.registry:has("night_threats", s.tonight.id) then
    s.tonight = nil
  end
end

function NightThreats.tick(world)
  local s, now = state(world), Calendar.now(world)
  local t = s.tonight
  if t and t.status == "pending" then
    local hour = HANDLERS[def(world, t.id).handler].nightHour(world, def(world, t.id))
    if t.day < now.day or now.hour >= hour then
      land(world)
    end
  end
  if s.planDay ~= now.day then
    local _, sunset = Calendar.daylight(world)
    if now.hour >= sunset then
      plan(world)
    end
  end
end

return NightThreats
