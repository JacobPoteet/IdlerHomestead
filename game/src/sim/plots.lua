-- Plot preview (D200, #384, docs/PLAN_DEPTH.md 12.1): the plots offered at the start of a new run.
--
-- A plot is a seed. `Plots.summarize` generates the land a seed would make on a bare stand-in world (the land
-- generator and the grid helpers only, none of the systems), and reads its traits off the grid. The numbers
-- come from tuning.plots. It is deterministic: the same seed always gives the same summary, and the summary is
-- plain data that can be saved:
--
--   { seed, soil = 1..3, water = 1..3, wood = 1..3, sun = 1..3 (levels; 3 is best),
--     values = { soil, waterTiles, trees, shade, rocks, clutter },
--     hazard = id | nil, bonus = { resourceId = amount } | nil }
--
-- `Plots.offer` derives the offered seeds from a base seed, so one stored base seed is the whole offer.
-- Choosing is optional (the caller takes the first plot when nothing is chosen). A plot with a hazard comes
-- with a small starting bonus: that is the reward half of the trade, so the easy plot is not always the pick.

local Grid = require("src.sim.grid")
local Landgen = require("src.sim.landgen")
local Rng = require("src.core.rng")
local World = require("src.sim.world")

local Plots = {}

local TREE_KIND = "tree"

--- Level 1..3 of `value` against a trait's thresholds (see tuning.plots).
local function level(cfg, value)
  local lvl = 1
  for _, t in ipairs(cfg.thresholds) do
    if (cfg.lowIsGood and value <= t) or (not cfg.lowIsGood and value >= t) then
      lvl = lvl + 1
    end
  end
  return lvl
end

--- Land for `seed` on a bare world, with no systems: just what Landgen needs.
local function bareLand(registry, tuning, seed)
  local world = setmetatable({
    state = World.newState(seed),
    registry = registry,
    tuning = tuning,
    rngStreams = {},
    occupancy = {},
  }, World)
  Landgen.generate(world)
  return world
end

--- The traits of the land `seed` makes (see the header). Costs one land generation.
function Plots.summarize(registry, tuning, seed)
  local cfg = tuning.plots
  local world = bareLand(registry, tuning, seed)
  local grid, truck = world.state.grid, world.state.land.truck
  local tx, ty = Grid.coords(grid, truck)
  local traitR, woodR = cfg.traitRadius, cfg.woodRadius

  local soilSum, soilN, rocks, clutter, trees = 0, 0, 0, 0, 0
  local shaded = {}
  for anchor, obj in pairs(grid.objects) do
    local x, y = Grid.coords(grid, anchor)
    local near = math.max(math.abs(x - tx), math.abs(y - ty))
    local def = registry:get("objects", obj.id)
    if def.kind == TREE_KIND then
      if near <= woodR then
        trees = trees + 1
      end
      for dy = -cfg.shadeReach, cfg.shadeReach do
        for dx = -cfg.shadeReach, cfg.shadeReach do
          if Grid.inBounds(grid, x + dx, y + dy) then
            shaded[Grid.index(grid, x + dx, y + dy)] = true
          end
        end
      end
    elseif near <= traitR then
      if obj.id == "rock" then
        rocks = rocks + 1
      elseif obj.id == "brush" or obj.id == "log" then
        clutter = clutter + 1
      end
    end
  end

  local tiles, clear = 0, 0
  local waterTiles = math.huge
  for y = math.max(1, ty - traitR), math.min(grid.h, ty + traitR) do
    for x = math.max(1, tx - traitR), math.min(grid.w, tx + traitR) do
      local i = Grid.index(grid, x, y)
      tiles = tiles + 1
      if not shaded[i] then
        clear = clear + 1
      end
      if registry:get("terrain", grid.terrain[i]).tillable then
        soilSum, soilN = soilSum + grid.soil[i], soilN + 1
      end
    end
  end
  -- Distance to the nearest water over the whole map (the creek may lie outside the trait radius).
  for i = 1, #grid.terrain do
    if registry:get("terrain", grid.terrain[i]).water then
      local x, y = Grid.coords(grid, i)
      waterTiles = math.min(waterTiles, math.max(math.abs(x - tx), math.abs(y - ty)))
    end
  end

  local values = {
    soil = soilN > 0 and soilSum / soilN or 0,
    waterTiles = waterTiles,
    trees = trees,
    shade = tiles > 0 and clear / tiles or 1,
    rocks = rocks,
    clutter = clutter,
  }
  local summary = {
    seed = seed,
    soil = level(cfg.soil, values.soil),
    water = level(cfg.water, values.waterTiles),
    wood = level(cfg.wood, values.trees),
    sun = level(cfg.sun, values.shade),
    values = values,
  }
  for _, h in ipairs(cfg.hazards) do
    if values[h.test.trait] >= h.test.atLeast then
      summary.hazard = h.id
      summary.bonus = h.bonus
      break
    end
  end
  return summary
end

--- The hazard's tuning row for an id (name, line, bonus), or nil.
function Plots.hazard(tuning, id)
  for _, h in ipairs(tuning.plots.hazards) do
    if h.id == id then
      return h
    end
  end
  return nil
end

--- The seeds of the offer for a base seed: the same base always gives the same seeds.
function Plots.seeds(tuning, baseSeed)
  local seeds = {}
  for n = 1, tuning.plots.offered do
    seeds[n] = Rng.deriveSeed(baseSeed, "plot" .. n)
  end
  return seeds
end

--- The offered plots for a base seed: a list of summaries (see the header), in a fixed order.
function Plots.offer(registry, tuning, baseSeed)
  local list = {}
  for n, seed in ipairs(Plots.seeds(tuning, baseSeed)) do
    list[n] = Plots.summarize(registry, tuning, seed)
  end
  return list
end

return Plots
