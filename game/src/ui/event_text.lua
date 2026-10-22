-- The words of the event card (D172, #348, docs/PLAN_DEPTH.md §6.2, §6.3): pure functions that turn the open card
-- (Events.pending) into plain text, so the card and a test say the same thing and no window is needed. Each option states
-- its cost and its effect in plain words and how safe it is; one with a cost the player cannot pay is disabled with the
-- reason; the ignore outcome is always shown; the timer says how long the ignore window has left. Colour is never the
-- only signal: every state is also a word.

local EventText = {}

EventText.free = "Free"
EventText.noEffect = "Nothing lasting."
EventText.ignoreHead = "If you do nothing: %s"
EventText.waiting = "Waiting for you"
EventText.paused = "Time is paused"
EventText.secondsLeft = "Settles itself in %d s"
EventText.minutesLeft = "Settles itself in %d:%02d"
EventText.wake = "This one woke you."
EventText.stamp = "Event"
EventText.ignoredToast = "Time ran out: %s"
EventText.orderToast = "Your rule: %s"
EventText.busy = "Answer the event first."
EventText.lacks = "Needs %s: you have %d"

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- "2 wood, 1 water" for a table of amounts. `name(id)` gives a resource's name.
local function amounts(list, name)
  local parts = {}
  for _, id in ipairs(sortedKeys(list)) do
    parts[#parts + 1] = string.format("%d %s", list[id], name(id):lower())
  end
  return table.concat(parts, ", ")
end

--- The cost line: "Free", or "Costs 2 wood, 1 water".
function EventText.costLine(cost, name)
  if not cost or next(cost) == nil then
    return EventText.free
  end
  return "Costs " .. amounts(cost, name)
end

--- A status's words: "Hobbling: Work 20% slower, 1 day".
local function statusWords(def)
  local span = def.duration and (", " .. plural(def.duration, "day")) or ", until cured"
  return string.format("%s: %s%s", def.name, def.line, span)
end

--- What an effect does, as a list of short phrases. `env.status(id)` returns a status definition, `env.name(id)` a
--- resource's name. An effect that changes nothing the player can see (a journal note, a flag) says nothing.
function EventText.effectWords(effect, env)
  local out = {}
  if not effect then
    return out
  end
  if effect.status then
    local ids = type(effect.status) == "table" and effect.status or { effect.status }
    for _, id in ipairs(ids) do
      out[#out + 1] = statusWords(env.status(id))
    end
  end
  if effect.later then
    -- An outcome that lands later says "may" when it is a chance, and never the odds (PLAN_DEPTH 6.2).
    local later = EventText.effectWords(effect.later.effect, env)
    out[#out + 1] = (effect.later.chance and "Later, it may: " or "Later: ") .. table.concat(later, "; ")
  end
  if effect.gain then
    out[#out + 1] = "Gain " .. amounts(effect.gain, env.name)
  end
  if effect.lose then
    out[#out + 1] = "Lose " .. amounts(effect.lose, env.name)
  end
  if effect.condition and effect.condition ~= 0 then
    out[#out + 1] = string.format("Condition %+d", effect.condition)
  end
  if effect.lockTiles then
    out[#out + 1] = string.format(
      "%s locked for %s",
      plural(effect.lockTiles.count, "planted tile"),
      plural(effect.lockTiles.days, "day")
    )
  end
  if effect.damageTiles then
    out[#out + 1] = string.format("%s set back", plural(effect.damageTiles.count, "planted tile"))
  end
  if effect.damage then
    local names = {}
    for _, n in ipairs(effect.damage) do
      names[#names + 1] = n:gsub("_", " ")
    end
    out[#out + 1] = "Leaves damage: " .. table.concat(names, ", ")
  end
  if effect.repair then
    local names = {}
    for _, n in ipairs(effect.repair) do
      names[#names + 1] = n:gsub("_", " ")
    end
    out[#out + 1] = "Mended: " .. table.concat(names, ", ")
  end
  if effect.freezePipes then
    out[#out + 1] = "No pumped water until noon"
  end
  return out
end

--- Seconds the ignore window has left, or nil when game time is not running (paused: the hours do not count down). Both
--- clocks must run out (PLAN_DEPTH 6.3): the real-seconds floor and the game hours at the speed now.
function EventText.remaining(realLeft, hoursLeft, hourSeconds, speed)
  if speed <= 0 then
    if realLeft > 0 or hoursLeft > 0 then
      return nil
    end
    return 0
  end
  return math.max(realLeft, math.max(0, hoursLeft) * hourSeconds / speed)
end

--- How much of the window is left, 0..1 (the bar): the larger of the two clocks' shares, since both must run out.
function EventText.fraction(realLeft, hoursLeft, minSeconds, hours)
  return math.max(0, math.min(1, math.max(realLeft / minSeconds, hoursLeft / hours)))
end

--- The timer's line.
function EventText.timerLine(seconds, away)
  if away then
    return EventText.waiting
  elseif seconds == nil then
    return EventText.paused
  elseif seconds >= 60 then
    local whole = math.ceil(seconds)
    return string.format(EventText.minutesLeft, math.floor(whole / 60), whole % 60)
  end
  return string.format(EventText.secondsLeft, math.ceil(seconds))
end

--- The card for the open event `ev` (Events.pending). `env` = { name(id), have(id), status(id), away, speed, hourSeconds,
--- ignoreHours, ignoreMinSeconds }. Returns { title, line, wake, options = { { index, label, cost, effects, risk,
--- enabled, reason } x2 }, ignore = { head, cost, effects, risk }, timer = { text, fraction, seconds } }.
function EventText.build(ev, env)
  local options = {}
  for i, o in ipairs(ev.options) do
    local reason
    if not o.affordable then
      reason = string.format(EventText.lacks, env.name(o.lacking):lower(), env.have(o.lacking))
    end
    local effects = EventText.effectWords(o.effect, env)
    if #effects == 0 then
      effects = { EventText.noEffect }
    end
    options[i] = {
      index = o.index,
      label = o.label,
      cost = EventText.costLine(o.cost, env.name),
      effects = effects,
      risk = o.risk,
      enabled = o.affordable,
      reason = reason,
    }
  end
  local ignoreEffects = EventText.effectWords(ev.ignore.effect, env)
  if #ignoreEffects == 0 then
    ignoreEffects = { EventText.noEffect }
  end
  local seconds = EventText.remaining(ev.realLeft, ev.hoursLeft, env.hourSeconds, env.speed)
  return {
    title = ev.title,
    line = ev.line,
    wake = ev.wake,
    options = options,
    ignore = {
      head = string.format(EventText.ignoreHead, ev.ignore.label),
      cost = EventText.free,
      effects = ignoreEffects,
      risk = ev.ignore.risk,
    },
    timer = {
      text = EventText.timerLine(seconds, env.away),
      seconds = seconds,
      fraction = EventText.fraction(ev.realLeft, ev.hoursLeft, env.ignoreMinSeconds, env.ignoreHours),
    },
  }
end

return EventText
