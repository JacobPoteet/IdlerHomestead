-- Machines (GDD §7.4, D14, D65): stationary actors on the task board.
--
-- A placed object with a `machine` definition { categories, tasks?, radius, workSpeed } becomes a
-- machine unit. Like the homesteader it claims tasks through the task board's reservations (so a
-- machine and the homesteader never work the same target), but it does not walk: it claims the
-- nearest doable target of its capability set within `radius` tiles of where it stands
-- (Tasks.chooseAreaJob) and works it in place at `workSpeed`.
--
-- Power: a machine's `sink` uses the "demand" schedule. While it has work it asks for power
-- (Power.request) and the network serves it in its tier ("machines", D46) from the next tick; it
-- works at workSpeed x the sink's satisfaction ratio, and below tuning.machines.minPowerRatio it
-- stops, gives up its claim (so the homesteader can take the job) and reports "unpowered". With
-- nothing to do it asks for nothing, so an idle machine draws no power. A machine without a `sink`
-- runs at full speed.
--
-- Storage: the task's own canDo is checked every tick of the job, so a full store (D59) drops the
-- job and leaves the crop in the ground; when that is all there is to do the machine reports "full".
--
-- State: world.state.machines = { units = { [anchor] = unit }, done = completions (lifetime) }
--   unit = { id ("machine:<anchor>", the reservation holder), kind (object id), x, y (its tile),
--            bucket (always 0: task code may read it), job (a task-board job or nil), status,
--            full (resource id while held back by storage), wait (seconds to the next search),
--            done (completions), warnedDay (last day "machine.unpowered" was emitted) }
--   status: "off" (switched off), "idle" (nothing in reach), "full" (work held back by storage),
--           "starting" (asked for power this tick), "unpowered" (below minPowerRatio), "slow"
--           (partly powered), "working".
-- Emits "task.completed" { task, target, actor = unit id, ordered = false, machine = kind } like a
-- walking actor, and "machine.unpowered" { anchor, kind } at most once a day per machine.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Power = require("src.sim.systems.power")
local Tasks = require("src.sim.systems.tasks")

local Machines = {}

local function state(world)
  return world.state.machines
end

local function defAt(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id)
end

local function newUnit(world, anchor, kind)
  local x, y = Grid.coords(world.state.grid, anchor)
  return { id = "machine:" .. anchor, kind = kind, x = x, y = y, bucket = 0, status = "idle", wait = 0, done = 0 }
end

local function dropJob(world, unit)
  if unit.job then
    Tasks.release(world, unit.job)
    unit.job = nil
  end
end

-- Keep one unit per placed machine: new machines get a unit, removed or replaced ones lose theirs
-- (and their claim and power request).
local function sync(world)
  local s = state(world)
  local objects = world.state.grid.objects
  local placed = {}
  for _, anchor in ipairs(Grid.anchorsWith(world, "machine")) do
    placed[anchor] = true
    local unit = s.units[anchor]
    if not unit or unit.kind ~= objects[anchor].id then
      if unit then
        dropJob(world, unit)
      end
      s.units[anchor] = newUnit(world, anchor, objects[anchor].id)
    end
  end
  local gone = {}
  for anchor in pairs(s.units) do
    if not placed[anchor] then
      gone[#gone + 1] = anchor
    end
  end
  table.sort(gone)
  for _, anchor in ipairs(gone) do
    dropJob(world, s.units[anchor])
    s.units[anchor] = nil
    Power.request(world, anchor, false)
  end
end

function Machines.init(world)
  local s = world.state.machines or {}
  world.state.machines = s
  -- Saves from before machines existed have no table; fill in the fields.
  s.units = s.units or {}
  s.done = s.done or 0
  sync(world)
  world.events:on("object.placed", function()
    sync(world) -- a new machine has a unit (and a card) at once, not only from the next tick
  end)
  local anchors = {}
  for anchor in pairs(s.units) do
    anchors[#anchors + 1] = anchor
  end
  table.sort(anchors)
  for _, anchor in ipairs(anchors) do
    local unit = s.units[anchor]
    if unit.job then
      Tasks.reserve(world, unit, unit.job) -- reservations are runtime; rebuild this machine's claim
    end
  end
end

-- Accessors ---------------------------------------------------------------------------------------

--- The unit of the machine anchored at `anchor`, or nil. Read-only.
function Machines.at(world, anchor)
  return state(world).units[anchor]
end

--- Every machine unit, in anchor order (read-only records).
function Machines.list(world)
  local list = {}
  for _, anchor in ipairs(Grid.anchorsWith(world, "machine")) do
    local unit = state(world).units[anchor]
    if unit then
      list[#list + 1] = unit
    end
  end
  return list
end

--- Tasks completed by machines this run.
function Machines.done(world)
  return state(world).done
end

--- Tiles a machine at `anchor` reaches (ascending indices inside the map), for the zone overlay.
function Machines.areaTiles(world, anchor)
  local grid = world.state.grid
  local ax, ay = Grid.coords(grid, anchor)
  local r = defAt(world, anchor).machine.radius
  local tiles = {}
  for y = ay - r, ay + r do
    for x = ax - r, ax + r do
      if Grid.inBounds(grid, x, y) then
        tiles[#tiles + 1] = Grid.index(grid, x, y)
      end
    end
  end
  return tiles
end

--- Progress of a machine's current job, for the UI: { task, target, fraction, duration } or nil.
function Machines.progress(world, unit)
  local job = unit.job
  if not job then
    return nil
  end
  local duration = Tasks.get(world, job.task).workTime(world, unit, job.target)
  if duration <= 0 then
    return nil
  end
  return { task = job.task, target = job.target, fraction = math.min(1, job.progress / duration), duration = duration }
end

--- Facts for the object card: { status, full, done, radius, workSpeed, draw, ratio, target }.
function Machines.info(world, anchor)
  local unit = state(world).units[anchor]
  local def = defAt(world, anchor)
  return {
    status = unit and unit.status or "idle",
    full = unit and unit.full,
    done = unit and unit.done or 0,
    radius = def.machine.radius,
    workSpeed = def.machine.workSpeed,
    draw = def.sink and def.sink.draw or 0,
    ratio = def.sink and Power.sinkRatio(world, anchor) or 1,
    target = unit and unit.job and unit.job.target,
  }
end

-- The tick ----------------------------------------------------------------------------------------

-- Power share this machine gets, and whether it is waiting for its first answer from the network.
local function powerFor(world, anchor, def)
  if not def.sink then
    return 1, false
  end
  Power.request(world, anchor, true)
  if Power.sinkState(world, anchor) == "idle" then
    return 0, true -- asked this tick; the network serves it from the next one
  end
  return Power.sinkRatio(world, anchor), false
end

local function tickUnit(world, anchor, unit, dt)
  local def = defAt(world, anchor)
  local spec, cfg = def.machine, world.tuning.machines
  if def.sink and not Power.isEnabled(world, anchor) then
    dropJob(world, unit)
    Power.request(world, anchor, false)
    unit.status, unit.full = "off", nil
    return
  end

  -- A held job stays only while this machine still holds the claim (a player order may have taken
  -- the tile) and the task can still be done (the crop is there, its store has room).
  local job = unit.job
  if job then
    local taskType = Tasks.get(world, job.task)
    if Tasks.holder(world, job.task, job.target) ~= unit.id or not taskType.canDo(world, unit, job.target, nil) then
      dropJob(world, unit)
      job = nil
    end
  end

  if not job then
    if unit.wait > 0 then
      unit.wait = unit.wait - dt
      return -- keep the last status and power request until the next search
    end
    local full
    job, full = Tasks.chooseAreaJob(world, unit, spec, { center = anchor, radius = spec.radius })
    if not job then
      if def.sink then
        Power.request(world, anchor, false)
      end
      unit.status, unit.full, unit.wait = full and "full" or "idle", full, cfg.recheckInterval
      return
    end
  end
  unit.full = nil

  local ratio, starting = powerFor(world, anchor, def)
  if starting then
    unit.status = "starting"
    return
  end
  if ratio < cfg.minPowerRatio then
    -- Too little power: stop and let the homesteader have the job; keep asking for power.
    dropJob(world, unit)
    unit.status, unit.wait = "unpowered", cfg.recheckInterval
    local day = Calendar.now(world).day
    if unit.warnedDay ~= day then
      unit.warnedDay = day
      world.events:emit("machine.unpowered", { anchor = anchor, kind = unit.kind })
    end
    return
  end

  if not unit.job then
    unit.job = job
    Tasks.reserve(world, unit, job)
  end
  unit.status = ratio < 1 - world.tuning.power.overdrawEpsilon and "slow" or "working"
  local taskType = Tasks.get(world, job.task)
  job.progress = job.progress + dt * spec.workSpeed * ratio
  if job.progress >= taskType.workTime(world, unit, job.target) then
    local target = job.target
    dropJob(world, unit)
    taskType.complete(world, unit, target, nil)
    unit.done = unit.done + 1
    state(world).done = state(world).done + 1
    world.events:emit("task.completed", { task = taskType.id, target = target, actor = unit.id, ordered = false, machine = unit.kind })
  end
end

function Machines.tick(world, dt)
  sync(world)
  local units = state(world).units
  for _, anchor in ipairs(Grid.anchorsWith(world, "machine")) do
    tickUnit(world, anchor, units[anchor], dt)
  end
end

return Machines
