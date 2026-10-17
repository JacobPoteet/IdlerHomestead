-- Misfortune events: the engine (D169, #347, docs/PLAN_DEPTH.md §5, §6.2, §6.3, §6.5). What happens to a person living
-- alone, asked as a choice between two options with a real trade-off, or ignored. The events are content
-- (data/content/events.lua, which documents the schema and the effect vocabulary); the knobs are tuning.events.
--
-- THE NIGHT SLOT, EXPOSURE AND THE PITY TIMER (shared with the night-threat framework, C1, #355, so it can reuse them as
-- they are). Each dusk (the first tick at or after sunset, once a day) is one draw for the coming night and the day after:
--   * Exposure (Events.exposure): 0..10 points from the homestead (tuning.night.exposure), 5 neutral; it scales the chance
--     of the draw linearly (Events.chance). The Tonight card will show the word and the points.
--   * One slot a night, shared by threats and events. A threat claims it first (Events.claimSlot, ahead of this system in
--     the system list); an event draw is skipped on a night the slot is claimed. A threat that is turned away still used
--     the slot and counts as an occurrence for the pity timer, but starts no cooldown (Events.slotOutcome "turned"); one
--     that landed starts the post-bad cooldown like a bad event ("landed").
--   * Pity (state.quiet): nights since the last occurrence; from tuning.events.pityNights the chance rises each night.
--   * Quiet start: no draw before tuning.events.firstNight, and no bad event before Footing is earned or tuning.events.badFromDay
--     (Q10), whichever comes first; mild luck may come from the third night. Budget: at most tuning.events.perDayBudget events are offered
--     on one calendar day, however they were scheduled.
--
-- WHEN AN EVENT COMES. A draw that hits picks one event by weight (content weight x season x terms x exposure, from the
-- named "event" stream) and schedules it: a night event shortly after bedtime, a morning or day event the next morning or
-- midday. When it is due, and nobody has a card open, and the player is present, it is offered: it joins the pending queue.
-- It is re-checked first against the mercy rules and its conditions and dropped if they no longer hold.
--
-- THE CARD AND THE IGNORE WINDOW. Time never waits for a card (D168). A pending event holds `hoursLeft` of game time and
-- `realLeft` seconds of real time (tuning.events.ignoreHours, ignoreMinSeconds); both run down only while the player is
-- present (Events.setAway false), game time in the tick and real time through Events.advanceReal (the scene feeds it every
-- frame). When both are spent the ignore outcome applies. While the player is away the card waits in the queue and no new
-- event is offered behind it. Events.choose answers a card, Events.ignore answers it by ignoring it now.
--
-- MERCY (PLAN_DEPTH 6.5, keyed on Footing and reserves). No event is offered under tuning.events.mercy.lowCondition;
-- no bad event while Footing is slipped or the statuses are full; Condition is never taken under conditionFloor; while
-- slipped, or past maxOpenDamage open damage flags, an outcome marked `capital` or `damage` is swapped for its `lesser`
-- form; the combined warmth need is capped (Needs.warmthNeeded). The ignore outcome is judged by the worst chain it can
-- reach, by Events.audit (run in the tests): free, no condition loss, nothing that can escalate, never worse than the worse option.
--
-- Event bus: "event.offered" { id, class, bad, wake, day }, "event.chosen" { id, option, label, class, bad },
-- "event.ignored" { id, reason ("expired" | "ignored"), label, class, bad }.
--
-- State: world.state.events = {
--   rollDay    the day of the last dusk draw
--   quiet      nights since the last occurrence (the pity timer)
--   coolUntil  day number: no draw hits through this day (after a bad outcome)
--   slot       { day, kind ("event" | "threat"), id } of the night's slot, or nil
--   scheduled  { { id, due (day * 24 + hour), depth } } events waiting for their hour
--   pending    { { id, day, hoursLeft, realLeft, depth } } the queue of open cards, the first is the card
--   budget     { day, count } events offered on that day
--   done, last id -> times offered this run / day last offered
--   flags      name -> true (until cleared) | the first day it no longer holds
--   damage     name -> true: the open lasting damage flags
--   locks      tile -> the first day it is free again
--   coldDay    the day the last cold-damage night was paid (Fever never follows one)
--   wakeNight  the night of the last wake event
--   history    { { day, id, how ("chosen" | "ignored" | "dropped"), option?, reason? } } }

local Animals = require("src.sim.systems.animals")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Footing = require("src.sim.systems.footing")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")
local Sleep = require("src.sim.systems.sleep")
local Status = require("src.sim.systems.status")
local Weather = require("src.sim.systems.weather")

local Events = {}

local function state(world)
  return world.state.events
end

local function cfg(world)
  return world.tuning.events
end

local function def(world, id)
  return world.registry:get("events", id)
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

-- Calendar position as one number (day * 24 + hour) so "due" compares across midnight.
local function stamp(day, hour)
  return day * 24 + hour
end

local function nowStamp(world)
  local now = Calendar.now(world)
  return stamp(now.day, now.hour)
end

-- The night an hour belongs to: the day of its sunset (hours before sunrise belong to the night before).
local function nightOf(world)
  local now = Calendar.now(world)
  local sunrise = Calendar.daylight(world)
  return now.hour < sunrise and now.day - 1 or now.day
end

-- Presence ------------------------------------------------------------------------------------------

--- Tell the engine whether the player is truly away (the app unfocused, or past the takeover delay with no input). Runtime
--- only, never saved: an away player's ignore window waits and no new event is offered. The scene calls this every frame.
function Events.setAway(world, away)
  world.playerAway = away == true
end

--- Is the player away? (false for a headless world nobody told.)
function Events.away(world)
  return world.playerAway == true
end

--- Count `dt` real seconds against the open card's ignore window, if the player is present. The scene calls this every
--- frame with the real frame time (the harness with the tick); the floor is real time, not game time.
function Events.advanceReal(world, dt)
  local head = state(world).pending[1]
  if head and not Events.away(world) then
    head.realLeft = math.max(0, head.realLeft - dt)
  end
end

-- Exposure ------------------------------------------------------------------------------------------

--- How much the homestead gives a night to work with: { points (0..10, 5 neutral), word ("low" | "medium" | "high"),
--- multiplier (on the night's chance) }. Shelter, stores that attract animals and livestock raise it; guards (C7) lower it.
function Events.exposure(world)
  local x = world.tuning.night.exposure
  local points = x.neutral
  local shelter = Shelter.id(world)
  if shelter and x.shelter[shelter] then
    points = points + x.shelter[shelter]
  end
  for _, id in ipairs(sortedKeys(x.stores)) do
    if Ledger.get(world, id) > 0 then
      points = points + x.stores[id]
    end
  end
  points = points + math.min(x.maxLivestock, (Animals.hens(world) + Animals.goats(world)) * x.perAnimal)
  for _, id in ipairs(sortedKeys(x.guards)) do
    if Ledger.get(world, id) > 0 then
      points = points - x.guards[id]
    end
  end
  points = math.max(x.min, math.min(x.max, points))
  local word = points < x.lowBelow and "low" or (points >= x.highFrom and "high" or "medium")
  local share = (points - x.min) / (x.max - x.min)
  return { points = points, word = word, multiplier = x.chanceAtMin + (x.chanceAtMax - x.chanceAtMin) * share }
end

--- Chance (0..1) that tonight's draw produces an occurrence: the base, scaled by exposure and the year, plus pity.
function Events.chance(world)
  local c, s = cfg(world), state(world)
  local year = c.yearScale[math.min(Calendar.now(world).year, #c.yearScale)]
  local chance = c.chancePerNight * year * Events.exposure(world).multiplier
  if s.quiet >= c.pityNights then
    chance = chance + c.pityBoost * (s.quiet - c.pityNights + 1)
  end
  return math.min(c.maxChance, chance)
end

--- Multiplier (0..1) on a night threat's strength: reduced while Footing is slipped (PLAN_DEPTH 6.5). For the threat framework.
function Events.threatScale(world)
  return Footing.paused(world) and cfg(world).mercy.slippedThreatScale or 1
end

-- The night slot ------------------------------------------------------------------------------------

--- Tonight's slot, { day, kind, id }, or nil while it is free.
function Events.slot(world)
  local slot = state(world).slot
  return slot and { day = slot.day, kind = slot.kind, id = slot.id } or nil
end

--- Claim the night's slot for a threat (or anything else that fills the night). False if it is taken.
function Events.claimSlot(world, kind, id)
  local s, now = state(world), Calendar.now(world)
  if s.slot and s.slot.day == now.day then
    return false
  end
  s.slot = { day = now.day, kind = kind, id = id }
  return true
end

--- Tell the pity timer how a claimed slot ended: "turned" (a threat was turned away: it counts as an occurrence, so the
--- pity timer resets, but starts no cooldown) or "landed" (it hurt: it resets the timer and starts the post-bad cooldown).
function Events.slotOutcome(world, outcome)
  assert(outcome == "turned" or outcome == "landed", "slot outcome is 'turned' or 'landed'")
  local s = state(world)
  s.quiet = 0
  if outcome == "landed" then
    s.coolUntil = Calendar.now(world).day + cfg(world).badCooldownNights
  end
end

-- Conditions, weights and the mercy gate -----------------------------------------------------------------

local function anyStatus(world, list)
  for _, id in ipairs(list) do
    if Status.has(world, id) or Status.inFamily(world, id) then
      return true
    end
  end
  return false
end

-- Do these conditions hold now? (`mult` and other keys of a weight term are not conditions.)
local function holds(world, cond)
  if not cond then
    return true
  end
  if cond.weather and not contains(cond.weather, Weather.kind(world)) then
    return false
  end
  if cond.frozen ~= nil and Weather.isFrozen(world) ~= cond.frozen then
    return false
  end
  if cond.status and not anyStatus(world, cond.status) then
    return false
  end
  if cond.noColdNight and state(world).coldDay == Calendar.now(world).day then
    return false
  end
  return true
end

--- Why an event cannot be offered now under the mercy rules (PLAN_DEPTH 6.5), or nil. Every event waits for Condition;
--- a misfortune also waits for Footing and for room among the statuses.
function Events.blocked(world, d)
  if Needs.condition(world) < cfg(world).mercy.lowCondition then
    return "low condition"
  end
  if d.bad then
    if not Footing.held(world) and Calendar.now(world).day < cfg(world).badFromDay then
      return "quiet start" -- Q10: bad events wait for Footing or tuning.events.badFromDay, whichever comes first
    end
    if Footing.paused(world) then
      return "slipped"
    end
    if Status.count(world) >= Status.maxActive(world) then
      return "statuses full"
    end
  end
  return nil
end

--- The weight of an event for tonight's draw (0 when it cannot come): content weight x season x the terms that hold x
--- exposure, zero if it is spent (once, cooldown), too early, out of season, its conditions fail or the mercy rules block it.
function Events.weight(world, id)
  local d, s, now = def(world, id), state(world), Calendar.now(world)
  if d.once and (s.done[id] or 0) > 0 then
    return 0
  end
  if d.cooldown and s.last[id] and now.day - s.last[id] < d.cooldown then
    return 0
  end
  if d.minYear and now.year < d.minYear then
    return 0
  end
  local weight = d.weight
  if d.seasons then
    weight = weight * (d.seasons[now.season] or 0)
  end
  if weight <= 0 or not holds(world, d.conditions) or Events.blocked(world, d) then
    return 0
  end
  for _, term in ipairs(d.terms or {}) do
    if holds(world, term) then
      weight = weight * term.mult
    end
  end
  if d.exposure then
    weight = weight * (1 + (Events.exposure(world).multiplier - 1) * d.exposure)
  end
  return weight
end

-- Effects ---------------------------------------------------------------------------------------------

local function record(world, id, how, option, reason)
  local s = state(world)
  s.history[#s.history + 1] = { day = Calendar.now(world).day, id = id, how = how, option = option, reason = reason }
  while #s.history > cfg(world).historyLimit do
    table.remove(s.history, 1)
  end
end

--- Open lasting damage flags (torn canvas, clogged flue ...), sorted.
function Events.openDamage(world)
  return sortedKeys(state(world).damage)
end

--- Is the damage flag `name` open?
function Events.hasDamage(world, name)
  return state(world).damage[name] == true
end

--- Repair a damage flag (the mend task or item calls this). Returns whether it was open.
function Events.repair(world, name)
  local s = state(world)
  local was = s.damage[name] == true
  s.damage[name] = nil
  return was
end

--- Is the event flag `name` set (for days, or until cleared)?
function Events.flag(world, name)
  local v = state(world).flags[name]
  return v == true or (type(v) == "number" and v > Calendar.now(world).day)
end

--- Is the planted tile locked from work (an event's hornets, a washout)? The land packs read this.
function Events.tileLocked(world, tile)
  local v = state(world).locks[tile]
  return v ~= nil and v > Calendar.now(world).day
end

--- The effect that actually applies (PLAN_DEPTH 6.5 rules 3 and 4): the outcome's `lesser` form (or nothing) while Footing is
--- slipped and the outcome destroys capital, or when its damage flags would pass tuning.events.mercy.maxOpenDamage.
function Events.effective(world, effect)
  if effect.capital and Footing.paused(world) then
    return effect.lesser or {}
  end
  if effect.damage then
    local s, fresh = state(world), 0
    for _, name in ipairs(effect.damage) do
      if not s.damage[name] then
        fresh = fresh + 1
      end
    end
    if fresh > 0 and #Events.openDamage(world) + fresh > cfg(world).mercy.maxOpenDamage then
      return effect.lesser or {}
    end
  end
  return effect
end

local schedule -- (below) queue an event for its hour

local function pickTiles(world, count)
  local tiles = Crops.plantedTiles(world)
  local rng, picked = world:rng("event"), {}
  for _ = 1, math.min(count, #tiles) do
    picked[#picked + 1] = table.remove(tiles, rng:int(1, #tiles))
  end
  return picked
end

local function applyEffect(world, effect, depth)
  local s, c = state(world), cfg(world)
  effect = Events.effective(world, effect)
  local day = Calendar.now(world).day
  local status = effect.status
  if status then
    for _, id in ipairs(type(status) == "table" and status or { status }) do
      Status.apply(world, id)
    end
  end
  for _, id in ipairs(sortedKeys(effect.gain or {})) do
    Ledger.addOrOverflow(world, id, effect.gain[id], "event")
  end
  for _, id in ipairs(sortedKeys(effect.lose or {})) do
    local amount = math.min(effect.lose[id], Ledger.get(world, id))
    if amount > 0 then
      Ledger.remove(world, id, amount, "event")
    end
  end
  if effect.condition then
    Needs.injure(world, -effect.condition, c.mercy.conditionFloor)
  end
  for _, name in ipairs(sortedKeys(effect.flags or {})) do
    local v = effect.flags[name]
    if v == false then
      s.flags[name] = nil
    else
      s.flags[name] = v == true and true or day + v
    end
  end
  for _, name in ipairs(effect.damage or {}) do
    s.damage[name] = true
  end
  if effect.lockTiles then
    for _, tile in ipairs(pickTiles(world, effect.lockTiles.count)) do
      s.locks[tile] = day + effect.lockTiles.days
    end
  end
  if effect.damageTiles then
    for _, tile in ipairs(pickTiles(world, effect.damageTiles.count)) do
      Crops.setBack(world, tile, effect.damageTiles.setback, "event")
    end
  end
  if effect.note then
    Journal.write(world, effect.note)
  end
  if effect.chain and depth < c.maxChainDepth then
    schedule(world, effect.chain.id, day + effect.chain.afterDays, depth + 1)
  end
end

-- Offering and answering ---------------------------------------------------------------------------------

-- The stamp a scheduled event is due: night events after bedtime, morning and day events at their hour, on `day`.
local function dueOn(world, d, day)
  local c = cfg(world)
  if d.when == "night" then
    local from = Sleep.bedtimeHours(world)
    return stamp(day, from + c.hours.night)
  end
  return stamp(day, c.hours[d.when])
end

schedule = function(world, id, day, depth)
  local s = state(world)
  s.scheduled[#s.scheduled + 1] = { id = id, due = dueOn(world, def(world, id), day), depth = depth or 0 }
end

local function offer(world, d, depth)
  local s, c = state(world), cfg(world)
  local now = Calendar.now(world)
  s.pending[#s.pending + 1] =
    { id = d.id, day = now.day, hoursLeft = c.ignoreHours, realLeft = c.ignoreMinSeconds, depth = depth }
  if s.budget.day ~= now.day then
    s.budget.day, s.budget.count = now.day, 0
  end
  s.budget.count = s.budget.count + 1
  s.done[d.id] = (s.done[d.id] or 0) + 1
  s.last[d.id] = now.day
  if d.wake then
    s.wakeNight = nightOf(world)
  end
  if d.journalNote then
    Journal.write(world, d.journalNote) -- the first time it is offered; later calls do nothing
  end
  world.events:emit("event.offered", { id = d.id, class = d.class, bad = d.bad, wake = d.wake == true, day = now.day })
end

-- Offer a scheduled event if it may come now: "offered", "dropped" (the mercy rules or its conditions no longer allow it)
-- or "later" (the day's budget is spent; it waits a day).
local function tryOffer(world, item)
  local s, c = state(world), cfg(world)
  local d = def(world, item.id)
  local now = Calendar.now(world)
  if s.budget.day == now.day and s.budget.count >= c.perDayBudget then
    item.due = item.due + 24
    return "later"
  end
  local reason = Events.blocked(world, d)
  if not reason and not holds(world, d.conditions) then
    reason = "conditions"
  end
  if not reason and d.wake and s.wakeNight == nightOf(world) then
    reason = "one wake a night"
  end
  if reason then
    record(world, d.id, "dropped", nil, reason)
    return "dropped"
  end
  offer(world, d, item.depth)
  return "offered"
end

local function resolve(world, option, reason)
  local s, c = state(world), cfg(world)
  local entry = table.remove(s.pending, 1)
  local d = def(world, entry.id)
  local outcome = option and d.options[option] or d.ignore
  applyEffect(world, outcome.effect, entry.depth)
  if d.bad then
    s.coolUntil = Calendar.now(world).day + c.badCooldownNights
  end
  record(world, d.id, option and "chosen" or "ignored", option, reason)
  local payload = { id = d.id, label = outcome.label, class = d.class, bad = d.bad }
  if option then
    payload.option = option
    world.events:emit("event.chosen", payload)
  else
    payload.reason = reason
    world.events:emit("event.ignored", payload)
  end
end

--- Resources an option costs that are not in stock: the first such id, or nil.
local function lacking(world, cost)
  for _, id in ipairs(sortedKeys(cost or {})) do
    if Ledger.get(world, id) < cost[id] then
      return id
    end
  end
  return nil
end

local function optionView(world, d, index)
  local o = d.options[index]
  local missing = lacking(world, o.cost)
  return {
    index = index,
    label = o.label,
    cost = o.cost or {},
    risk = o.risk,
    careful = o.careful == true,
    bold = o.bold == true,
    effect = o.effect, -- the content's effect table, for the card's plain words (read-only)
    affordable = missing == nil,
    lacking = missing,
  }
end

local function view(world, entry)
  local d = def(world, entry.id)
  return {
    id = d.id,
    title = d.title,
    line = d.line,
    class = d.class,
    bad = d.bad,
    wake = d.wake == true,
    options = { optionView(world, d, 1), optionView(world, d, 2) },
    ignore = { label = d.ignore.label, risk = d.ignore.risk, effect = d.ignore.effect },
    hoursLeft = entry.hoursLeft,
    realLeft = entry.realLeft,
  }
end

--- The open card, as a read-only view, or nil: { id, title, line, class, bad, wake, options = { { index, label, cost, risk,
--- careful, bold, effect, affordable, lacking } x2 }, ignore = { label, risk, effect }, hoursLeft, realLeft }. `effect` is the
--- content's own table (read-only), so the card (B4, src/ui/event_text.lua) can say it in plain words.
function Events.pending(world)
  local entry = state(world).pending[1]
  return entry and view(world, entry) or nil
end

--- How many cards wait (the first is open): a cheap look for the notice queue, which asks every frame.
function Events.waiting(world)
  return #state(world).pending
end

--- Every waiting card in order (the first is open), for the ranked notice queue (PLAN_DEPTH principle 8).
function Events.queue(world)
  local out = {}
  for i, entry in ipairs(state(world).pending) do
    out[i] = view(world, entry)
  end
  return out
end

--- Answer the open card with option 1 or 2. Returns true, or false + the reason ("no event", "no such option",
--- "lacks <resource>"). The cost is paid from the ledger.
function Events.choose(world, index)
  local entry = state(world).pending[1]
  if not entry then
    return false, "no event"
  end
  local o = def(world, entry.id).options[index]
  if not o then
    return false, "no such option"
  end
  local missing = lacking(world, o.cost)
  if missing then
    return false, "lacks " .. missing
  end
  if o.cost then
    Ledger.spend(world, o.cost, "event")
  end
  resolve(world, index)
  return true
end

--- Answer the open card by ignoring it now (the ignore outcome applies at once, as when the window runs out).
function Events.ignore(world, reason)
  if not state(world).pending[1] then
    return false, "no event"
  end
  resolve(world, nil, reason or "ignored")
  return true
end

--- Offer an event now, outside the draw: the debug and driver path (the card itself is the homestead scene's). Skips the schedule, the
--- budget and the mercy rules, but not the queue: false + "busy" while a card is open.
function Events.force(world, id)
  if #state(world).pending > 0 then
    return false, "busy"
  end
  offer(world, def(world, id), 0)
  return true
end

--- Events waiting for their hour, as { { id, due } }, read-only.
function Events.scheduled(world)
  local out = {}
  for i, item in ipairs(state(world).scheduled) do
    out[i] = { id = item.id, due = item.due }
  end
  return out
end

--- What happened to the events this run, oldest first: { { day, id, how, option?, reason? } } (a plain copy).
function Events.history(world)
  local out = {}
  for i, h in ipairs(state(world).history) do
    out[i] = { day = h.day, id = h.id, how = h.how, option = h.option, reason = h.reason }
  end
  return out
end

-- The dusk draw -----------------------------------------------------------------------------------------

-- Pick one event by weight with a roll in 0..1, or nil when none can come.
local function pick(world, roll)
  local pool, total = {}, 0
  for _, d in ipairs(world.registry:all("events")) do
    local w = Events.weight(world, d.id)
    if w > 0 then
      pool[#pool + 1] = { id = d.id, weight = w }
      total = total + w
    end
  end
  if total <= 0 then
    return nil
  end
  local x = roll * total
  for _, e in ipairs(pool) do
    if x < e.weight then
      return e.id
    end
    x = x - e.weight
  end
  return pool[#pool].id
end

--- Run tonight's draw (the dusk tick calls this once a day; public for tests). Always takes the same two rolls from the
--- "event" stream, so what the stream does never depends on what the homestead has. Returns the id scheduled, or nil.
function Events.rollNight(world)
  local s, c = state(world), cfg(world)
  local now = Calendar.now(world)
  s.rollDay = now.day
  local rng = world:rng("event")
  local hit, choose = rng:float(), rng:float()
  if now.day < c.firstNight then
    return nil -- the quiet start
  end
  if s.slot and s.slot.day == now.day then
    return nil -- a threat took the slot (and told the pity timer how it ended)
  end
  local chance = Events.chance(world)
  local quiet = s.quiet
  s.quiet = quiet + 1
  if now.day <= s.coolUntil or hit >= chance then
    return nil
  end
  local id = pick(world, choose)
  if not id then
    return nil
  end
  s.quiet = 0
  s.slot = { day = now.day, kind = "event", id = id }
  local d = def(world, id)
  schedule(world, id, d.when == "night" and now.day or now.day + 1, 0)
  return id
end

-- Is something to offer now? One per tick, in order, never behind an open card or while the player is away.
local function offerDue(world)
  local s = state(world)
  if #s.pending > 0 or Events.away(world) then
    return
  end
  local at = nowStamp(world)
  for i, item in ipairs(s.scheduled) do
    if item.due <= at then
      if tryOffer(world, item) ~= "later" then
        table.remove(s.scheduled, i)
      end
      return
    end
  end
end

--- A content audit (run in the tests): the problems found in the events content, as a list of strings. Checks the shape,
--- that every id named exists, that chains end, that `capital` and `damage` outcomes have a lesser form, and the ignore
--- rules of PLAN_DEPTH 6.2 and 6.5: free, no condition loss, nothing that can escalate or roll later, and judged by its
--- worst reachable chain never worse than the worse option.
local EFFECT_KEYS = {
  status = true,
  gain = true,
  lose = true,
  condition = true,
  flags = true,
  damage = true,
  lockTiles = true,
  damageTiles = true,
  note = true,
  chain = true,
  capital = true,
  lesser = true,
}

function Events.audit(world)
  local problems = {}
  local reg = world.registry
  local function bad(id, message)
    problems[#problems + 1] = id .. ": " .. message
  end
  local function statusIds(effect)
    local list = effect.status
    return type(list) == "table" and list or (list and { list } or {})
  end
  -- The worst a status can become by escalation, and a chain's reach: { severity, condition }.
  local function reach(effect, seen)
    local out = { severity = 0, condition = 0 }
    for _, sid in ipairs(statusIds(effect)) do
      local sd = reg:get("statuses", sid)
      while sd do
        out.severity = math.max(out.severity, sd.severity)
        sd = sd.escalatesTo and reg:get("statuses", sd.escalatesTo) or nil
      end
    end
    out.condition = effect.condition and -effect.condition or 0
    if effect.chain and not seen[effect.chain.id] then
      seen[effect.chain.id] = true
      local follow = reg:get("events", effect.chain.id)
      for _, outcome in ipairs({ follow.options[1], follow.options[2], follow.ignore }) do
        local r = reach(outcome.effect, seen)
        out.severity = math.max(out.severity, r.severity)
        out.condition = math.max(out.condition, r.condition)
      end
    end
    return out
  end
  for _, d in ipairs(reg:all("events")) do
    local id = d.id
    if not contains({ "body", "home", "land", "visitors" }, d.class) then
      bad(id, "class '" .. d.class .. "'")
    end
    if not contains({ "night", "morning", "day" }, d.when) then
      bad(id, "when '" .. d.when .. "'")
    end
    if d.journalNote and not reg:has("notes", d.journalNote) then
      bad(id, "unknown journalNote " .. d.journalNote)
    end
    if #d.options ~= 2 then
      bad(id, "needs exactly two options")
    end
    local outcomes = { d.options[1], d.options[2], d.ignore }
    local worst = { severity = 0, condition = 0 }
    for n, o in ipairs(outcomes) do
      local where = n == 3 and "ignore" or ("option " .. n)
      if type(o.label) ~= "string" or type(o.risk) ~= "string" or type(o.effect) ~= "table" then
        bad(id, where .. " needs label, risk and effect")
      else
        for key in pairs(o.effect) do
          if not EFFECT_KEYS[key] then
            bad(id, where .. " has the unknown effect '" .. key .. "'")
          end
        end
        for _, sid in ipairs(statusIds(o.effect)) do
          if not reg:has("statuses", sid) then
            bad(id, where .. " names the unknown status " .. sid)
          end
        end
        for _, key in ipairs({ "gain", "lose" }) do
          for rid in pairs(o.effect[key] or {}) do
            if not reg:has("resources", rid) then
              bad(id, where .. " names the unknown resource " .. rid)
            end
          end
        end
        for rid in pairs(o.cost or {}) do
          if not reg:has("resources", rid) then
            bad(id, where .. " costs the unknown resource " .. rid)
          end
        end
        if o.effect.note and not reg:has("notes", o.effect.note) then
          bad(id, where .. " writes the unknown note " .. o.effect.note)
        end
        if o.effect.condition and o.effect.condition >= 0 then
          bad(id, where .. ": condition is a loss, so negative")
        end
        if (o.effect.capital or o.effect.damage) and not o.effect.lesser then
          bad(id, where .. " destroys capital or opens damage but has no lesser form")
        end
        if o.effect.lesser and (o.effect.lesser.capital or o.effect.lesser.damage) then
          bad(id, where .. ": the lesser form must not destroy capital or open damage")
        end
        if o.effect.chain then
          if not reg:has("events", o.effect.chain.id) then
            bad(id, where .. " chains the unknown event " .. o.effect.chain.id)
          elseif o.effect.chain.id == id then
            bad(id, where .. " chains itself")
          end
        end
        local r = reach(o.effect, { [id] = true })
        if n < 3 then
          worst.severity = math.max(worst.severity, r.severity)
          worst.condition = math.max(worst.condition, r.condition)
        else
          if o.cost then
            bad(id, "ignore must be free")
          end
          for _, forbidden in ipairs({ "condition", "chain", "damage", "capital", "lockTiles", "damageTiles", "lose" }) do
            if o.effect[forbidden] then
              bad(id, "ignore must not use " .. forbidden .. " (free, safe, non-escalating)")
            end
          end
          for _, sid in ipairs(statusIds(o.effect)) do
            if reg:has("statuses", sid) and reg:get("statuses", sid).escalatesTo then
              bad(id, "ignore applies " .. sid .. ", which can escalate")
            end
          end
          if r.severity > worst.severity or r.condition > worst.condition then
            bad(id, "ignore is worse than the worse option")
          end
        end
      end
    end
  end
  return problems
end

function Events.init(world)
  local s = world.state.events or {}
  world.state.events = s
  s.rollDay = s.rollDay or 0
  s.quiet = s.quiet or 0
  s.coolUntil = s.coolUntil or 0
  s.coldDay = s.coldDay or 0
  s.wakeNight = s.wakeNight or 0
  s.scheduled = s.scheduled or {}
  s.pending = s.pending or {}
  s.budget = s.budget or { day = 0, count = 0 }
  s.done = s.done or {}
  s.last = s.last or {}
  s.flags = s.flags or {}
  s.damage = s.damage or {}
  s.locks = s.locks or {}
  s.history = s.history or {}
  -- A loaded save may name an event the content no longer has: drop it rather than fail.
  for _, list in ipairs({ s.scheduled, s.pending }) do
    for i = #list, 1, -1 do
      if not world.registry:has("events", list[i].id) then
        table.remove(list, i)
      end
    end
  end
  world.events:on("needs.warmed", function(e)
    if e.shortfall > 0 then
      state(world).coldDay = Calendar.now(world).day
    end
  end)
  world.events:on("calendar.newDay", function(e)
    local st = state(world)
    for _, name in ipairs(sortedKeys(st.flags)) do
      local v = st.flags[name]
      if type(v) == "number" and v <= e.day then
        st.flags[name] = nil
      end
    end
    for _, tile in ipairs(sortedKeys(st.locks)) do
      if st.locks[tile] <= e.day then
        st.locks[tile] = nil
      end
    end
  end)
end

function Events.tick(world, dt)
  local c = cfg(world)
  if not c.enabled then
    return
  end
  local s = state(world)
  local head = s.pending[1]
  if head and not Events.away(world) then
    head.hoursLeft = head.hoursLeft - dt / Calendar.hourLength(world)
    if head.hoursLeft <= 0 and head.realLeft <= 0 then
      resolve(world, nil, "expired")
    end
  end
  local now = Calendar.now(world)
  if s.rollDay ~= now.day then
    local _, sunset = Calendar.daylight(world)
    if now.hour >= sunset then
      Events.rollNight(world)
    end
  end
  offerDue(world)
end

return Events
