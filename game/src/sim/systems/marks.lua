-- Area marks (GDD §9.4, D138, D147, #299): the Axe and the Pail mark a dragged area as orders on the task board.
-- A mark is a standing order like a planned field tile (D92): the hand and the routine both work through it, with
-- the same costs, energy, skill and room checks as the single-tile task, in any control mode.
--
--   clear marks  tile index of the anchor of an object the Axe can clear (a tree, bush, stump, rock ...)
--   water marks  tile index of a crop that is dry
--
-- The marks add three task types that only borrow the single-tile tasks' rules: "clear_marked" (clear.canDo,
-- room check, axe speed and yields), "water_marked" (water_crop), and "fetch_marked", which refills an empty
-- bucket while a watering mark waits, so a marked area gets watered in any control mode. Doing a mark removes it.
-- A mark whose object or thirsty crop is gone (cleared by a plan, rained on, harvested) drops away on the next tick.
--
-- State: world.state.marks = { clear = { [anchor] = true }, water = { [tile] = true } }.

local Clearing = require("src.sim.systems.clearing")
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Tasks = require("src.sim.systems.tasks")

local Marks = {}

Marks.KINDS = { "clear", "water" }

local function state(world)
  return world.state.marks
end

--- The tile a mark of `kind` would sit on for tile i, or nil when nothing there can take that mark: the anchor
--- of a clearable object (clear) or the tile of a dry crop (water). The same things a tap with the tool works.
function Marks.target(world, kind, i)
  if kind == "clear" then
    return Clearing.clearableAt(world, i)
  end
  return Crops.needsWaterAt(world, i) and i or nil
end

--- Does tile i hold a mark of `kind`?
function Marks.has(world, kind, i)
  local target = kind == "clear" and select(2, Grid.object(world, i)) or i
  return target ~= nil and state(world)[kind][target] == true
end

--- The kind of mark on tile i ("clear" or "water"), or nil.
function Marks.kindAt(world, i)
  for _, kind in ipairs(Marks.KINDS) do
    if Marks.has(world, kind, i) then
      return kind
    end
  end
  return nil
end

--- Mark every tile in `tiles` (an array of tile indexes) that can take a `kind` mark. Returns how many marks were
--- added (a tile already marked adds none).
function Marks.add(world, kind, tiles)
  local set, added = state(world)[kind], 0
  for _, i in ipairs(tiles) do
    local target = Marks.target(world, kind, i)
    if target and not set[target] then
      set[target] = true
      added = added + 1
    end
  end
  return added
end

--- Cancel the `kind` marks on `tiles`. Returns how many were cancelled.
function Marks.remove(world, kind, tiles)
  local set, removed = state(world)[kind], 0
  for _, i in ipairs(tiles) do
    local target = kind == "clear" and select(2, Grid.object(world, i)) or i
    if target and set[target] then
      set[target] = nil
      removed = removed + 1
    end
  end
  return removed
end

--- Cancel every mark (a new run, or a test).
function Marks.clearAll(world)
  local s = state(world)
  s.clear, s.water = {}, {}
end

--- The marked tiles of `kind`, ascending (so every run walks them in the same order).
function Marks.list(world, kind)
  local out = {}
  for i in pairs(state(world)[kind]) do
    out[#out + 1] = i
  end
  table.sort(out)
  return out
end

--- How many marks of `kind` stand.
function Marks.count(world, kind)
  local n = 0
  for _ in pairs(state(world)[kind]) do
    n = n + 1
  end
  return n
end

-- A mark is still worth working while its target exists.
local function alive(world, kind, i)
  if kind == "clear" then
    local def, anchor = Grid.object(world, i)
    return def ~= nil and anchor == i and Clearing.clearableAt(world, i) ~= nil
  end
  return Crops.needsWaterAt(world, i)
end

--- Drop the marks whose target is gone.
function Marks.prune(world)
  for _, kind in ipairs(Marks.KINDS) do
    local set = state(world)[kind]
    local stale
    for i in pairs(set) do
      if not alive(world, kind, i) then
        stale = stale or {}
        stale[#stale + 1] = i
      end
    end
    for _, i in ipairs(stale or {}) do
      set[i] = nil
    end
  end
end

local function eachMark(world, kind, add)
  for i in pairs(state(world)[kind]) do
    add(i)
  end
end

function Marks.init(world)
  local s = world.state.marks or {}
  world.state.marks = s
  s.clear = s.clear or {}
  s.water = s.water or {}

  local clear = Tasks.get(world, "clear")
  Tasks.register(world, {
    id = "clear_marked",
    category = "clear",
    verb = "Clear",
    standing = true, -- a marked object is the player's own order (D92)
    candidates = function(w, _, add)
      eachMark(w, "clear", add)
    end,
    canDo = function(w, actor, i)
      return Marks.has(w, "clear", i) and clear.canDo(w, actor, i)
    end,
    blocked = function(w, actor, i)
      return Marks.has(w, "clear", i) and clear.blocked(w, actor, i) or nil
    end,
    workTime = clear.workTime,
    complete = function(w, actor, i)
      clear.complete(w, actor, i)
      state(w).clear[i] = nil
    end,
  })

  local water = Tasks.get(world, "water_crop")
  Tasks.register(world, {
    id = "water_marked",
    category = "water",
    verb = "Water",
    standing = true,
    candidates = function(w, _, add)
      eachMark(w, "water", add)
    end,
    canDo = function(w, actor, i)
      return Marks.has(w, "water", i) and water.canDo(w, actor, i)
    end,
    workTime = water.workTime,
    complete = function(w, actor, i)
      water.complete(w, actor, i)
      state(w).water[i] = nil
    end,
  })

  -- Refill the bucket for the marks: the single-tile fetch (same creek, wells, cisterns and ice), but standing, and
  -- only while a watering mark waits, so the hand's marked rows are watered without the routine.
  local fetch = Tasks.get(world, "fetch_water")
  Tasks.register(world, {
    id = "fetch_marked",
    category = "water",
    verb = fetch.verb,
    standing = true,
    candidates = function(w, actor, add)
      if next(state(w).water) ~= nil then
        fetch.candidates(w, actor, add)
      end
    end,
    canDo = fetch.canDo,
    canDoCandidate = fetch.canDoCandidate,
    workTime = fetch.workTime,
    complete = fetch.complete,
  })
end

function Marks.tick(world)
  Marks.prune(world)
end

return Marks
