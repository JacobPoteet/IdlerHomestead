-- Misfortune events: the engine (D169, #347, docs/PLAN_DEPTH.md §5, §6.2, §6.3, §6.5). What happens to a person living
-- alone, asked as a choice between two options with a real trade-off, or ignored. The events are content
-- (data/content/events.lua, which documents the schema and the effect vocabulary); the knobs are tuning.events.
--
-- THE NIGHT SLOT, EXPOSURE AND THE PITY TIMER (shared with the night-threat framework, C1, #355, so it can reuse them as
-- they are). Each dusk (the first tick at or after sunset, once a day) is one draw for the coming night and the day after:
--   * Exposure (Events.exposure): 0..10 points from the homestead (tuning.night.exposure), 5 neutral; it scales the chance
--     of the draw linearly (Events.chance). The Tonight card shows the word only (D187).
--   * One slot a night, shared by threats and events. A threat claims it first (Events.claimSlot, from nightthreats.lua,
--     which runs ahead of this system in the system list and plans its threat at dusk, D187); an event draw is skipped on a night the slot is claimed. A threat that is turned away still used
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
-- STANDING ORDERS (B5, #349, D176, PLAN_DEPTH 6.4). With the "Rules of thumb" perk known, each event class (body, home, land,
-- visitors) can be set to Ask me (default: the card), Careful (the option flagged `careful`) or Bold (the one flagged `bold`).
-- The setting is the player's own, kept in the slot's meta (it survives a failed run). An event of a class that has an order is
-- answered the moment it is offered, so a player away or at 8x is not interrupted. Careful and Bold both fall back to the ignore
-- outcome when there is no such option, when the cost cannot be paid, or when paying would take a stock under a keep target the
-- player set, under the wood still needed to reach the end of winter, or under a day's drinking water (Events.orderFloor); an unaffordable or keep-blocked option adds a line to the morning
-- report ("event.orderFallback"). Until the perk is known every order reads as Ask me, so nothing changes without it.
--
-- Event bus: "event.offered" { id, class, bad, wake, day }, "event.chosen" { id, option, label, class, bad, order? (true when a
-- standing order chose it) }, "event.ignored" { id, reason ("expired" | "ignored" | "order"), label, class, bad },
-- "event.orderFallback" { id, class, mode, why ("keep" | "short"), resource } (an order fell back to ignoring because of the cost),
-- "event.later" { id, hit } (a delayed outcome came due: it landed, or the chance missed).
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
--   delayed    { { due (day * 24 + hour), from (the event id), chance (a tuning.events.chances key, or nil = certain), effect } }
--              effects that land later (a `later` outcome): an infection two mornings on, a collapse that afternoon
--   coldDay    the day the last cold-damage night was paid (Fever never follows one)
--   wakeNight  the night of the last wake event
--   history    { { day, id, how ("chosen" | "ignored" | "dropped"), option?, reason? ("order" when a standing order answered) } } }
-- The orders themselves are world.meta.standingOrders = { [class] = "careful" | "bold" } (absent = Ask me).

local Animals = require("src.sim.systems.animals")
local Calendar = require("src.sim.systems.calendar")
local Crops = require("src.sim.systems.crops")
local Food = require("src.sim.systems.food")
local Footing = require("src.sim.systems.footing")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")
local Sleep = require("src.sim.systems.sleep")
local Stats = require("src.sim.stats")
local Status = require("src.sim.systems.status")
local Wardrobe = require("src.sim.systems.wardrobe")
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
--- only, never saved: an away player's ignore window waits and nothing is offered but what a standing order answers. The scene calls this every frame.
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

-- Is this guard owned? A guard is catalog equipment (a cat, a fence, a lantern) or anything held in the ledger.
local function guardOwned(world, id)
  return Inventory.hasEquipment(world, id) or (world.registry:has("resources", id) and Ledger.get(world, id) > 0)
end

--- How much the homestead gives a night to work with: { points (0..10, 5 neutral), word ("low" | "medium" | "high"),
--- multiplier (on the night's chance), parts = { shelter (id or nil), stores (ids in stock that attract animals),
--- animals (hens and goats kept), guards (ids owned that count) } }. Shelter, stores that attract animals and livestock
--- raise it; each owned guard in tuning.night.exposure.guards lowers it by its points (C7 adds the guards). With a
--- `threatId` only the guards that cover that threat count (a guard lists the threats it covers, PLAN_DEPTH 6.1).
function Events.exposure(world, threatId)
  local x = world.tuning.night.exposure
  local points = x.neutral
  local shelter = Shelter.id(world)
  local shelterPoints = shelter and rawget(x.shelter, shelter) or 0 -- a shelter the table does not list adds nothing
  points = points + shelterPoints
  local parts = { shelter = shelter, stores = {}, animals = Animals.hens(world) + Animals.goats(world), guards = {} }
  for _, id in ipairs(sortedKeys(x.stores)) do
    if Ledger.get(world, id) > 0 then
      points = points + x.stores[id]
      parts.stores[#parts.stores + 1] = id
    end
  end
  points = points + math.min(x.maxLivestock, parts.animals * x.perAnimal)
  for _, id in ipairs(sortedKeys(x.guards)) do
    local guard = x.guards[id]
    if guardOwned(world, id) and (threatId == nil or contains(guard.covers, threatId)) then
      points = points - guard.points
      parts.guards[#parts.guards + 1] = id
    end
  end
  points = math.max(x.min, math.min(x.max, points))
  local word = points < x.lowBelow and "low" or (points >= x.highFrom and "high" or "medium")
  local share = (points - x.min) / (x.max - x.min)
  return {
    points = points,
    word = word,
    multiplier = x.chanceAtMin + (x.chanceAtMax - x.chanceAtMin) * share,
    parts = parts,
  }
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

--- Is the post-bad cooldown running (a bad event or a landed threat in the last tuning.events.badCooldownNights nights)?
function Events.cooling(world)
  return Calendar.now(world).day <= state(world).coolUntil
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

-- Is an object with one of these ids placed (the wood stove)? Only the heat sources are looked at, from the cached index.
local function placedAny(world, ids)
  local objects = world.state.grid.objects
  for _, anchor in ipairs(Grid.anchorsWith(world, "heatSource")) do
    if contains(ids, objects[anchor].id) then
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
  if cond.noStatus and anyStatus(world, cond.noStatus) then
    return false
  end
  if cond.coldNight ~= nil and (Needs.warmthNeeded(world) >= cfg(world).body.coldNightNeed) ~= cond.coldNight then
    return false
  end
  if cond.thirsty ~= nil and (Needs.waterOutlook(world).days < cfg(world).body.thirstyDays) ~= cond.thirsty then
    return false
  end
  if cond.placed and not placedAny(world, cond.placed) then
    return false
  end
  if cond.feet and Wardrobe.classOf(world, "feet") ~= cond.feet then
    return false
  end
  if cond.outfit and Wardrobe.outfitLean(world) ~= cond.outfit then
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
  if
    weight <= 0
    or not holds(world, d.conditions)
    or not holds(world, d.drawConditions)
    or Events.blocked(world, d)
  then
    return 0
  end
  if d.fall then
    weight = weight * Stats.factor(world, "fallChance") -- a fall is likelier with a bad ankle (PLAN_DEPTH 6.2)
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
  -- Its own stream: choosing must never move the dusk draw ("two rolls per dusk" on the `event` stream).
  local rng, picked = world:rng("eventTiles"), {}
  for _ = 1, math.min(count, #tiles) do
    picked[#picked + 1] = table.remove(tiles, rng:int(1, #tiles))
  end
  return picked
end

local function applyEffect(world, effect, depth, from)
  local s, c = state(world), cfg(world)
  effect = Events.effective(world, effect)
  local now = Calendar.now(world)
  local day = now.day
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
  local later = effect.later
  if later then
    -- A delayed outcome (an infection two mornings on): `hours` from now, or `days` on at `hour` (default the same hour).
    local due = later.hours and stamp(day, now.hour) + later.hours or stamp(day + later.days, later.hour or now.hour)
    s.delayed[#s.delayed + 1] = { due = due, from = from, chance = later.chance, effect = later.effect }
  end
end

-- Land the delayed outcomes that are due. A chance is a tuning.events.chances key, rolled on its own stream so that what
-- the player chose never moves the dusk draw. The effect is the outcome's own, with no `later` of its own.
local function landDelayed(world)
  local s, c = state(world), cfg(world)
  local at = nowStamp(world)
  local i = 1
  while i <= #s.delayed do
    local item = s.delayed[i]
    if item.due <= at then
      table.remove(s.delayed, i)
      local hit = item.chance == nil or world:rng("eventLater"):float() < c.chances[item.chance]
      if hit then
        applyEffect(world, item.effect, c.maxChainDepth, item.from)
      end
      world.events:emit("event.later", { id = item.from, hit = hit })
    else
      i = i + 1
    end
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

--- Offer a night event a threat woke the homesteader for (C1's `wake`): the same road as a drawn event, so the hour, the
--- budget and every mercy rule still apply when it comes due (not before night `firstNight`, one wake a night, nothing
--- while Footing is slipped or Condition is low). Returns whether it was scheduled.
function Events.scheduleWake(world, id)
  local d = def(world, id)
  if not d.wake or d.when ~= "night" or Calendar.now(world).day < cfg(world).firstNight then
    return false
  end
  schedule(world, id, Calendar.now(world).day, 0)
  return true
end

local resolve -- (below) apply an outcome

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
  Events.answerByOrder(world, d)
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

resolve = function(world, option, reason)
  local s, c = state(world), cfg(world)
  local entry = table.remove(s.pending, 1)
  local d = def(world, entry.id)
  local outcome = option and d.options[option] or d.ignore
  applyEffect(world, outcome.effect, entry.depth, d.id)
  if d.bad then
    s.coolUntil = Calendar.now(world).day + c.badCooldownNights
  end
  record(world, d.id, option and "chosen" or "ignored", option, reason)
  local payload = { id = d.id, label = outcome.label, class = d.class, bad = d.bad }
  if option then
    payload.option = option
    payload.order = reason == "order" or nil
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

-- Standing orders ---------------------------------------------------------------------------------------

--- The event classes a standing order can be set for, and the modes, in the order the Routine screen lists them.
Events.CLASSES = { "body", "home", "land", "visitors" }
Events.MODES = { "ask", "careful", "bold" }

--- Is the "Rules of thumb" perk known, so the orders apply (and the Routine screen shows them)?
function Events.ordersUnlocked(world)
  return Journal.isKnown(world, cfg(world).ordersPerk)
end

--- The mode set for an event class: "ask" (default), "careful" or "bold". What the player chose, whether or not the perk is
--- known yet; Events.ordersUnlocked says whether it applies.
function Events.orderMode(world, class)
  return (world.meta.standingOrders or {})[class] or "ask"
end

--- Set the mode for an event class. Errors on an unknown class or mode.
function Events.setOrder(world, class, mode)
  if not contains(Events.CLASSES, class) then
    error("Unknown event class '" .. tostring(class) .. "'", 2)
  end
  if not contains(Events.MODES, mode) then
    error("Unknown standing order '" .. tostring(mode) .. "'", 2)
  end
  local orders = world.meta.standingOrders or {}
  world.meta.standingOrders = orders
  orders[class] = mode ~= "ask" and mode or nil
end

--- The stock of `id` a standing order's Careful option must leave (B5, D176): the keep target the player set, for wood at
--- least the wood still needed to reach the end of winter (not the automatic keep, which holds a second winter and so
--- equals the woodpile all year), for drinking water at least the day's need. Every other automatic keep is not a floor.
function Events.orderFloor(world, id)
  local keeps, auto = Food.keeps(world)
  local floor = auto[id] and 0 or (keeps[id] or 0)
  if id == Needs.fuelId(world) then
    floor = math.max(floor, Food.winterWoodNeed(world))
  elseif id == Needs.WATER then
    floor = math.max(floor, math.ceil(Needs.waterNeeded(world)))
  end
  return floor
end

--- What an order does with event `d`: the option index to take, or nil + why it fell back ("none": no such option, "short":
--- cannot pay, "keep": paying would drop a stock under its keep target) + the resource that stopped it.
local function orderChoice(world, d, mode)
  local index
  for i, o in ipairs(d.options) do
    if o[mode] == true then
      index = i
      break
    end
  end
  if not index then
    return nil, "none"
  end
  local cost = d.options[index].cost
  local missing = lacking(world, cost)
  if missing then
    return nil, "short", missing
  end
  for _, id in ipairs(sortedKeys(cost or {})) do
    if Ledger.get(world, id) - cost[id] < Events.orderFloor(world, id) then
      return nil, "keep", id
    end
  end
  return index
end

--- Does a standing order apply to event `d` (the perk is known and its class is not Ask me)?
function Events.orderApplies(world, d)
  return Events.ordersUnlocked(world) and Events.orderMode(world, d.class) ~= "ask"
end

--- Answer the open card by the standing order for its class, if the perk is known and the class is not Ask me. Returns whether
--- it did. Called when an event is offered (and public for tests).
function Events.answerByOrder(world, d)
  local mode = Events.orderMode(world, d.class)
  local head = state(world).pending[1]
  if not Events.orderApplies(world, d) or not head or head.id ~= d.id then
    return false
  end
  local index, why, resource = orderChoice(world, d, mode)
  if index then
    local cost = d.options[index].cost
    if cost then
      Ledger.spend(world, cost, "event")
    end
  elseif why ~= "none" then
    world.events:emit(
      "event.orderFallback",
      { id = d.id, class = d.class, mode = mode, why = why, resource = resource }
    )
  end
  resolve(world, index, "order")
  return true
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
--- No draw is made (and the pity count does not move) while a card is pending or the player is away, so a long absence
--- cannot pile up a queue that is later offered one a day.
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
  if #s.pending > 0 or Events.away(world) then
    return nil -- no backlog while a card is open or the player is away (D175): the night passes undrawn, the pity timer waits
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

-- Is something to offer now? One per tick, in order, never behind an open card. While the player is away only an event whose
-- class has a standing order that applies is offered (the order answers it at once, PLAN_DEPTH 6.3); the rest wait.
local function offerDue(world)
  local s = state(world)
  if #s.pending > 0 then
    return
  end
  local away = Events.away(world)
  local at = nowStamp(world)
  for i, item in ipairs(s.scheduled) do
    if item.due <= at and (not away or Events.orderApplies(world, def(world, item.id))) then
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
--- worst reachable chain never worse than the worse option, and the status it applies, landing on every active status of
--- its family at every severity, escalates or worsens none of them (Status.resolve).
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
  later = true,
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
    if effect.later then
      local r = reach(effect.later.effect, seen) -- what could land later counts, whatever its chance
      out.severity = math.max(out.severity, r.severity)
      out.condition = math.max(out.condition, r.condition)
    end
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
        local later = o.effect.later
        if later then
          if type(later.effect) ~= "table" or not (later.hours or later.days) then
            bad(id, where .. ": later needs an effect and hours or days")
          else
            if later.chance and cfg(world).chances[later.chance] == nil then
              bad(id, where .. ": later names the unknown chance " .. tostring(later.chance))
            end
            for _, sid in ipairs(statusIds(later.effect)) do
              if not reg:has("statuses", sid) then
                bad(id, where .. ": later names the unknown status " .. sid)
              end
            end
            for key in pairs(later.effect) do
              if not EFFECT_KEYS[key] or key == "later" or key == "chain" or key == "capital" or key == "damage" then
                bad(id, where .. ": a later effect cannot use '" .. key .. "'")
              end
            end
            if later.effect.condition and later.effect.condition >= 0 then
              bad(id, where .. ": a later condition is a loss, so negative")
            end
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
          for _, forbidden in ipairs({
            "condition",
            "chain",
            "later",
            "damage",
            "capital",
            "lockTiles",
            "damageTiles",
            "lose",
          }) do
            if o.effect[forbidden] then
              bad(id, "ignore must not use " .. forbidden .. " (free, safe, non-escalating)")
            end
          end
          for _, sid in ipairs(statusIds(o.effect)) do
            if reg:has("statuses", sid) and reg:get("statuses", sid).escalatesTo then
              bad(id, "ignore applies " .. sid .. ", which can escalate")
            end
            -- Landing on top of any active status of its family, at every severity, it must change nothing (D175).
            if reg:has("statuses", sid) then
              local applied = reg:get("statuses", sid)
              for _, active in ipairs(reg:all("statuses")) do
                if active.family == applied.family then
                  local held = Status.resolve(world, active.id, sid)
                  if held ~= active.id then
                    bad(id, "ignore applies " .. sid .. " on " .. active.id .. " and it becomes " .. held)
                  end
                end
              end
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
  s.delayed = s.delayed or {}
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
  if #s.delayed > 0 then
    landDelayed(world)
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
