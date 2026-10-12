-- Finds (GDD §8.4, D53): occasional "pick 1 of 3" roguelike offers.
--
-- Once a day, at tuning.finds.rollHour, a roll (own seeded RNG stream "finds") may queue an offer
-- (`due`), unless the cooldown since the last pick has not passed or it is too early in the run.
-- A queued offer waits until the homesteader is not busy (resting, or doing a job listed in
-- tuning.finds.busyJobs), then becomes the pending offer: three distinct finds drawn by weight
-- (content `weight`, season and lack multipliers; finds outside their years or already pointless
-- are not eligible). The UI shows the pending offer; Finds.choose applies the pick's effects
-- through the ledger, inventory and power systems and the other options are gone.
-- Time only matters while the sim ticks, so a paused game never rolls or offers; a pending offer
-- simply waits to be answered (and is saved with the run).
--
-- State: world.state.finds = { rollDay = day of the last roll, lastPick = day of the last pick or nil,
--   due = bool, pending = { day, choices = { findId, ... } } or nil, history = { { day, offered, picked }, ... } }
-- Emits "finds.offered" { day, choices } and "finds.picked" { day, find, offered }.

local Calendar = require("src.sim.systems.calendar")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")
local Sleep = require("src.sim.systems.sleep")
local Actors = require("src.sim.systems.actors")

local Finds = {}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

function Finds.init(world)
  local state = world.state
  state.finds = state.finds or {}
  local f = state.finds
  f.rollDay = f.rollDay or 0
  f.history = f.history or {}
  if f.due == nil then
    f.due = false
  end
end

--- The offer waiting for an answer: { day, choices = { findId, ... } }, or nil.
function Finds.pending(world)
  return world.state.finds.pending
end

--- Is an offer queued, waiting for a calm moment?
function Finds.isDue(world)
  return world.state.finds.due == true
end

--- The picks made this run, oldest first: { { day, offered = { ids }, picked = id }, ... }.
function Finds.history(world)
  return world.state.finds.history
end

--- Is the homesteader too busy for an offer (resting, or on one of tuning.finds.busyJobs)?
function Finds.isBusy(world)
  if Sleep.isBedtime(world) then
    return true
  end
  local actor = Actors.homesteader(world)
  if Sleep.resting(actor) then
    return true
  end
  if actor.job then
    for _, task in ipairs(world.tuning.finds.busyJobs) do
      if actor.job.task == task then
        return true
      end
    end
  end
  return false
end

-- Does the "lacks" condition of a find hold right now?
local function lacking(world, lacks)
  if not lacks then
    return false
  end
  if lacks.resource then
    return Ledger.get(world, lacks.resource) < lacks.below
  elseif lacks.object then
    if Inventory.objectCount(world, lacks.object) > 0 then
      return false
    end
    for _, obj in pairs(world.state.grid.objects) do
      if obj.id == lacks.object then
        return false
      end
    end
    return true
  elseif lacks.equipment then
    return not Inventory.hasEquipment(world, lacks.equipment)
  end
  return false
end

-- Can this find be offered now (years, and not all of its equipment already owned)?
local function eligible(world, def, year)
  if (def.minYear and year < def.minYear) or (def.maxYear and year > def.maxYear) then
    return false
  end
  local equipment = def.effects.equipment
  if equipment then
    local owned = true
    for _, id in ipairs(equipment) do
      owned = owned and Inventory.hasEquipment(world, id)
    end
    if owned then
      return false
    end
  end
  return true
end

--- The selection weight of a find right now (0 when it cannot be offered).
function Finds.weight(world, id)
  local def = world.registry:get("finds", id)
  local now = Calendar.now(world)
  if not eligible(world, def, now.year) then
    return 0
  end
  local weight = def.weight or 1
  if def.seasons then
    weight = weight * (def.seasons[now.season] or 1)
  end
  if lacking(world, def.lacks) then
    weight = weight * world.tuning.finds.lackBoost
  end
  return weight
end

--- Draw `tuning.finds.choices` distinct finds by weight from the run's "finds" stream.
--- Returns an array of find ids (shorter if too few are eligible).
function Finds.draw(world)
  local pool = {}
  for _, def in ipairs(world.registry:all("finds")) do
    local weight = Finds.weight(world, def.id)
    if weight > 0 then
      pool[#pool + 1] = { id = def.id, weight = weight }
    end
  end
  local rng = world:rng("finds")
  local picked = {}
  for _ = 1, math.min(world.tuning.finds.choices, #pool) do
    local entry = rng:weighted(pool, function(e)
      return e.weight
    end)
    picked[#picked + 1] = entry.id
    for i, e in ipairs(pool) do
      if e == entry then
        table.remove(pool, i)
        break
      end
    end
  end
  return picked
end

--- Make an offer pending now (the daily roll and busy check normally do this). Does nothing
--- if one is already pending or nothing is eligible. Returns the pending offer or nil.
function Finds.offer(world)
  local f = world.state.finds
  if f.pending then
    return f.pending
  end
  local choices = Finds.draw(world)
  f.due = false
  if #choices == 0 then
    return nil
  end
  f.pending = { day = Calendar.now(world).day, choices = choices }
  world.events:emit("finds.offered", { day = f.pending.day, choices = choices })
  return f.pending
end

local function applyEffects(world, effects)
  local resources = effects.resources or {}
  for _, id in ipairs(sortedKeys(resources)) do
    Ledger.addOrOverflow(world, id, resources[id], "find")
  end
  local objects = effects.objects or {}
  for _, id in ipairs(sortedKeys(objects)) do
    Inventory.addObject(world, id, objects[id])
  end
  for _, id in ipairs(effects.equipment or {}) do
    Inventory.addEquipment(world, id)
  end
  if effects.truckCharge then
    Power.add(world, Land.truck(world), effects.truckCharge)
  end
end

--- Take one of the pending offer's finds; the others are gone. Returns true, or false + reason.
function Finds.choose(world, id)
  local f = world.state.finds
  local pending = f.pending
  if not pending then
    return false, "no offer"
  end
  local listed = false
  for _, choice in ipairs(pending.choices) do
    listed = listed or choice == id
  end
  if not listed then
    return false, "not offered"
  end
  local def = world.registry:get("finds", id)
  applyEffects(world, def.effects)
  local day = Calendar.now(world).day
  f.pending = nil
  f.lastPick = day
  f.history[#f.history + 1] = { day = day, offered = pending.choices, picked = id }
  while #f.history > world.tuning.finds.historyLimit do
    table.remove(f.history, 1)
  end
  world.events:emit("finds.picked", { day = day, find = id, offered = pending.choices })
  return true
end

function Finds.tick(world)
  local cfg = world.tuning.finds
  local f = world.state.finds
  local now = Calendar.now(world)
  if now.hour < cfg.rollHour then
    return
  end
  if f.rollDay < now.day then
    f.rollDay = now.day
    -- Always draw, so the stream does not depend on cooldowns or what is pending.
    local hit = world:rng("finds"):chance(cfg.chancePerDay)
    local cooled = f.lastPick == nil or now.day - f.lastPick >= cfg.cooldownDays
    if hit and cooled and now.day >= cfg.firstDay and not f.pending then
      f.due = true
    end
  end
  if f.due and not f.pending and not Finds.isBusy(world) then
    Finds.offer(world)
  end
end

return Finds
