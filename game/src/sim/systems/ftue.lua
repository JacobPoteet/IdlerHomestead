-- First-time user experience (GDD D69, #152): decides which contextual tip card is due.
--
-- Steps are content (data/content/ftue.lua). This system listens to the event bus, queues a step the
-- first time its trigger happens, and hands the scene the one card that is due. It draws nothing and
-- never pauses the sim; the scene shows the card and calls dismiss/skip.
--
-- State lives in the slot's meta (so "skip" and "seen" persist per save slot, across runs):
--   meta.ftue = { seen = { [id] = true }, seenAt = { [id] = game seconds }, off = bool,
--                 queue = { { id, due = game seconds } ... }, lastShown = game seconds? }
-- A slot whose meta has no `ftue` (saved before D69, or a world built without a slot) counts as
-- finished, so veterans are not nagged. A brand-new slot calls Ftue.begin(meta, true).
-- Times are Calendar.elapsed, which restarts with each run; the tips are off from the second run on.

local Calendar = require("src.sim.systems.calendar")

local Ftue = {}

--- Start the tips for a brand-new slot's meta (`on` false starts it finished, for tools and tests).
function Ftue.begin(meta, on)
  meta.ftue = { seen = {}, seenAt = {}, queue = {}, off = not on }
  return meta.ftue
end

--- The slot's tip state; a slot without one is created finished.
function Ftue.state(world)
  local meta = world.meta
  if not meta.ftue then
    Ftue.begin(meta, false)
  end
  local st = meta.ftue
  st.seen, st.seenAt, st.queue = st.seen or {}, st.seenAt or {}, st.queue or {}
  return st
end

function Ftue.enabled(world)
  return not Ftue.state(world).off
end

local function stepDef(world, id)
  return world.registry:get("ftue", id)
end

--- Has the player been told this step (by its card, a skip of it, or the card that covers it)?
function Ftue.isSeen(world, id)
  local def = stepDef(world, id)
  if Ftue.state(world).seen[id] then
    return true
  end
  return def.doneFlag ~= nil and world.meta[def.doneFlag] == true
end

local function queued(st, id)
  for _, entry in ipairs(st.queue) do
    if entry.id == id then
      return true
    end
  end
  return false
end

--- Queue a step, due `delay` game seconds from now (unless it is seen, queued, or tips are off).
local function enqueue(world, def)
  local st = Ftue.state(world)
  if st.off or def.card == false or Ftue.isSeen(world, def.id) or queued(st, def.id) then
    return false
  end
  local delay = def.delay or world.tuning.ftue.defaultDelay
  st.queue[#st.queue + 1] = { id = def.id, due = Calendar.elapsed(world) + delay }
  return true
end

local function matches(def, payload)
  if not def.match then
    return true
  end
  for field, want in pairs(def.match) do
    if type(payload) ~= "table" or payload[field] ~= want then
      return false
    end
  end
  return true
end

-- Take a step out of the queue and mark it seen.
local function settle(world, id)
  local st = Ftue.state(world)
  for i, entry in ipairs(st.queue) do
    if entry.id == id then
      table.remove(st.queue, i)
      break
    end
  end
  st.seen[id] = true
  st.seenAt[id] = Calendar.elapsed(world)
end

local function queueStarts(world)
  for _, def in ipairs(world.registry:all("ftue")) do
    if def.trigger == "start" then
      enqueue(world, def)
    end
  end
end

function Ftue.init(world)
  Ftue.state(world)
  local byEvent, retireBy = {}, {}
  for _, def in ipairs(world.registry:all("ftue")) do
    if def.trigger and def.trigger ~= "start" then
      byEvent[def.trigger] = byEvent[def.trigger] or {}
      table.insert(byEvent[def.trigger], def)
    end
    for _, event in ipairs(def.retire or {}) do
      retireBy[event] = retireBy[event] or {}
      table.insert(retireBy[event], def)
    end
  end
  local names = {}
  for event in pairs(byEvent) do
    names[event] = true
  end
  for event in pairs(retireBy) do
    names[event] = true
  end
  for event in pairs(names) do
    world.events:on(event, function(payload)
      for _, def in ipairs(retireBy[event] or {}) do
        if not Ftue.isSeen(world, def.id) then
          settle(world, def.id) -- the player already knows it: no card
        end
      end
      for _, def in ipairs(byEvent[event] or {}) do
        if matches(def, payload) then
          enqueue(world, def)
        end
      end
    end)
  end
  queueStarts(world)
end

--- Steps that become due a while after another was dismissed (checked every tick; cheap).
function Ftue.tick(world)
  local st = world.meta.ftue
  if not st or st.off then
    return
  end
  local now = Calendar.elapsed(world)
  for _, def in ipairs(world.registry:all("ftue")) do
    local after = def.after
    if after and st.seenAt[after.step] and st.seenAt[after.step] + after.seconds <= now then
      enqueue(world, def)
    end
  end
end

--- The card to show now ({ id, title, text, def }) or nil: the due step that comes first in the
--- content, and only once `tuning.ftue.minGap` has passed since the last card was dismissed.
function Ftue.current(world)
  local st = Ftue.state(world)
  if st.off or #st.queue == 0 then
    return nil
  end
  local now = Calendar.elapsed(world)
  if st.lastShown and now - st.lastShown < world.tuning.ftue.minGap then
    return nil
  end
  local due = {}
  for _, entry in ipairs(st.queue) do
    if entry.due <= now then
      due[entry.id] = true
    end
  end
  for _, def in ipairs(world.registry:all("ftue")) do
    if due[def.id] then
      return { id = def.id, title = def.title, text = Ftue.text(world, def), def = def }
    end
  end
  return nil
end

--- A step's text with its {domain.key} tokens read from tuning.
function Ftue.text(world, def)
  return (def.text:gsub("{([%w_]+)%.([%w_]+)}", function(domain, key)
    return tostring(world.tuning[domain][key])
  end))
end

--- The player closed the current card.
function Ftue.dismiss(world, id)
  settle(world, id)
  Ftue.state(world).lastShown = Calendar.elapsed(world)
end

--- "Skip tips": no more cards, now or later in this slot.
function Ftue.skip(world)
  local st = Ftue.state(world)
  st.off = true
  st.queue = {}
end

--- Menu toggle. Turning tips on again keeps what was already seen.
function Ftue.setEnabled(world, on)
  local st = Ftue.state(world)
  st.off = not on
  if not on then
    st.queue = {}
  end
end

--- Menu "Show all again": forget what was seen, so every tip comes back as its moment arrives.
function Ftue.reset(world)
  local st = Ftue.state(world)
  st.seen, st.seenAt, st.queue, st.lastShown, st.off = {}, {}, {}, nil, false
  queueStarts(world)
end

--- A new run begins: tips are for the first run only, so they stop (Menu > Tips can bring them back).
function Ftue.endForRun(meta)
  if meta.ftue then
    meta.ftue.off = true
    meta.ftue.queue = {}
  end
end

--- Every step, in content order, as { def, seen } for the Menu's Tips list.
function Ftue.steps(world)
  local out = {}
  for _, def in ipairs(world.registry:all("ftue")) do
    out[#out + 1] = { def = def, seen = Ftue.isSeen(world, def.id) }
  end
  return out
end

return Ftue
