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

local Grid = require("src.sim.grid")
local Noise = require("src.sim.noise")

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

--- Yield multiplier from fertility alone: `soilFloor` at 0, 1 at full.
function Soil.fertilityFactor(world, i)
  local floor = world.tuning.soil.soilFloor
  return floor + (1 - floor) * Soil.fertility(world, i)
end

--- Yield multiplier of tile i: soil quality (tuning.farming.soilYieldMin..Max) times the fertility factor.
function Soil.yieldMultiplier(world, i)
  local farming = world.tuning.farming
  local quality = farming.soilYieldMin + (farming.soilYieldMax - farming.soilYieldMin) * world.state.grid.soil[i]
  return quality * Soil.fertilityFactor(world, i)
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

--- A harvest of `cropDef` on tile i: draw its fertility (or add, for a negative draw).
function Soil.harvested(world, i, cropDef)
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

function Soil.init(world)
  local state = world.state
  state.soil = state.soil or { worked = {} }
  if not state.grid.fertility then
    generate(world)
  end
  world.events:on("calendar.newDay", function()
    Soil.fallow(world)
  end)
end

return Soil
