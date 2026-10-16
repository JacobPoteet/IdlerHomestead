-- The homesteader's wardrobe (GDD §7.8, D149 to D153, docs/PLAN_WARDROBE.md). Five slots, three weight
-- classes: light clothes add a little work speed by day and need a little more heat at night, heavy clothes
-- need less heat and add no work, mid is the baseline and changes nothing. Garments are content
-- (data/content/garments.lua), the numbers are tuning.wardrobe.
--
-- State, in two places:
--   meta.wardrobe  (the save slot, kept across runs; only this system touches it)
--     { owned = { [id] = true }, fresh = { [id] = true } (earned, not yet looked at), stamp = bool (the
--       "New clothes" stamp is due), earned = { [id] = run number }, worn = { slot = id } (the outfit
--       chosen), presets = { warm = outfit?, cold = outfit? }, auto = bool,
--       counts = { seasons = { [season] = n }, winters, snowDays, snaps, frosts, harvests, crops = { [id] =
--       true }, trips, built = { [objectId] = true }, cleared = { [object] = n }, machines } }
--     `counts` holds what the unlocks count that nothing else records.
--   world.state.wardrobe  (the run) = { dressed = { slot = id } }: today's outfit, copied from `worn` at the
--     start of the run and at each new day. The numbers read `dressed`, so a mid-day change cannot touch
--     today (D149). Between runs there is no run: `dressed` is `worn`.
-- A Sandbox slot owns every garment and unlocks nothing (D134).
--
-- Accessors (the menu reads only these): slots, garments, owned, committed, dressed, dressedKey, appliesNow,
-- effects, scale, isNew, newCount, stampDue, earnedThisRun, preset, autoOn, threshold, progress.
-- Writers: wear, markSeen, stampSeen, savePreset, setAuto, grant (and evaluate, the unlock check).
-- Multipliers other systems use: insulation(world) and workBonus(world).
-- Emits "wardrobe.dressed" { dressed, reason } and "wardrobe.unlocked" { id, run }.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Sandbox = require("src.sim.systems.sandbox")

local Wardrobe = {}

-- Garment index ---------------------------------------------------------------------------------------

-- Per registry: the garments of each slot in content order and the default of each slot. A registry's
-- content never changes after loading, so this is built once. Weak-keyed, runtime only.
local indexCache = setmetatable({}, { __mode = "k" })

local function index(world)
  local registry = world.registry
  local found = indexCache[registry]
  if not found then
    found = { bySlot = {}, default = {} }
    for _, def in ipairs(registry:all("garments")) do
      local list = found.bySlot[def.slot] or {}
      found.bySlot[def.slot] = list
      list[#list + 1] = def
      if def.default then
        found.default[def.slot] = def.id
      end
    end
    indexCache[registry] = found
  end
  return found
end

local function cfg(world)
  return world.tuning.wardrobe
end

--- The garment of `slot` named `id`, or the slot's default when the id is unknown or belongs to another slot.
local function garmentIn(world, slot, id)
  local registry = world.registry
  if id and registry:has("garments", id) then
    local def = registry:get("garments", id)
    if def.slot == slot then
      return def
    end
  end
  return registry:get("garments", index(world).default[slot])
end

local function copyOutfit(world, outfit)
  local out = {}
  for _, slot in ipairs(cfg(world).slots) do
    out[slot] = outfit[slot]
  end
  return out
end

local function outfitKey(world, outfit)
  local parts = {}
  for i, slot in ipairs(cfg(world).slots) do
    parts[i] = outfit[slot] or "-"
  end
  return table.concat(parts, "|")
end

-- The slot's saved state -------------------------------------------------------------------------------

local function newCounts()
  return {
    seasons = {},
    winters = 0,
    snowDays = 0,
    snaps = 0,
    frosts = 0,
    harvests = 0,
    crops = {},
    trips = 0,
    built = {},
    cleared = {},
    machines = 0,
  }
end

--- Bring a (possibly loaded, possibly empty) meta.wardrobe to the full shape: every table present, the
--- starters owned, unknown ids dropped, `worn` naming a garment of the right slot for every slot.
local function sanitize(world, w)
  w.owned, w.fresh, w.earned, w.presets = w.owned or {}, w.fresh or {}, w.earned or {}, w.presets or {}
  w.stamp, w.auto = w.stamp == true, w.auto == true
  w.worn = w.worn or {}
  local counts = w.counts or newCounts()
  for key, value in pairs(newCounts()) do
    if counts[key] == nil then
      counts[key] = value
    end
  end
  w.counts = counts
  local registry = world.registry
  for id in pairs(w.owned) do
    if not registry:has("garments", id) then
      w.owned[id] = nil
    end
  end
  for id in pairs(w.fresh) do
    if not registry:has("garments", id) then
      w.fresh[id] = nil
    end
  end
  for _, def in ipairs(registry:all("garments")) do
    if def.starter then
      w.owned[def.id] = true
    end
  end
  local sandbox = Sandbox.on(world)
  for _, slot in ipairs(cfg(world).slots) do
    local id = w.worn[slot]
    local def = garmentIn(world, slot, id)
    if id ~= nil and (def.id ~= id or not (sandbox or w.owned[id])) then
      def = registry:get("garments", index(world).default[slot])
      print(
        string.format("wardrobe: '%s' is not a garment you can wear in slot %s; wearing %s", tostring(id), slot, def.id)
      )
    end
    w.worn[slot] = def.id
  end
  return w
end

--- The slot's wardrobe state, created on first use.
local function store(world)
  local w = world.meta.wardrobe
  if not w then
    w = {}
    world.meta.wardrobe = w
    sanitize(world, w)
  end
  return w
end

local function runNumber(world)
  local career = world.meta.career
  return career and career.runs or 1
end

-- Accessors ---------------------------------------------------------------------------------------------

--- The slot ids in display order.
function Wardrobe.slots(world)
  return cfg(world).slots
end

--- The garment definitions of a slot, in content order. Shared: read, never write.
function Wardrobe.garments(world, slot)
  return index(world).bySlot[slot] or {}
end

--- Does the slot own this garment? Everything is owned in a Sandbox slot.
function Wardrobe.owned(world, id)
  return Sandbox.on(world) or store(world).owned[id] == true
end

--- The outfit chosen in meta, `{ slot = id }`: a fresh table with an id for every slot.
function Wardrobe.committed(world)
  local worn = store(world).worn
  local out = {}
  for _, slot in ipairs(cfg(world).slots) do
    out[slot] = garmentIn(world, slot, worn[slot]).id
  end
  return out
end

-- Today's outfit as stored (the live table; internal). Falls back to the chosen outfit when there is no run
-- yet (a world still setting up) or no run at all.
local function today(world)
  local state = world.state
  local slice = state and state.wardrobe
  if slice then
    return slice.dressed
  end
  return store(world).worn
end

--- Today's outfit from the run's snapshot, a fresh table; the chosen outfit when there is no run.
function Wardrobe.dressed(world)
  local state = world.state
  if state and state.wardrobe then
    return copyOutfit(world, state.wardrobe.dressed)
  end
  return Wardrobe.committed(world)
end

--- A string that changes whenever the dressed outfit does (cheap to poll).
function Wardrobe.dressedKey(world)
  return outfitKey(world, today(world))
end

--- Does a Wear change today's outfit at once? True between runs (there is no run to protect) and in a run's
--- opening window (`tuning.wardrobe.appliesNow`); false otherwise, when the change waits for the next dawn.
function Wardrobe.appliesNow(world)
  if not world.state then
    return true
  end
  local window = cfg(world).appliesNow
  local now = Calendar.now(world)
  return now.day <= window.day and now.hour < window.untilHour
end

-- Weight points and class values summed over an outfit: work, cold. Allocation free (it runs every tick).
local function sums(world, outfit)
  local c = cfg(world)
  local work, cold = 0, 0
  for _, slot in ipairs(c.slots) do
    local def = garmentIn(world, slot, outfit[slot])
    local class = c.classes[def.class]
    local weight = c.slotWeight[slot]
    work = work + weight * class.work
    cold = cold + weight * class.cold
  end
  return work, cold
end

--- What an outfit does, as fractions: `{ work, cold }`. `work` is added to the work-speed bonus (0.04 is +4%),
--- `cold` to the night's warmth need (0.06 is +6% heat needed, -0.08 is 8% less). The same maths as
--- `insulation` and `workBonus`, before the floor. `outfit` defaults to today's.
function Wardrobe.effects(world, outfit)
  local work, cold = sums(world, outfit or today(world))
  return { work = work, cold = cold }
end

--- The largest magnitude an outfit can reach on each axis: `{ work, cold }`, the full half of a meter.
function Wardrobe.scale(world)
  local scale = cfg(world).scale
  return { work = scale.work, cold = scale.cold }
end

--- Multiplier on the night's warmth need from today's clothes, never below `insulationFloor`. Exactly 1 in
--- the starter outfit (all mid).
function Wardrobe.insulation(world)
  local _, cold = sums(world, today(world))
  return math.max(cfg(world).insulationFloor, 1 + cold)
end

--- Multiplier on the homesteader's work rate from today's clothes. Exactly 1 in the starter outfit.
function Wardrobe.workBonus(world)
  local work = sums(world, today(world))
  return 1 + work
end

-- New markers --------------------------------------------------------------------------------------------

--- Is this garment earned and not yet looked at?
function Wardrobe.isNew(world, id)
  return store(world).fresh[id] == true
end

--- How many garments are new, in `slot` or in all slots.
function Wardrobe.newCount(world, slot)
  local registry = world.registry
  local n = 0
  for id in pairs(store(world).fresh) do
    if registry:has("garments", id) and (slot == nil or registry:get("garments", id).slot == slot) then
      n = n + 1
    end
  end
  return n
end

--- Is the "New clothes" decision stamp due?
function Wardrobe.stampDue(world)
  return not Sandbox.on(world) and store(world).stamp == true
end

--- Garment ids earned in a run (default: this run), in content order, for the recovery row.
function Wardrobe.earnedThisRun(world, run)
  run = run or runNumber(world)
  local earned = store(world).earned
  local out = {}
  for _, def in ipairs(world.registry:all("garments")) do
    if earned[def.id] == run then
      out[#out + 1] = def.id
    end
  end
  return out
end

--- A saved outfit (`warm` or `cold`) as a fresh table, or nil when nothing was saved there.
function Wardrobe.preset(world, name)
  local saved = store(world).presets[name]
  if not saved then
    return nil
  end
  local out = {}
  for _, slot in ipairs(cfg(world).slots) do
    out[slot] = garmentIn(world, slot, saved[slot]).id
  end
  return out
end

--- Does the slot switch to a saved outfit by the forecast at dawn?
function Wardrobe.autoOn(world)
  return store(world).auto == true
end

-- Writers --------------------------------------------------------------------------------------------------

local function snapshot(world, reason)
  local slice = world.state.wardrobe
  local now = Wardrobe.committed(world)
  local changed = outfitKey(world, slice.dressed) ~= outfitKey(world, now)
  slice.dressed = now
  if changed then
    world.events:emit("wardrobe.dressed", { dressed = copyOutfit(world, now), reason = reason })
  end
end

--- Choose an outfit: `outfit` is `{ slot = id }` for the slots to change (the others keep what they are).
--- Every id must be a garment of its slot and owned. Returns true, or false and a reason ("unknown", "slot",
--- "locked"). Where `appliesNow` the outfit is also today's and "wardrobe.dressed" is emitted when it changed; otherwise
--- today's outfit changes at the next dawn. A manual Wear turns Auto off; the third result says it did.
function Wardrobe.wear(world, outfit)
  local w = store(world)
  local registry = world.registry
  local slots = cfg(world).slots
  local isSlot = {}
  for _, slot in ipairs(slots) do
    isSlot[slot] = true
  end
  for slot in pairs(outfit) do
    if not isSlot[slot] then
      return false, "slot"
    end
  end
  local nextWorn = Wardrobe.committed(world)
  for _, slot in ipairs(slots) do
    local id = outfit[slot]
    if id ~= nil then
      if not registry:has("garments", id) then
        return false, "unknown"
      end
      if registry:get("garments", id).slot ~= slot then
        return false, "slot"
      end
      if not Wardrobe.owned(world, id) then
        return false, "locked"
      end
      nextWorn[slot] = id
    end
  end
  w.worn = nextWorn
  local autoWasOn = w.auto
  w.auto = false
  if Wardrobe.appliesNow(world) then
    if world.state then
      snapshot(world, "wear")
    else
      world.events:emit("wardrobe.dressed", { dressed = copyOutfit(world, nextWorn), reason = "wear" })
    end
  end
  return true, nil, autoWasOn
end

--- The player has looked at this garment: its dot goes.
function Wardrobe.markSeen(world, id)
  store(world).fresh[id] = nil
end

--- The player opened the wardrobe: the decision stamp goes (the tile dots stay until each is seen).
function Wardrobe.stampSeen(world)
  store(world).stamp = false
end

--- Save an outfit under a preset name (`warm` or `cold`). Returns true, or false and a reason ("name",
--- "unknown", "slot", "locked").
function Wardrobe.savePreset(world, name, outfit)
  local w = store(world)
  local known = false
  for _, preset in ipairs(cfg(world).presets) do
    known = known or preset == name
  end
  if not known then
    return false, "name"
  end
  local saved = {}
  for _, slot in ipairs(cfg(world).slots) do
    local id = outfit[slot]
    if not world.registry:has("garments", id) then
      return false, "unknown"
    end
    if world.registry:get("garments", id).slot ~= slot then
      return false, "slot"
    end
    if not Wardrobe.owned(world, id) then
      return false, "locked"
    end
    saved[slot] = id
  end
  w.presets[name] = saved
  return true
end

--- Switch the dawn auto-dress on or off (the switching itself is the menu's later step).
function Wardrobe.setAuto(world, on)
  store(world).auto = on == true
end

-- Unlocks ----------------------------------------------------------------------------------------------------

local function own(world, id)
  local w = store(world)
  if w.owned[id] then
    return false
  end
  local run = runNumber(world)
  w.owned[id], w.fresh[id], w.stamp, w.earned[id] = true, true, true, run
  world.events:emit("wardrobe.unlocked", { id = id, run = run })
  return true
end

--- Give a garment as if it had been earned: owned, new, the stamp due, "wardrobe.unlocked" emitted. For
--- driver scenarios and the balance harness; a Sandbox slot owns everything already, so this does nothing
--- there. Returns true when the garment was newly owned.
function Wardrobe.grant(world, id)
  assert(world.registry:has("garments", id), "no garment " .. tostring(id))
  if Sandbox.on(world) then
    return false
  end
  return own(world, id)
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- What an unlock counts, as a number.
local function measure(world, unlock)
  local meta = world.meta
  local counts = store(world).counts
  local kind = unlock.kind
  if kind == "season" then
    return counts.seasons[unlock.season] or 0
  elseif kind == "crops" then
    return countKeys(counts.crops)
  elseif kind == "fish" then
    return countKeys(meta.fishGuide or {})
  elseif kind == "built" then
    return counts.built[unlock.object] and 1 or 0
  elseif kind == "builtField" then
    for id in pairs(counts.built) do
      if world.registry:has("objects", id) and world.registry:get("objects", id)[unlock.field] then
        return 1
      end
    end
    return 0
  elseif kind == "cleared" then
    return counts.cleared[unlock.object] or 0
  elseif kind == "rescues" then
    return meta.career and #meta.career.history or 0
  elseif kind == "runs" then
    return runNumber(world)
  elseif kind == "established" then
    return meta.established and 1 or 0
  end
  return counts[kind] or 0 -- winters, snowDays, snaps, frosts, harvests, trips, machines
end

--- The threshold of a counting unlock (tuning.wardrobe.unlocks), or nil for one that is a yes or no.
function Wardrobe.threshold(world, id)
  return rawget(cfg(world).unlocks, id)
end

--- How far along an unlock is: `have, need` (need is 1 for a yes or no). nil for a starter.
function Wardrobe.progress(world, id)
  local def = world.registry:get("garments", id)
  if not def.unlock then
    return nil
  end
  return measure(world, def.unlock), Wardrobe.threshold(world, id) or 1
end

--- Check every locked garment against what the slot has done, and own the ones that are earned. Called at
--- every dawn, at the end of a run and at the start of one. Returns the ids newly owned. Does nothing in a
--- Sandbox slot.
function Wardrobe.evaluate(world)
  if Sandbox.on(world) then
    return {}
  end
  local w = store(world)
  if world.state and world.state.grid then
    -- Machines standing at once: the peak over the dawns (picking one up and putting it down counts once).
    w.counts.machines = math.max(w.counts.machines, #Grid.anchorsWith(world, "machine"))
  end
  local earned = {}
  for _, def in ipairs(world.registry:all("garments")) do
    if def.unlock and not w.owned[def.id] then
      local have, need = Wardrobe.progress(world, def.id)
      if have >= need and own(world, def.id) then
        earned[#earned + 1] = def.id
      end
    end
  end
  return earned
end

-- System hooks --------------------------------------------------------------------------------------------------

local function isFrozenSeason(world, season)
  for _, s in ipairs(world.tuning.weather.frozenSeasons) do
    if s == season then
      return true
    end
  end
  return false
end

function Wardrobe.init(world)
  sanitize(world, store(world))
  local state = world.state
  if state.wardrobe then
    for _, slot in ipairs(cfg(world).slots) do
      state.wardrobe.dressed[slot] = garmentIn(world, slot, state.wardrobe.dressed[slot]).id
    end
  else
    state.wardrobe = { dressed = Wardrobe.committed(world) }
  end
  Wardrobe.evaluate(world) -- a run that starts counts too (the run number)

  local events = world.events
  -- Registered after needs, so the night's warmth (settled on the new day's first event) still uses the
  -- outfit worn through the day, and the new outfit starts with the day (D149).
  events:on("calendar.newDay", function()
    local counts = store(world).counts
    if isFrozenSeason(world, Calendar.now(world).season) then
      counts.snowDays = counts.snowDays + 1
    end
    snapshot(world, "dawn")
    Wardrobe.evaluate(world)
  end)
  events:on("calendar.newSeason", function(e)
    local seasons = world.tuning.time.seasons
    local at
    for i, season in ipairs(seasons) do
      if season == e.season then
        at = i
      end
    end
    local ended = seasons[(at - 2) % #seasons + 1]
    local counts = store(world).counts
    counts.seasons[ended] = (counts.seasons[ended] or 0) + 1
    if isFrozenSeason(world, ended) then
      counts.winters = counts.winters + 1
    end
  end)
  events:on("weather.froze", function()
    local counts = store(world).counts
    counts.frosts = counts.frosts + 1
  end)
  events:on("weather.coldSnap", function(e)
    if not e.active then
      local counts = store(world).counts
      counts.snaps = counts.snaps + 1
    end
  end)
  events:on("crop.harvested", function(e)
    local counts = store(world).counts
    counts.harvests = counts.harvests + 1
    if e.crop then
      counts.crops[e.crop] = true
    end
  end)
  events:on("market.trip", function()
    local counts = store(world).counts
    counts.trips = counts.trips + 1
  end)
  events:on("object.placed", function(e)
    if e.object then
      store(world).counts.built[e.object] = true
    end
  end)
  events:on("object.cleared", function(e)
    local cleared = store(world).counts.cleared
    if e.object then
      cleared[e.object] = (cleared[e.object] or 0) + 1
    end
  end)
end

return Wardrobe
