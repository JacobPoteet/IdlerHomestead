-- Soil fertility (PLAN_DEPTH 8.2, D178, issue #364): the per-tile number made from the seed, drawn by harvests,
-- refilled by fallow, never below the yield floor; the Soil lens's data and the Plan readout's numbers.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Fields = require("src.render.lens_fields")
local Gridpack = require("src.core.gridpack")
local Grid = require("src.sim.grid")
local LensState = require("src.ui.lens")
local Ledger = require("src.sim.systems.ledger")
local Save = require("src.core.save")
local Soil = require("src.sim.systems.soil")
local Tasks = require("src.sim.systems.tasks")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.soil

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active"
  return world
end

--- A free tillable tile near the spawn.
local function freeTile(world, skip)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  for r = 1, 10 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and i ~= skip
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and not Crops.tileInUse(world, i)
        then
          return i
        end
      end
    end
  end
end

--- Plant a ripe `cropId` on tile i and harvest it through the real task.
local function harvest(world, i, cropId)
  world.state.fields.tilled[i] = true
  world.state.crops[i] = { id = cropId, growth = 1, moisture = 1 }
  Ledger.add(world, reg:get("crops", cropId).produce, 0) -- the stores exist
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
end

local function newDay(world)
  world.events:emit("calendar.newDay", { day = 1, season = "spring", year = 1 })
end

-- Making it ---------------------------------------------------------------------------------------

T.test("soil: every tile gets a fertility in whole hundredths, from the seed, with real variation", function()
  local a, b, c = newWorld(4), newWorld(4), newWorld(9)
  local fa = a.state.grid.fertility
  T.eq(#fa, a.state.grid.w * a.state.grid.h)
  local lo, hi = 1, 0
  for i = 1, #fa do
    T.truthy(fa[i] >= 0 and fa[i] <= 1, "in range")
    T.eq(math.floor(fa[i] * 100 + 0.5) / 100, fa[i], "whole hundredths, so it packs")
    lo, hi = math.min(lo, fa[i]), math.max(hi, fa[i])
  end
  T.truthy(hi - lo > 0.1, "the ground is patchy, not flat")
  T.same(fa, b.state.grid.fertility, "same seed, same ground")
  T.truthy(serialize.encode(fa) ~= serialize.encode(c.state.grid.fertility), "another seed, another ground")
end)

T.test("soil: making the ground uses its own stream, so the plot and the water table are unchanged", function()
  local world = newWorld(4)
  T.truthy(world.state.rng.soil ~= nil, "the soil stream exists")
  local before = serialize.encode({ world.state.grid.terrain, world.state.grid.soil, world.state.grid.waterTable })
  local again = newWorld(4)
  T.eq(serialize.encode({ again.state.grid.terrain, again.state.grid.soil, again.state.grid.waterTable }), before)
end)

T.test("soil: richer earth starts richer (soil quality shifts the centre)", function()
  local world = newWorld(4)
  local grid = world.state.grid
  local poorSum, poorN, richSum, richN = 0, 0, 0, 0
  for i = 1, #grid.soil do
    if grid.soil[i] < 0.35 then
      poorSum, poorN = poorSum + grid.fertility[i], poorN + 1
    elseif grid.soil[i] > 0.65 then
      richSum, richN = richSum + grid.fertility[i], richN + 1
    end
  end
  if poorN > 20 and richN > 20 then
    T.truthy(richSum / richN > poorSum / poorN, "rich soil is more fertile on average")
  end
end)

-- Draw and yield ----------------------------------------------------------------------------------

T.test("soil: a harvest draws the crop's fertility draw, and beans add", function()
  local world = newWorld()
  local i = freeTile(world)
  local j = freeTile(world, i)
  world.state.grid.fertility[i] = 0.9
  harvest(world, i, "potato")
  T.near(Soil.fertility(world, i), 0.9 - reg:get("crops", "potato").fertilityDraw, 0.001)
  world.state.grid.fertility[j] = 0.5
  harvest(world, j, "beans")
  T.near(Soil.fertility(world, j), 0.5 + 0.15, 0.001, "a legume's negative draw adds")
end)

T.test("soil: fertility stays within 0..1 and reports each change", function()
  local world = newWorld()
  local i = freeTile(world)
  local seen = {}
  world.events:on("soil.changed", function(e)
    seen[#seen + 1] = e
  end)
  world.state.grid.fertility[i] = 0.05
  T.eq(Soil.add(world, i, -0.4, "test"), 0, "never below zero")
  T.eq(#seen, 1)
  T.eq(seen[1].tile, i)
  T.eq(seen[1].cause, "test")
  world.state.grid.fertility[i] = 0.95
  T.eq(Soil.add(world, i, 0.4, "test"), 1, "never above one")
  T.eq(Soil.add(world, i, 0.4, "test"), 1)
  T.eq(#seen, 2, "no change, no event")
end)

T.test("soil: yield scales with fertility between the floor and the full multiplier", function()
  local world = newWorld()
  local i = freeTile(world)
  world.state.grid.soil[i] = 1
  world.state.grid.fertility[i] = 1
  local full = Soil.yieldMultiplier(world, i)
  T.near(full, tun.farming.soilYieldMax, 0.0001, "full fertility leaves the soil-quality multiplier as it was")
  world.state.grid.fertility[i] = 0
  T.near(Soil.yieldMultiplier(world, i), tun.farming.soilYieldMax * cfg.soilFloor, 0.0001, "none leaves the floor")
  world.state.grid.fertility[i] = 0.5
  local mid = Soil.yieldMultiplier(world, i)
  T.truthy(mid > full * cfg.soilFloor and mid < full, "and it rises between")
  T.near(Soil.expectedYield(world, "potato", i), reg:get("crops", "potato").yield * mid, 0.0001)
end)

T.test("soil: dead land is never dead (the floor) and a harvest there still gives something", function()
  local world = newWorld()
  local i = freeTile(world)
  world.state.grid.soil[i] = 0
  world.state.grid.fertility[i] = 0
  T.truthy(Soil.yieldMultiplier(world, i) >= tun.farming.soilYieldMin * cfg.soilFloor - 1e-9)
  T.truthy(Soil.yieldMultiplier(world, i) > 0)
  local before = Ledger.get(world, "radish")
  harvest(world, i, "radish")
  T.truthy(Ledger.get(world, "radish") - before >= 1, "at least one comes up")
  T.eq(Soil.fertility(world, i), 0, "and a drained tile cannot be drawn lower")
end)

T.test("soil: the harvest is read before it draws, so one crop is not punished by its own draw", function()
  local world = newWorld(4)
  local i = freeTile(world)
  world.state.grid.fertility[i] = 1
  local expected = Soil.expectedYield(world, "corn", i)
  local seen
  world.events:on("crop.harvested", function(e)
    seen = e.amount
  end)
  harvest(world, i, "corn")
  T.truthy(seen >= math.floor(expected) and seen <= math.floor(expected) + 1, "amount follows the fertility it saw")
end)

-- Fallow ------------------------------------------------------------------------------------------

T.test("soil: a worked tile with no crop regains fallowRate a day, up to the ceiling, then is let go", function()
  local world = newWorld()
  local i = freeTile(world)
  world.state.grid.fertility[i] = 0.9
  harvest(world, i, "corn")
  local left = 0.9 - reg:get("crops", "corn").fertilityDraw
  T.near(Soil.fertility(world, i), left, 0.001)
  T.truthy(world.state.soil.worked[i], "the draw marks it worked")
  newDay(world)
  T.near(Soil.fertility(world, i), left + cfg.fallowRate, 0.001, "one day, one step")
  for _ = 1, 40 do
    newDay(world)
  end
  T.near(Soil.fertility(world, i), cfg.fallowCeiling, 0.001, "fallow stops at the ceiling")
  T.falsy(world.state.soil.worked[i], "and the tile leaves the list")
end)

T.test("soil: nothing regrows under a crop, and fallow never lifts a tile past the ceiling", function()
  local world = newWorld()
  local i = freeTile(world)
  local j = freeTile(world, i)
  world.state.grid.fertility[i] = 0.5
  Soil.add(world, i, -0.1, "test")
  world.state.crops[i] = { id = "radish", growth = 0.2, moisture = 1 }
  newDay(world)
  T.near(Soil.fertility(world, i), 0.4, 0.001, "a growing crop holds the tile")
  world.state.crops[i] = nil
  newDay(world)
  T.near(Soil.fertility(world, i), 0.43, 0.001)
  world.state.grid.fertility[j] = 0.95
  Soil.add(world, j, 0.0, "test")
  newDay(world)
  T.eq(Soil.fertility(world, j), 0.95, "rich ground stays as it is")
end)

T.test("soil: only worked tiles are visited, and compost-style Soil.add can pass the ceiling", function()
  local world = newWorld()
  local i = freeTile(world)
  local before = world.state.grid.fertility[i]
  for _ = 1, 5 do
    newDay(world)
  end
  T.eq(world.state.grid.fertility[i], before, "untouched ground does not drift")
  world.state.grid.fertility[i] = 0.8
  Soil.add(world, i, 0.15, "compost")
  T.near(Soil.fertility(world, i), 0.95, 0.001)
  T.falsy(world.state.soil.worked[i], "above the ceiling there is nothing for fallow to do")
end)

-- The overlay's data ------------------------------------------------------------------------------

T.test("soil lens: the Plan field tool shows it, other modes and tools do not", function()
  local lens = tun.ui.lens
  T.eq(LensState.forMode(lens, "plan"), "soil")
  T.eq(LensState.forMode(lens, "act"), nil)
  T.eq(LensState.forMode(lens, "place"), nil)
  T.eq(LensState.forMode(lens, nil), nil)
  T.truthy(lens.title.soil and lens.legend.soil)
end)

T.test("soil lens: fertility on farmable ground, the farm marked, water and buildings left blank", function()
  local world = newWorld()
  local grid = world.state.grid
  local i = freeTile(world)
  world.state.fields.tilled[i] = true
  world.state.grid.fertility[i] = 0.62
  local f = Fields.soil(world)
  T.eq(f.w, grid.w)
  T.eq(f.r[i], 0.62)
  T.eq(f.a[i], 1, "farmable")
  T.eq(f.g[i], 1, "part of the farm")
  local water
  for k = 1, #grid.terrain do
    if grid.terrain[k] == "water" then
      water = k
      break
    end
  end
  T.truthy(water, "the plot has a creek")
  T.eq(f.a[water], 0)
  T.eq(f.r[water], 0)
  local farm = 0
  for k = 1, grid.w * grid.h do
    farm = farm + f.g[k]
  end
  T.eq(farm, #Crops.fieldTiles(world), "only the farm's tiles are marked")
end)

T.test("soil readout: the summary and the expected yield for a rectangle", function()
  local world = newWorld()
  local i = freeTile(world)
  local j = freeTile(world, i)
  world.state.grid.fertility[i], world.state.grid.fertility[j] = 0.4, 0.8
  local s = Soil.summary(world, { i, j })
  T.near(s.mean, 0.6, 0.0001)
  T.eq(s.low, 0.4)
  T.eq(s.count, 2)
  T.eq(Soil.summary(world, {}), nil)
  local both = Soil.expectedYield(world, "potato", i) + Soil.expectedYield(world, "potato", j)
  T.truthy(both > 0)
end)

-- Saving ------------------------------------------------------------------------------------------

T.test("soil: fertility and the worked set survive a save, packed with the grid", function()
  local world = newWorld()
  local i = freeTile(world)
  world.state.grid.fertility[i] = 0.5
  Soil.add(world, i, -0.1, "test")
  local data = Save.newSlotData("Soil")
  data.run = world.state
  local disk = serialize.decode(serialize.encode(Save.forDisk(data)))
  T.eq(type(disk.run.grid.fertility), "string", "packed in hundredths like the soil array")
  Gridpack.unpack(disk.run.grid)
  T.same(disk.run.grid.fertility, world.state.grid.fertility)
  T.truthy(disk.run.soil.worked[i])
  local loaded = World.new({ registry = reg, tuning = tun }, disk.run)
  T.eq(Soil.fertility(loaded, i), 0.4)
end)

-- Rotation and pest pressure (PLAN_DEPTH 8.3, D179) ----------------------------------------------------

T.test(
  "pressure: the same family twice in a row builds it, rotating relieves it, the first harvest sets none",
  function()
    local world = newWorld()
    local i = freeTile(world)
    harvest(world, i, "radish")
    T.eq(Soil.pressure(world, i), 0, "no history, no pressure")
    T.eq(world.state.soil.family[i], "brassicas", "the family is remembered")
    harvest(world, i, "radish")
    T.near(Soil.pressure(world, i), cfg.pressurePerRepeat, 0.001, "a repeat builds pressure")
    harvest(world, i, "radish")
    T.near(Soil.pressure(world, i), 2 * cfg.pressurePerRepeat, 0.001)
    harvest(world, i, "potato")
    T.near(
      Soil.pressure(world, i),
      math.max(0, 2 * cfg.pressurePerRepeat - cfg.rotateRelief),
      0.001,
      "a rotation relieves it"
    )
    T.eq(world.state.soil.family[i], "nightshades")
    harvest(world, i, "beans")
    harvest(world, i, "radish")
    T.eq(Soil.pressure(world, i), 0, "rotating clears it for good")
  end
)

T.test("pressure: it caps at 1, is whole hundredths and reports each change", function()
  local world = newWorld()
  local i = freeTile(world)
  local seen = {}
  world.events:on("soil.pressure", function(e)
    seen[#seen + 1] = e
  end)
  for _ = 1, 8 do
    harvest(world, i, "radish")
  end
  T.eq(Soil.pressure(world, i), 1, "capped")
  T.eq(math.floor(Soil.pressure(world, i) * 100 + 0.5) / 100, Soil.pressure(world, i))
  T.truthy(#seen >= 4 and seen[1].cause == "repeat" and seen[1].tile == i, "each change is announced")
  local before = #seen
  harvest(world, i, "radish")
  T.eq(#seen, before, "no change, no event")
end)

T.test("pressure: it cuts yield by a share, and the cut never reaches zero", function()
  local world = newWorld()
  local i = freeTile(world)
  T.eq(Soil.pressureFactor(world, i), 1, "clean ground: no cut")
  world.state.soil.pressure[i] = 1
  T.near(Soil.pressureFactor(world, i), 1 - cfg.pressureCut, 1e-9)
  T.truthy(cfg.pressureCut > 0 and cfg.pressureCut < 1, "a share of the yield, not all of it")
  local clean = freeTile(world, i)
  T.truthy(Soil.yieldMultiplier(world, i) < Soil.yieldMultiplier(world, clean) + 1e-9, "pressure only lowers")
  -- The worst ground there is: no fertility, full pressure, the poorest soil. A harvest still gives something.
  world.state.grid.fertility[i] = 0
  world.state.grid.soil[i] = 0
  T.truthy(Soil.yieldMultiplier(world, i) > 0)
  for _ = 1, 30 do
    harvest(world, i, "radish")
    T.truthy(world.state.soil.pressure[i] == 1)
    T.truthy(Ledger.get(world, "radish") > 0)
    local before = Ledger.get(world, "radish")
    Ledger.remove(world, "radish", before, "test")
    world.state.grid.fertility[i] = 0
  end
end)

T.test("pressure: the Plan readout and the harvest read the pressured multiplier", function()
  local world = newWorld()
  local i = freeTile(world)
  local clean = Soil.expectedYield(world, "radish", i)
  world.state.soil.pressure[i] = 1
  T.near(Soil.expectedYield(world, "radish", i), clean * (1 - cfg.pressureCut), 1e-9)
end)

T.test("pressure: harvested announces the pressure and whether the family repeated", function()
  local world = newWorld()
  local i = freeTile(world)
  local seen = {}
  world.events:on("crop.harvested", function(e)
    seen[#seen + 1] = e
  end)
  harvest(world, i, "radish")
  harvest(world, i, "radish")
  harvest(world, i, "potato")
  T.eq(seen[1].repeated, false)
  T.eq(seen[2].repeated, true)
  T.near(seen[3].pressure, cfg.pressurePerRepeat, 0.001, "the pressure the harvest met, before it changed")
  T.eq(seen[3].repeated, false)
end)

T.test("pressure: a tile with no crop sheds it a day, and a crop on it holds it", function()
  local world = newWorld()
  local i = freeTile(world)
  local j = freeTile(world, i)
  world.state.soil.pressure[i] = 0.3
  world.state.soil.pressure[j] = 0.3
  world.state.crops[j] = { id = "radish", growth = 0.1, moisture = 1 }
  newDay(world)
  T.near(Soil.pressure(world, i), 0.3 - cfg.fallowRelief, 0.001)
  T.eq(Soil.pressure(world, j), 0.3, "a growing crop keeps it")
  for _ = 1, 40 do
    newDay(world)
  end
  T.eq(Soil.pressure(world, i), 0, "fallow clears it")
  T.eq(world.state.soil.pressure[i], nil, "and the tile leaves the set")
  T.eq(world.state.soil.family[i], nil, "no history was made here")
end)

local function pestWorld(seed)
  local world = newWorld(seed)
  local tiles = {}
  for n = 1, 6 do
    local i = freeTile(world) -- planting it takes the tile out of the next search
    tiles[n] = i
    world.state.soil.pressure[i] = n <= 3 and 1 or 0.2
    world.state.crops[i] = { id = "potato", growth = 0.1, moisture = 1 }
  end
  return world, tiles
end

T.test(
  "pests: high pressure invites a pest that knocks the crop back, never kills it; low pressure is left alone",
  function()
    local world, tiles = pestWorld()
    local seen = {}
    world.events:on("pest.struck", function(e)
      seen[#seen + 1] = e
    end)
    local damaged = {}
    world.events:on("crop.damaged", function(e)
      damaged[e.tile] = e.cause
    end)
    for _ = 1, 30 do
      newDay(world)
      for _, i in ipairs(tiles) do
        T.truthy(world.state.crops[i], "a pest never kills the crop")
        world.state.crops[i].growth = 0.5 -- a hit would show as growth lost
      end
    end
    T.truthy(#seen > 0, "pests came to the pressured tiles")
    for _, e in ipairs(seen) do
      T.truthy(e.pressure >= cfg.pestAt, "only tiles at or above pestAt are visited")
      T.eq(damaged[e.tile], "pests", "the crop is hurt with the pests as the cause")
    end
    for n = 4, 6 do
      T.eq(damaged[tiles[n]], nil, "low pressure: left alone")
    end
  end
)

T.test("pests: ripe crops are not rolled for, and the roll is deterministic per seed", function()
  local function run(seed)
    local world, tiles = pestWorld(seed)
    world.state.crops[tiles[1]].growth = 1
    local out = {}
    world.events:on("pest.struck", function(e)
      out[#out + 1] = e.tile .. "@" .. #out
      T.truthy(e.tile ~= tiles[1], "the ripe one is spared")
    end)
    for _ = 1, 20 do
      newDay(world)
      for _, i in ipairs(tiles) do
        world.state.crops[i].growth = i == tiles[1] and 1 or 0.5
      end
    end
    return table.concat(out, " ")
  end
  T.eq(run(3), run(3))
end)

T.test("pests: row covers (pestGuard) turn them aside and the rolls do not change", function()
  local Inventory = require("src.sim.systems.inventory")
  local function run(guarded)
    local world, tiles = pestWorld(5)
    if guarded then
      Inventory.addEquipment(world, "row_covers")
    end
    local hits, saved = 0, 0
    world.events:on("pest.struck", function(e)
      if e.saved then
        saved = saved + 1
      else
        hits = hits + 1
      end
    end)
    for _ = 1, 40 do
      newDay(world)
      for _, i in ipairs(tiles) do
        world.state.crops[i].growth = 0.5
      end
    end
    return hits, saved
  end
  local hits0, saved0 = run(false)
  local hits1, saved1 = run(true)
  T.eq(saved0, 0)
  T.truthy(hits1 < hits0, "the covers cut the hits")
  T.eq(hits1 + saved1, hits0, "the same pests came; the covers saved some")
end)

T.test("pests: their stream is their own, so the farming rolls are unchanged", function()
  local a, tilesA = pestWorld(6)
  local b = pestWorld(6)
  for _ = 1, 10 do
    newDay(a)
    for _, i in ipairs(tilesA) do
      a.state.crops[i].growth = 0.5
    end
  end
  T.eq(a:rng("farming"):float(), b:rng("farming"):float())
end)

T.test("rotation: rotating beats replanting the same crop, and neither ever yields nothing", function()
  local function year(rotate)
    local world = newWorld(2)
    local i = freeTile(world)
    local total, least = 0, math.huge
    local crops = rotate and { "radish", "potato", "beans", "radish", "potato", "beans" } or { "radish" }
    for n = 1, 18 do
      world.state.grid.fertility[i] = 0.8 -- the same ground each time: only pressure differs
      Ledger.remove(world, "radish", Ledger.get(world, "radish"), "test")
      Ledger.remove(world, "potato", Ledger.get(world, "potato"), "test")
      Ledger.remove(world, "beans", Ledger.get(world, "beans"), "test")
      local id = crops[(n - 1) % #crops + 1]
      harvest(world, i, id)
      local got = Ledger.get(world, reg:get("crops", id).produce)
      T.truthy(got >= 1, "never a zero yield")
      if id == "radish" then
        total, least = total + got, math.min(least, got)
      end
    end
    return total
  end
  -- Compare the radish: replanted every time it is cut; rotated it is cut only when it follows another family.
  T.truthy(year(true) / 6 >= year(false) / 18, "a rotated radish out-yields a replanted one")
end)

T.test("pressure: family memory and pressure survive a save", function()
  local world = newWorld()
  local i = freeTile(world)
  harvest(world, i, "radish")
  harvest(world, i, "radish")
  local data = Save.newSlotData("Soil")
  data.run = world.state
  local disk = serialize.decode(serialize.encode(Save.forDisk(data)))
  Gridpack.unpack(disk.run.grid)
  local loaded = World.new({ registry = reg, tuning = tun }, disk.run)
  T.near(Soil.pressure(loaded, i), cfg.pressurePerRepeat, 0.001)
  T.eq(loaded.state.soil.family[i], "brassicas")
end)

-- Cost --------------------------------------------------------------------------------------------

T.test("soil: the day's fallow step and the lens data stay cheap on a large grid", function()
  local world = newWorld()
  local grid = world.state.grid
  local n = grid.w * grid.h
  local worked = world.state.soil.worked
  for i = 1, n do
    grid.fertility[i] = 0.3
    worked[i] = true
  end
  local t0 = os.clock()
  Soil.fallow(world)
  local fallow = os.clock() - t0
  t0 = os.clock()
  Fields.soil(world)
  local lens = os.clock() - t0
  -- every tile of a 128 x 128 map worked at once is far worse than any real field; both are loose guards
  -- against an accidental per-tile cost, not a benchmark (docs/PERF.md)
  T.truthy(fallow < 0.25, "fallow over every tile took " .. fallow .. " s")
  T.truthy(lens < 0.5, "lens data took " .. lens .. " s")
end)
