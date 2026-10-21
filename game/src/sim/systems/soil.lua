-- Soil fertility (PLAN_DEPTH 8.2, D178): a 0..1 number on every tile, beside soil quality and the water table.
--
-- State:
--   world.state.grid.fertility[i]   fertility 0..1, whole hundredths, made from the seed (own RNG stream
--                                   "soil") and saved with the grid like the water table
--   world.state.soil.worked[i]      set of tiles a harvest has drawn below the fallow ceiling: the only ones
--                                   the daily fallow step visits, so a large grid costs nothing per day
-- A harvest draws fertility by the crop's `fertilityDraw` (negative adds: legumes). Yield scales with it
-- between `soilFloor` and 1, so neglected land still gives about the floor, never nothing. A worked tile with
-- no crop regains `fallowRate` a day up to `fallowCeiling`. Compost, manure and mulch (D4, D5) call Soil.add.
-- Emits "soil.changed" { tile, from, to, cause } on every change.
--
-- Rotation and pest pressure (PLAN_DEPTH 8.3, D179):
--   world.state.soil.family[i]     rotation family of the last crop harvested on the tile (memory, never cleared)
--   world.state.soil.pressure[i]   pest pressure 0..1, whole hundredths, only tiles above 0
-- Harvesting the same family twice in a row adds `pressurePerRepeat`; a different family takes `rotateRelief` off,
-- and a tile with no crop sheds `fallowRelief` a day. Pressure cuts yield by up to `pressureCut` (a share of the
-- yield, so never to zero) and, from `pestAt`, invites a daily pest roll (own RNG stream "pests") that knocks the
-- growing crop back (never kills it); the pestGuard stat (row covers) turns part of that aside.
-- Emits "soil.pressure" { tile, from, to, cause } on every change and "pest.struck" { tile, crop, pressure, saved }.

local Grid = require("src.sim.grid")
local Noise = require("src.sim.noise")
local Stats = require("src.sim.stats")

local Soil = {}

local function whole(v)
  return math.floor(math.max(0, math.min(1, v)) * 100 + 0.5) / 100
end

-- Made once per run (or when a save has none): quality sets the centre, seeded noise the patchiness.
local function generate(world)
  local cfg = world.tuning.soil
  local grid = world.state.grid
  local sample = Noise.value(world:rng("soil"), grid.w, grid.h, cfg.noiseScale)
  grid.fertility = {}
  for y = 1, grid.h do
    for x = 1, grid.w do
      local i = Grid.index(grid, x, y)
      local value = cfg.startBase + cfg.startSoilWeight * (grid.soil[i] - 0.5) + cfg.startNoise * (sample(x, y) - 0.5)
      grid.fertility[i] = whole(value)
    end
  end
end

--- Fertility of tile i, 0..1.
function Soil.fertility(world, i)
  return world.state.grid.fertility[i] or 0
end

--- Pest pressure on tile i, 0..1.
function Soil.pressure(world, i)
  return world.state.soil.pressure[i] or 0
end

--- Yield multiplier from pest pressure: 1 clean, down to 1 - `pressureCut` at full pressure (never zero).
function Soil.pressureFactor(world, i)
  return 1 - world.tuning.soil.pressureCut * Soil.pressure(world, i)
end

--- Rotation family of the last crop harvested on tile i, or nil.
function Soil.lastFamily(world, i)
  return world.state.soil.family[i]
end

--- Would a harvest of `cropDef` on tile i repeat the family last harvested there?
function Soil.repeats(world, i, cropDef)
  return cropDef.family ~= nil and world.state.soil.family[i] == cropDef.family
end

--- Yield multiplier from fertility alone: `soilFloor` at 0, 1 at full.
function Soil.fertilityFactor(world, i)
  local floor = world.tuning.soil.soilFloor
  return floor + (1 - floor) * Soil.fertility(world, i)
end

--- Yield multiplier of tile i: soil quality (tuning.farming.soilYieldMin..Max) times the fertility factor
--- times the pest-pressure factor.
function Soil.yieldMultiplier(world, i)
  local farming = world.tuning.farming
  local quality = farming.soilYieldMin + (farming.soilYieldMax - farming.soilYieldMin) * world.state.grid.soil[i]
  return quality * Soil.fertilityFactor(world, i) * Soil.pressureFactor(world, i)
end

--- Harvest a crop would give on tile i today, before the harvest's own rounding roll (the Plan readout).
function Soil.expectedYield(world, cropId, i)
  return world.registry:get("crops", cropId).yield * Soil.yieldMultiplier(world, i)
end

--- Change tile i's fertility by `delta` (negative draws), clamped to 0..1. Returns the new value.
function Soil.add(world, i, delta, cause)
  local grid = world.state.grid
  local from = grid.fertility[i]
  if from == nil then
    return 0
  end
  local to = whole(from + delta)
  if to == from then
    return to
  end
  grid.fertility[i] = to
  if to < world.tuning.soil.fallowCeiling then
    world.state.soil.worked[i] = true
  end
  world.events:emit("soil.changed", { tile = i, from = from, to = to, cause = cause })
  return to
end

local function setPressure(world, i, to, cause)
  local pressure = world.state.soil.pressure
  local from = pressure[i] or 0
  to = whole(to)
  if to == from then
    return
  end
  pressure[i] = to > 0 and to or nil
  world.events:emit("soil.pressure", { tile = i, from = from, to = to, cause = cause })
end

--- A harvest of `cropDef` on tile i: draw its fertility (or add, for a negative draw), and build or relieve
--- pest pressure by whether the crop's family repeats the last one there.
function Soil.harvested(world, i, cropDef)
  local cfg = world.tuning.soil
  local soil = world.state.soil
  if cropDef.family then
    local last = soil.family[i]
    if last == cropDef.family then
      setPressure(world, i, Soil.pressure(world, i) + cfg.pressurePerRepeat, "repeat")
    elseif last then
      setPressure(world, i, Soil.pressure(world, i) - cfg.rotateRelief, "rotate")
    end
    soil.family[i] = cropDef.family
  end
  return Soil.add(world, i, -cropDef.fertilityDraw, "harvest")
end

--- Mean, lowest and count of fertility over `tiles` (a list of tile indices), or nil for none.
function Soil.summary(world, tiles)
  local sum, low, n = 0, 1, 0
  for _, i in ipairs(tiles) do
    local f = world.state.grid.fertility[i]
    if f then
      sum, n = sum + f, n + 1
      low = math.min(low, f)
    end
  end
  if n == 0 then
    return nil
  end
  return { mean = sum / n, low = low, count = n }
end

--- One game day of fallow: every worked tile without a crop regains fallowRate toward the ceiling.
function Soil.fallow(world)
  local Crops = require("src.sim.systems.crops") -- here, not at the top: crops reads soil too
  local cfg = world.tuning.soil
  local grid, worked = world.state.grid, world.state.soil.worked
  for i in pairs(worked) do
    local f = grid.fertility[i]
    if f >= cfg.fallowCeiling then
      worked[i] = nil
    elseif not Crops.hasCropAt(world, i) then
      local to = whole(math.min(cfg.fallowCeiling, f + cfg.fallowRate))
      grid.fertility[i] = to
      if to >= cfg.fallowCeiling then
        worked[i] = nil
      end
    end
  end
end

--- Tiles with pest pressure, ascending (a small set: only affected tiles are stored).
function Soil.pressureTiles(world)
  local tiles = {}
  for i in pairs(world.state.soil.pressure) do
    tiles[#tiles + 1] = i
  end
  table.sort(tiles)
  return tiles
end

--- One game day of pests: an empty tile sheds pressure, and a growing crop on a tile at `pestAt` or more rolls
--- (in tile order, whatever the guard, so the stream does not depend on the defences) to be knocked back.
function Soil.pests(world)
  local Crops = require("src.sim.systems.crops") -- here, not at the top: crops reads soil too
  local cfg = world.tuning.soil
  local guard = math.min(world.tuning.threats.maxGuard, Stats.modifier(world, "pestGuard"))
  local rng
  for _, i in ipairs(Soil.pressureTiles(world)) do
    local pressure = Soil.pressure(world, i)
    if not Crops.hasCropAt(world, i) then
      setPressure(world, i, pressure - cfg.fallowRelief, "fallow")
    elseif pressure >= cfg.pestAt and not Crops.isRipeAt(world, i) then
      rng = rng or world:rng("pests")
      local chance = cfg.pestChance * pressure
      local roll = rng:float()
      if roll < chance then
        local crop = Crops.cropIdAt(world, i)
        local saved = roll >= chance * (1 - guard)
        if not saved then
          Crops.setBack(world, i, cfg.pestSetback, "pests")
        end
        world.events:emit("pest.struck", { tile = i, crop = crop, pressure = pressure, saved = saved })
      end
    end
  end
end

function Soil.init(world)
  local state = world.state
  state.soil = state.soil or { worked = {} }
  state.soil.family = state.soil.family or {}
  state.soil.pressure = state.soil.pressure or {}
  if not state.grid.fertility then
    generate(world)
  end
  world.events:on("calendar.newDay", function()
    Soil.fallow(world)
    Soil.pests(world)
  end)
end

return Soil
