-- Compost and the manure loop (PLAN_DEPTH 8.4, D181, D185): residue, spoiled food and animal manure become compost.
--
-- The loop, end to end:
--   1. Hens and goats make muck in their house every game day (`state.compost.muck`, capped; a house with no
--      animals makes none). The Tend chores (animals.lua) call `Compost.rake`, which moves the whole units into the
--      ledger as "manure", but only while a compost bin exists.
--   2. A bin draws the ledger's manure straight in each tick (no haul task, D185), as far as it has room, and also
--      takes crop residue (each harvest) and spoiled food (a share of every "food.spoiled" unit, so spoilage losses,
--      #169, are partly recovered) on its own. The bin with the most room takes it, ties to the lower anchor; what no
--      bin has room for is lost (manure stays in the ledger).
--   3. A bin with `startAt` raw units starts a batch like a processing station: up to `batchRaw` raw units go in,
--      `yield` of them come out as compost after `hours` in-game hours, into the ledger "compost" stock. A batch the
--      ledger has no room for waits in the bin, keeping it busy (D59).
--   4. The `fertilize` task spreads one ledger compost unit on a field tile through Soil.add. The idle routine does it
--      for the single lowest-fertility worn tile (D185); a player tap does it on any tile under `fertilizeMax`.
--
-- State: world.state.compost = { muck = { hens, goats } (units, fractional), bins = { [anchor] = { raw (units),
--   batch = { count, remaining } | nil } }, made, spread (lifetime units) }
-- Emits "compost.fed" { tile, amount, cause } (cause "manure" | "residue" | "spoiled"), "compost.started" { tile, raw,
-- count }, "compost.done" { tile, count } (units that went into stock), "compost.blocked" { tile, count },
-- "compost.spread" { tile, from, to }.

local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Soil = require("src.sim.systems.soil")
local Tasks = require("src.sim.systems.tasks")

local Compost = {}

local MANURE, COMPOST = "manure", "compost"
local EPS = 1e-6 -- float slack for raw units built from fractional shares (not a balance value)

local function state(world)
  return world.state.compost
end

local function binDef(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id).compost
end

local function bins(world)
  return Grid.anchorsWith(world, "compost")
end

-- The state of the bin at `anchor`, made when first needed.
local function binAt(world, anchor)
  local list = state(world).bins
  list[anchor] = list[anchor] or { raw = 0 }
  return list[anchor]
end

--- Is any compost bin placed?
function Compost.hasBin(world)
  return #bins(world) > 0
end

--- Raw units the bin at `anchor` holds.
function Compost.raw(world, anchor)
  local bin = state(world).bins[anchor]
  return bin and bin.raw or 0
end

--- Raw units the bin at `anchor` still has room for.
function Compost.room(world, anchor)
  return math.max(0, binDef(world, anchor).raw - Compost.raw(world, anchor))
end

--- Raw units all bins can still take.
function Compost.totalRoom(world)
  local room = 0
  for _, anchor in ipairs(bins(world)) do
    room = room + Compost.room(world, anchor)
  end
  return room
end

--- The batch running or waiting in the bin at `anchor`, or nil.
function Compost.batch(world, anchor)
  local bin = state(world).bins[anchor]
  return bin and bin.batch or nil
end

--- Muck waiting in a house: kind "hens" or "goats".
function Compost.muck(world, kind)
  return state(world).muck[kind]
end

--- Put up to `amount` raw units into the bins (the one with the most room first, ties to the lower anchor).
--- Returns the units that fitted. Emits "compost.fed" for each bin that took some.
function Compost.feed(world, amount, cause)
  local left = amount
  while left > EPS do
    local best, bestRoom
    for _, anchor in ipairs(bins(world)) do
      local room = Compost.room(world, anchor)
      if room > EPS and (bestRoom == nil or room > bestRoom + EPS) then
        best, bestRoom = anchor, room
      end
    end
    if not best then
      break
    end
    local put = math.min(left, bestRoom)
    binAt(world, best).raw = binAt(world, best).raw + put
    left = left - put
    world.events:emit("compost.fed", { tile = best, amount = put, cause = cause })
  end
  return amount - left
end

--- Rake the whole units of muck out of a house ("hens" or "goats") into the ledger as manure, as far as the
--- ledger has room. Only while a bin exists to use it. Returns the units raked.
function Compost.rake(world, kind)
  if not Compost.hasBin(world) then
    return 0
  end
  local s = state(world)
  local units = math.min(math.floor(s.muck[kind] + EPS), math.floor(Ledger.room(world, MANURE)))
  if units <= 0 then
    return 0
  end
  Ledger.add(world, MANURE, units, "raked")
  s.muck[kind] = s.muck[kind] - units
  return units
end

--- Could a compost unit be spread on tile i right now by a player tap (the tile is farmed, under
--- `fertilizeMax`, and there is compost)?
function Compost.canSpread(world, i, routine)
  local cfg = world.tuning.compost
  if Ledger.get(world, COMPOST) < 1 or not Crops.tileInUse(world, i) or Crops.isHeld(world, i) then
    return false
  end
  local fertility = Soil.fertility(world, i)
  return fertility < (routine and cfg.fertilizeBelow or cfg.fertilizeMax)
end

--- Spread one compost unit on tile i. Returns the new fertility, or nil when there was nothing to spread.
function Compost.spread(world, i)
  if not Ledger.remove(world, COMPOST, 1, "spread") then
    return nil
  end
  local from = Soil.fertility(world, i)
  local to = Soil.add(world, i, world.tuning.compost.compostFertility, "compost")
  state(world).spread = state(world).spread + 1
  world.events:emit("compost.spread", { tile = i, from = from, to = to })
  return to
end

--- Facts for the tile card of the bin at `anchor`: { raw, cap, batch = { count, hoursLeft, blocked } | nil }.
function Compost.info(world, anchor)
  local batch = Compost.batch(world, anchor)
  local out = { raw = Compost.raw(world, anchor), cap = binDef(world, anchor).raw }
  if batch then
    out.batch = {
      count = batch.count,
      hoursLeft = batch.remaining / (world.tuning.time.dayLength / 24),
      blocked = batch.blocked == true,
    }
  end
  return out
end

--- Drop the bin state at `anchor` (the bin was destroyed or picked up): its contents are lost.
function Compost.scrap(world, anchor)
  state(world).bins[anchor] = nil
end

--- Carry the bin state of the bin at `from` to where it now stands, `to` (it was moved).
function Compost.relocate(world, from, to)
  local list = state(world).bins
  list[to], list[from] = list[from], nil
end

-- The daily muck of the animals (a house with none makes none), capped per house.
local function makeMuck(world)
  local cfg, s = world.tuning.compost, state(world)
  s.muck.hens = math.min(cfg.muckCap, s.muck.hens + Ledger.get(world, "hen") * cfg.henMuck)
  s.muck.goats = math.min(cfg.muckCap, s.muck.goats + Ledger.get(world, "goat") * cfg.goatMuck)
end

local function registerTasks(world)
  Tasks.register(world, {
    id = "fertilize",
    category = "maintenance",
    verb = "Fertilize",
    clickOrder = 55,
    candidates = function(w, _, add)
      if Ledger.get(w, COMPOST) < 1 then
        return
      end
      -- one candidate: the lowest-fertility worn tile, ties to the lower index (D185); the worn list is ascending
      local lowest, lowestFertility
      for _, i in ipairs(Soil.worn(w, w.tuning.compost.fertilizeBelow)) do
        local fertility = Soil.fertility(w, i)
        if Compost.canSpread(w, i, true) and (lowest == nil or fertility < lowestFertility) then
          lowest, lowestFertility = i, fertility
        end
      end
      if lowest then
        add(lowest)
      end
    end,
    canDo = function(w, _, i, order)
      return Compost.canSpread(w, i, order == nil)
    end,
    workTime = function(w)
      return w.tuning.compost.fertilizeTime
    end,
    complete = function(w, _, i)
      Compost.spread(w, i)
    end,
  })
end

function Compost.init(world)
  local s = world.state.compost or {}
  world.state.compost = s
  s.muck = s.muck or { hens = 0, goats = 0 }
  s.bins = s.bins or {}
  s.made = s.made or 0
  s.spread = s.spread or 0
  registerTasks(world)
  world.events:on("calendar.newDay", function()
    makeMuck(world)
  end)
  world.events:on("crop.harvested", function()
    Compost.feed(world, world.tuning.compost.residuePerHarvest, "residue")
  end)
  world.events:on("food.spoiled", function(e)
    Compost.feed(world, e.amount * world.tuning.compost.spoilShare, "spoiled")
  end)
end

-- One bin's step: start a batch from enough raw material, or run the one it has and deliver it.
local function stepBin(world, anchor, bin, dt)
  local cfg = world.tuning.compost
  local batch = bin.batch
  if not batch then
    local take = math.min(math.floor(bin.raw + EPS), cfg.batchRaw)
    if bin.raw >= cfg.startAt - EPS and take > 0 then
      local count = math.max(1, math.floor(take * cfg.yield + EPS))
      bin.raw = bin.raw - take
      bin.batch = { count = count, remaining = cfg.hours * world.tuning.time.dayLength / 24 }
      world.events:emit("compost.started", { tile = anchor, raw = take, count = count })
    end
    return
  end
  batch.remaining = math.max(0, batch.remaining - dt)
  if batch.remaining > 0 then
    return
  end
  -- Whatever fits goes into stock; the rest waits in the bin (and keeps it busy) until there is room.
  local moved = Ledger.add(world, COMPOST, batch.count, "composted")
  batch.count = batch.count - moved
  if moved > 0 then
    state(world).made = state(world).made + moved
    world.events:emit("compost.done", { tile = anchor, count = moved })
  end
  if batch.count <= 0 then
    bin.batch = nil
  elseif not batch.blocked then
    batch.blocked = true
    world.events:emit("compost.blocked", { tile = anchor, count = batch.count })
  end
end

-- The bins draw the ledger's manure in, whole units, as far as their combined room goes (D185).
local function drawManure(world)
  local units = math.min(math.floor(Ledger.get(world, MANURE)), math.floor(Compost.totalRoom(world) + EPS))
  if units > 0 and Ledger.remove(world, MANURE, units, "composted") then
    Compost.feed(world, units, "manure")
  end
end

function Compost.tick(world, dt)
  if Compost.hasBin(world) then
    drawManure(world)
  end
  local list = state(world).bins
  for _, anchor in ipairs(bins(world)) do
    local bin = list[anchor]
    if bin then
      stepBin(world, anchor, bin, dt)
    end
  end
end

return Compost
