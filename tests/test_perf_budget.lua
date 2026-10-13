-- Performance work (#19, #77, #132, #21; D103): the speed-ups must not change results (a shared walking
-- flood, a cached date, an allocation-free Stats.modifier, a reused power flow), the grid arrays must
-- round-trip through the compact save form exactly, and the sim must stay inside its allocation budget.
-- Counts allocations, never wall-clock, so it is not flaky.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Rng = require("src.core.rng")
local serialize = require("src.core.serialize")
local Gridpack = require("src.core.gridpack")
local Perf = require("src.core.perf")
local Save = require("src.core.save")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Pathfind = require("src.sim.pathfind")
local Power = require("src.sim.systems.power")
local Stats = require("src.sim.stats")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

-- Shared walking flood ----------------------------------------------------------------------------

-- What Pathfind.nearest was before the shared flood: a fresh Dijkstra per query through Pathfind.find.
local function reference(world, start, targets)
  local grid = world.state.grid
  local function targetFrom(i)
    if not Grid.walkable(world, i) then
      return nil
    end
    if targets[i] ~= nil then
      return i
    end
    local x, y = Grid.coords(grid, i)
    local best
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if Grid.inBounds(grid, nx, ny) then
          local n = Grid.index(grid, nx, ny)
          if targets[n] == false and (not best or n < best) then
            best = n
          end
        end
      end
    end
    return best
  end
  local found
  local path = Pathfind.find(world, start, function(i)
    found = targetFrom(i)
    return found ~= nil
  end, start, true)
  return path, found
end

local function randomTargets(rng, grid)
  local targets = {}
  for _ = 1, rng:int(1, 14) do
    targets[rng:int(1, grid.w * grid.h)] = rng:chance(0.5)
  end
  return targets
end

T.test("flood: queries on one shared flood match a fresh search each, paths and targets", function()
  for seed = 1, 4 do
    local world = newWorld(seed)
    local grid = world.state.grid
    local rng = Rng.new(900 + seed)
    for _ = 1, 6 do
      local start
      repeat
        start = rng:int(1, grid.w * grid.h)
      until Grid.walkable(world, start)
      local flood = Pathfind.flood(world, start)
      for query = 1, 6 do
        local targets = randomTargets(rng, grid)
        if query == 5 then
          targets = { [1] = true } -- usually unreachable or far: runs the flood dry
        end
        local wantPath, wantFound = reference(world, start, targets)
        local path, found = flood:nearest(targets)
        T.eq(found, wantFound, "seed " .. seed .. " query " .. query .. " target")
        T.same(path, wantPath, "seed " .. seed .. " query " .. query .. " path")
      end
    end
  end
end)

T.test("flood: Pathfind.nearest still answers, and a newer flood retires an older one", function()
  local world = newWorld(2)
  local grid = world.state.grid
  local start = Land.spawn(world)
  local target = Grid.index(grid, 5, 5)
  local path, found = Pathfind.nearest(world, start, { [target] = false })
  local wantPath, wantFound = reference(world, start, { [target] = false })
  T.eq(found, wantFound)
  T.same(path, wantPath)
  local old = Pathfind.flood(world, start)
  Pathfind.flood(world, start)
  T.errors(function()
    old:nearest({ [target] = false })
  end, "newer flood")
end)

-- Cached date -------------------------------------------------------------------------------------

T.test("calendar: the cached date equals a fresh one, and a snapshot never changes under its holder", function()
  local world = newWorld(1)
  local cal = world.state.calendar
  local held = Calendar.now(world)
  T.truthy(Calendar.now(world) == held, "the same table while the clock stands still")
  local before = serialize.encode(held)
  for _, elapsed in ipairs({ 1, 80, 3000, 9000, 70000, 5e5 }) do
    cal.elapsed = elapsed
    T.same(Calendar.now(world), Calendar.compute(world), "elapsed " .. elapsed)
  end
  T.eq(serialize.encode(held), before, "an earlier snapshot is not rewritten")
  -- A different calendar table (a loaded save) or different time tuning is not served stale.
  local other = newWorld(1)
  other.state.calendar.elapsed = 2e5
  T.same(Calendar.now(other), Calendar.compute(other))
  local saved = tun.time.daysPerSeason
  tun.time.daysPerSeason = saved + 3
  T.same(Calendar.now(world), Calendar.compute(world), "tuning changed")
  tun.time.daysPerSeason = saved
  T.same(Calendar.now(world), Calendar.compute(world))
end)

-- Stats.modifier ----------------------------------------------------------------------------------

-- The original, allocating version.
local function modifierReference(world, name)
  local total = 0
  for _, itemId in ipairs(Inventory.equipmentIds(world)) do
    local mods = world.registry:get("catalog", itemId).modifiers
    if mods and mods[name] then
      total = total + mods[name]
    end
  end
  local journal = world.meta.journal
  if journal then
    for _, perk in ipairs(world.registry:all("perks")) do
      if journal.known[perk.id] and perk.modifiers and perk.modifiers[name] then
        total = total + perk.modifiers[name]
      end
    end
  end
  return total
end

T.test("stats: Stats.modifier gives the original sums exactly, for any equipment and perks", function()
  local world = newWorld(1)
  local equipment, perks = {}, {}
  for _, item in ipairs(reg:all("catalog")) do
    if item.equipment then
      equipment[#equipment + 1] = item.id
    end
  end
  for _, perk in ipairs(reg:all("perks")) do
    perks[#perks + 1] = perk.id
  end
  local names = {}
  for _, item in ipairs(reg:all("catalog")) do
    for name in pairs(item.modifiers or {}) do
      names[name] = true
    end
  end
  for _, perk in ipairs(reg:all("perks")) do
    for name in pairs(perk.modifiers or {}) do
      names[name] = true
    end
  end
  T.truthy(next(names) ~= nil, "content has stat modifiers to compare")
  local rng = Rng.new(5)
  world.meta.journal = world.meta.journal or { known = {} }
  for _ = 1, 40 do
    world.state.inventory.equipment = {}
    for _, id in ipairs(equipment) do
      world.state.inventory.equipment[id] = rng:chance(0.5) or nil
    end
    world.meta.journal.known = {}
    for _, id in ipairs(perks) do
      world.meta.journal.known[id] = rng:chance(0.5) or nil
    end
    for name in pairs(names) do
      T.eq(Stats.modifier(world, name), modifierReference(world, name), name)
    end
    T.eq(Stats.modifier(world, "noSuchStat"), 0)
  end
end)

-- Power flow reuse --------------------------------------------------------------------------------

T.test("power: the flow is reused tick to tick, and forgets sinks that were picked up", function()
  local world = newWorld(1)
  for _ = 1, 5 do
    world:tick(STEP)
  end
  local flow = Power.flow(world)
  local sinks = Grid.anchorsWith(world, "sink")
  -- Fake one sink entry from a vanished object: the next solve must drop it.
  flow.sinks[999999] = { demand = 1, ratio = 1 }
  flow.tiers.ghost = { demand = 1, served = 1, charging = 0 }
  world:tick(STEP)
  T.truthy(Power.flow(world) == flow, "the same table, refilled")
  T.eq(flow.sinks[999999], nil)
  T.eq(flow.tiers.ghost, nil)
  for _, anchor in ipairs(sinks) do
    T.truthy(flow.sinks[anchor] ~= nil, "a placed sink has an entry")
  end
  -- A save keeps the flow, and a loaded one carries on from it.
  local copy = serialize.decode(serialize.encode(world.state))
  local loaded = World.new({ registry = reg, tuning = tun }, copy)
  loaded:tick(STEP)
  world:tick(STEP)
  T.eq(serialize.encode(loaded.state.power), serialize.encode(world.state.power))
end)

-- Compact grid arrays -----------------------------------------------------------------------------

local function roundTrip(grid)
  local packed = Gridpack.pack(grid)
  local back = serialize.decode(serialize.encode(packed))
  Gridpack.unpack(back)
  return back, packed
end

T.test("gridpack: random maps round-trip exactly, small and large", function()
  local rng = Rng.new(77)
  local ids = { "grass", "water", "dirt", "tilled", "road", "sand", "mud", "rock", "snow", "ice" }
  for _, size in ipairs({ { 1, 1 }, { 7, 5 }, { 64, 48 }, { 200, 150 }, { 512, 400 } }) do
    local w, h = size[1], size[2]
    local grid = { w = w, h = h, terrain = {}, soil = {}, waterTable = {}, objects = { [3] = { id = "tree" } } }
    local current = ids[1]
    for i = 1, w * h do
      if rng:chance(0.08) then
        current = ids[rng:int(1, #ids)]
      end
      grid.terrain[i] = current
      grid.soil[i] = math.floor(math.max(0, math.min(1, rng:float())) * 100 + 0.5) / 100
      grid.waterTable[i] = rng:chance(0.6) and 0 or math.floor(rng:float() * 100 + 0.5) / 100
    end
    local back, packed = roundTrip(grid)
    T.eq(type(packed.terrain), "string", w .. "x" .. h .. " terrain is packed")
    T.eq(type(packed.soil), "string")
    T.same(back.terrain, grid.terrain, w .. "x" .. h .. " terrain")
    T.same(back.soil, grid.soil, w .. "x" .. h .. " soil")
    T.same(back.waterTable, grid.waterTable, w .. "x" .. h .. " waterTable")
    T.same(back.objects, grid.objects)
    T.eq(back.w, w)
    for i = 1, w * h do
      T.eq(back.soil[i], grid.soil[i]) -- bitwise-equal doubles, not just close
    end
    T.eq(#back.terrain, w * h)
    T.truthy(type(grid.terrain) == "table" and #grid.terrain == w * h, "the live grid is untouched")
    if w * h >= 300 then
      T.truthy(#serialize.encode(packed) < #serialize.encode(grid) / 2, w .. "x" .. h .. " is much smaller packed")
    end
  end
end)

T.test("gridpack: anything it cannot pack exactly stays a plain array", function()
  local cases = {
    { terrain = { "grass", "wa,ter" }, soil = { 0.5, 0.25 } }, -- a comma in an id (soil here does pack)
    { terrain = { "grass", 7 }, soil = { 0.123456789, 0.5 } }, -- a non-string id; not hundredths
    { terrain = {}, soil = { 1.5 } }, -- empty; out of range
    { terrain = { "a" }, soil = { -0.0 } }, -- negative zero
    { terrain = { "a" }, soil = { 0.1 + 0.2 } }, -- 0.30000000000000004 is not 30 / 100
  }
  for k, grid in ipairs(cases) do
    local back, packed = roundTrip(grid)
    T.same(back.terrain, grid.terrain, "case " .. k .. " terrain")
    T.same(back.soil, grid.soil, "case " .. k .. " soil")
    if k >= 2 then
      T.eq(type(packed.soil), "table", "case " .. k .. " soil stays plain")
    end
  end
  local many = {}
  for i = 1, 60 do
    many[i] = "terrain" .. i -- more ids than palette letters
  end
  T.eq(type(Gridpack.pack({ terrain = many }).terrain), "table")
  T.errors(function()
    Gridpack.unpack({ terrain = "ids:grass;x5" })
  end, "unknown id")
  T.errors(function()
    Gridpack.unpack({ soil = "garbage" })
  end, "malformed")
end)

T.test("save: a real run's grid is written packed, read back exactly, and the file shrinks", function()
  local world = newWorld(3)
  for _ = 1, 400 do
    world:tick(STEP)
  end
  local data = Save.newSlotData("Packed")
  data.run = world.state
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  T.truthy(store:write(1, data))
  T.eq(type(world.state.grid.terrain), "table", "writing leaves the live grid as plain arrays")
  local file = backend.files["slot1.sav"]
  T.truthy(file:find('terrain = "ids:', 1, true), "the file holds the compact terrain")
  local plain = #serialize.encode(data)
  T.truthy(#file < plain * 0.45, string.format("file %d bytes vs %d plain", #file, plain))
  local back = store:read(1)
  T.same(back.run.grid, world.state.grid)
  T.same(back.run, world.state)
  -- A damaged map string makes the slot unreadable instead of loading garbage.
  backend.files["slot1.sav"] = file:gsub('terrain = "ids:', 'terrain = "oops:', 1)
  backend.files["slot1.bak"] = nil
  local bad, err = store:read(1)
  T.eq(bad, nil)
  T.truthy(tostring(err):find("damaged map", 1, true), tostring(err))
end)

-- Overlay probes ----------------------------------------------------------------------------------

T.test("perf: probes average per tick and per frame, and flag a figure over budget", function()
  Perf.reset()
  for _ = 1, 3 do
    Perf.add("tick", 0.001)
    Perf.add("tick", 0.003)
    Perf.add("update", 0.005)
    Perf.add("draw", 0.002)
    Perf.endFrame()
  end
  local s = Perf.summary()
  T.near(s.tickMs, 2, 1e-9)
  T.near(s.ticksPerFrame, 2, 1e-9)
  T.near(s.simMs, 4, 1e-9)
  T.near(s.updateMs, 5, 1e-9)
  T.near(s.drawMs, 2, 1e-9)
  T.near(s.worstTickMs, 3, 1e-9)
  local lines = Perf.lines({ simMsPerTick = 1, worstTickMs = 8, drawMs = 8 })
  T.eq(#lines, 3)
  T.truthy(lines[1]:find("OVER", 1, true), lines[1])
  T.falsy(lines[3]:find("OVER", 1, true), lines[3])
  Perf.reset()
  T.near(Perf.summary().tickMs, 0, 1e-9)
end)

-- Allocation budget -------------------------------------------------------------------------------

package.path = "tools/balance/?.lua;" .. package.path

T.test("budget: the sim allocates within tuning.perf per tick over a played stretch", function()
  local Balance = require("balance")
  local Features = require("features")
  local Policies = require("policies")
  local Session = require("src.session")
  local ctx = Balance.context()
  local cfg = ctx.tuning.perf
  local data = Save.newSlotData("budget")
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local session = Session.new({ store = store, slot = 1, data = data, registry = ctx.registry, tuning = ctx.tuning, seed = 1 })
  local world = session.world
  local policy = Policies.new("scripted", world, 1, Features.parse(nil))
  world.events:on("calendar.newDay", function()
    policy:daily(world)
  end)
  local decision = math.max(1, math.floor(ctx.tuning.idle.recheckInterval * ctx.tuning.time.tickRate + 0.5))
  local ticks = cfg.testWindowDays * ctx.tuning.time.dayLength * ctx.tuning.time.tickRate
  local total, worst, measured = 0, 0, 0
  for n = 0, ticks - 1 do
    local offer = require("src.sim.systems.finds").pending(world)
    if offer then
      require("src.sim.systems.finds").choose(world, policy:chooseFind(world, offer))
    end
    if n % decision == 0 then
      policy:step(world)
    end
    collectgarbage("stop")
    local before = collectgarbage("count")
    world:tick(STEP)
    local grew = collectgarbage("count") - before
    collectgarbage("restart")
    if n >= ticks / 5 then -- the first fifth is the starter field and the opening orders
      total, measured, worst = total + grew, measured + 1, math.max(worst, grew)
    end
  end
  local mean = total / measured
  print(string.format("  alloc per tick: mean %.2f KB (budget %.1f), worst %.1f KB (budget %.0f)", mean, cfg.testAllocKbPerTick, worst, cfg.testAllocKbWorstTick))
  T.truthy(mean <= cfg.testAllocKbPerTick, string.format("mean %.2f KB per tick is over the %.1f budget", mean, cfg.testAllocKbPerTick))
  T.truthy(worst <= cfg.testAllocKbWorstTick, string.format("worst tick %.1f KB is over the %.0f budget", worst, cfg.testAllocKbWorstTick))
end)
