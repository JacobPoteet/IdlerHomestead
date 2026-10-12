-- Field Journal (GDD §8.1–8.2): Notes → Ideas → Study at night → Known.
--
-- Notes are written from world events by data rules (data/content/notes.lua); the systems that
-- emit those events never know the journal exists (GDD §12.1 #8). Journal nodes are catalog items
-- and perks (one id space); a node becomes an idea once every note in its `needs` is written. The player queues ideas to study; the head of
-- the queue makes progress while the homesteader sleeps (longer nights study faster, equipment
-- with a `studySpeed` modifier speeds it up) and becomes known for good.
--
-- Everything here lives in the save slot's meta, so it survives failed runs:
--   world.meta.journal = {
--     notes = { [noteId] = { day, season, year, run } }, -- when it was written (day of season, run #)
--     counts = { [noteId] = n },                     -- matching events so far (count notes)
--     known = { [itemId] = true },
--     queue = { itemId, ... },                       -- study order; [1] is being studied
--     progress = { [itemId] = nights },              -- kept if unqueued: nothing is spent
--   }
-- Emits "journal.note" { note }, "journal.idea" { item }, "journal.learned" { item }.

local Calendar = require("src.sim.systems.calendar")
local Power = require("src.sim.systems.power")
local Sleep = require("src.sim.systems.sleep")
local Stats = require("src.sim.stats")

local Journal = {}

local function journal(world)
  return world.meta.journal
end

-- Content kinds whose entries are journal nodes, in display order.
local NODE_KINDS = { "catalog", "perks" }

--- The definition of a journal node (catalog item or perk). Errors on unknown ids.
local function item(world, id)
  for _, kind in ipairs(NODE_KINDS) do
    if world.registry:has(kind, id) then
      return world.registry:get(kind, id)
    end
  end
  error("Unknown journal node '" .. tostring(id) .. "'", 2)
end
Journal.node = item

--- "catalog" or "perks" for a node id.
function Journal.kindOf(world, id)
  for _, kind in ipairs(NODE_KINDS) do
    if world.registry:has(kind, id) then
      return kind
    end
  end
  return nil
end

--- Every journal node, catalog first, then perks.
function Journal.nodes(world)
  local list = {}
  for _, kind in ipairs(NODE_KINDS) do
    for _, def in ipairs(world.registry:all(kind)) do
      list[#list + 1] = def
    end
  end
  return list
end

--- The chapters of the knowledge map (data/content/chapters.lua) with the nodes they hold, in
--- map order. A node belongs to the chapter that lists its `page`; chapters without nodes are left out.
--- Returns { { id, name, nodes = { def, ... } }, ... }.
function Journal.chapters(world)
  local list, byPage = {}, {}
  for _, chapter in ipairs(world.registry:all("chapters")) do
    local entry = { id = chapter.id, name = chapter.name, nodes = {} }
    list[#list + 1] = entry
    for _, page in ipairs(chapter.pages) do
      byPage[page] = byPage[page] or entry
    end
  end
  for _, def in ipairs(Journal.nodes(world)) do
    local entry = byPage[def.page]
    if entry then
      entry.nodes[#entry.nodes + 1] = def
    end
  end
  local shown = {}
  for _, entry in ipairs(list) do
    if #entry.nodes > 0 then
      shown[#shown + 1] = entry
    end
  end
  return shown
end

--- The id of the chapter a node sits in, or nil if no chapter lists its page.
function Journal.chapterOf(world, id)
  local page = item(world, id).page
  for _, chapter in ipairs(world.registry:all("chapters")) do
    for _, listed in ipairs(chapter.pages) do
      if listed == page then
        return chapter.id
      end
    end
  end
  return nil
end

local function isStarter(world, id)
  return world.registry:has("catalog", id) and world.registry:get("catalog", id).starter == true
end

function Journal.hasNote(world, id)
  world.registry:get("notes", id)
  return journal(world).notes[id] ~= nil
end

--- When a note was written ({ day = day of season, season, year, run }), or nil.
function Journal.noteInfo(world, id)
  return journal(world).notes[id]
end

function Journal.isKnown(world, id)
  item(world, id)
  return isStarter(world, id) or journal(world).known[id] == true
end

--- Has every note this item needs been written? (Known items count too.)
local function needsMet(world, def)
  if not def.needs then
    return false
  end
  for _, note in ipairs(def.needs) do
    if not journal(world).notes[note] then
      return false
    end
  end
  return true
end

--- An item you could study: all its notes are written but it isn't known yet.
function Journal.isIdea(world, id)
  local def = item(world, id)
  return not Journal.isKnown(world, id) and needsMet(world, def)
end

local function queueIndex(world, id)
  for n, queued in ipairs(journal(world).queue) do
    if queued == id then
      return n
    end
  end
  return nil
end

--- "known" | "studying" (head of the queue) | "queued" | "idea" | "unknown".
function Journal.status(world, id)
  if Journal.isKnown(world, id) then
    return "known"
  end
  local n = queueIndex(world, id)
  if n == 1 then
    return "studying"
  elseif n then
    return "queued"
  elseif Journal.isIdea(world, id) then
    return "idea"
  end
  return "unknown"
end

--- Study progress as a fraction 0..1.
function Journal.progress(world, id)
  local def = item(world, id)
  if Journal.isKnown(world, id) then
    return 1
  end
  return math.min(1, (journal(world).progress[id] or 0) / (def.studyNights or 1))
end

--- Known perks (their effects apply), in content order.
function Journal.knownPerks(world)
  local list = {}
  for _, def in ipairs(world.registry:all("perks")) do
    if journal(world).known[def.id] then
      list[#list + 1] = def
    end
  end
  return list
end

--- Ideas not yet known, catalog then perks (queued ones included).
function Journal.ideas(world)
  local list = {}
  for _, def in ipairs(Journal.nodes(world)) do
    if Journal.isIdea(world, def.id) then
      list[#list + 1] = def
    end
  end
  return list
end

function Journal.queue(world)
  return journal(world).queue
end

--- A gentle prompt: there are ideas to study but nothing is queued (GDD §8.1).
function Journal.needsChoice(world)
  if #journal(world).queue > 0 then
    return false
  end
  return #Journal.ideas(world) > 0
end

--- Add an idea to the end of the study queue. Returns true, or false + reason.
function Journal.study(world, id)
  if Journal.isKnown(world, id) then
    return false, "known"
  end
  if queueIndex(world, id) then
    return false, "queued"
  end
  if not Journal.isIdea(world, id) then
    return false, "not an idea"
  end
  local queue = journal(world).queue
  if #queue >= world.tuning.study.queueSize then
    return false, "queue full"
  end
  queue[#queue + 1] = id
  return true
end

--- Take an idea off the queue. Its progress is kept.
function Journal.unqueue(world, id)
  local n = queueIndex(world, id)
  if n then
    table.remove(journal(world).queue, n)
  end
  return n ~= nil
end

local function learn(world, id)
  local j = journal(world)
  j.known[id] = true
  j.progress[id] = nil
  local n = queueIndex(world, id)
  if n then
    table.remove(j.queue, n)
  end
  world.events:emit("journal.learned", { item = id })
end

--- Learn an idea right away, skipping study (the free study during recovery, GDD §4.3).
--- Returns true, or false + reason.
function Journal.learnNow(world, id)
  if Journal.isKnown(world, id) then
    return false, "known"
  end
  if not Journal.isIdea(world, id) then
    return false, "not an idea"
  end
  learn(world, id)
  return true
end

--- Finish the study in progress right away (recovery after a rescue, GDD §4.3).
--- Returns the item learned, or nil if nothing was queued.
function Journal.finishStudy(world)
  local head = journal(world).queue[1]
  if head then
    learn(world, head)
  end
  return head
end

-- Notes ------------------------------------------------------------------------------------

local function matches(rule, e)
  for field, want in pairs(rule or {}) do
    local value = e[field]
    if type(want) == "table" then
      if type(value) ~= "number" then
        return false
      end
      if (want.min and value < want.min) or (want.max and value > want.max) then
        return false
      end
    elseif value ~= want then
      return false
    end
  end
  return true
end

local function writeNote(world, def)
  local j = journal(world)
  -- Ideas this note completes, so the player hears about each new one.
  local nodes = Journal.nodes(world)
  local before = {}
  for _, entry in ipairs(nodes) do
    before[entry.id] = Journal.isIdea(world, entry.id)
  end
  local now = Calendar.now(world)
  local career = world.meta.career
  j.notes[def.id] = { day = now.dayOfSeason, season = now.season, year = now.year, run = career and career.runs or 1 }
  j.counts[def.id] = nil
  world.events:emit("journal.note", { note = def.id })
  for _, entry in ipairs(nodes) do
    if not before[entry.id] and Journal.isIdea(world, entry.id) then
      world.events:emit("journal.idea", { item = entry.id })
    end
  end
end

local function listen(world)
  local byEvent, order = {}, {}
  for _, def in ipairs(world.registry:all("notes")) do
    if not byEvent[def.event] then
      byEvent[def.event] = {}
      order[#order + 1] = def.event
    end
    local list = byEvent[def.event]
    list[#list + 1] = def
  end
  for _, name in ipairs(order) do
    local defs = byEvent[name]
    world.events:on(name, function(e)
      local j = journal(world)
      for _, def in ipairs(defs) do
        if not j.notes[def.id] and matches(def.match, e or {}) then
          local count = (j.counts[def.id] or 0) + 1
          if count >= (def.count or 1) then
            writeNote(world, def)
          else
            j.counts[def.id] = count
          end
        end
      end
    end)
  end
end

function Journal.init(world)
  local j = world.meta.journal or {}
  j.notes = j.notes or {}
  j.counts = j.counts or {}
  j.known = j.known or {}
  j.queue = j.queue or {}
  j.progress = j.progress or {}
  world.meta.journal = j
  listen(world)
end

function Journal.tick(world, dt)
  local j = journal(world)
  local head = j.queue[1]
  if not head or not Sleep.homesteaderResting(world) then
    return
  end
  local cfg = world.tuning.study
  local hours = dt / Calendar.hourLength(world)
  local rate = (1 + Stats.modifier(world, "studySpeed") + Power.effect(world, "studySpeed")) / cfg.nightHours -- a powered lamp helps
  j.progress[head] = (j.progress[head] or 0) + hours * rate
  if j.progress[head] >= item(world, head).studyNights - cfg.finishSlack then
    learn(world, head)
  end
end

return Journal
