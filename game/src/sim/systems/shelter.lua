-- Shelter (GDD §5.3, D82): the ladder of places to sleep (truck, camp, shack). Accessors only, no
-- state of its own. A shelter is an object with `shelter = true` plus content fields:
--   shelterRank  higher is better; Sleep walks to the best reachable one and the accessors below
--                describe the best one placed (the bed you will sleep in tonight)
--   insulation   multiplier on the night's warmth need (lower keeps more heat)
--   recovery     multiplier on the daily Condition recovery of a fed, warm day
--   heaterRadius tiles (Chebyshev, from the shelter's footprint) within which a heat source or
--                electric heater delivers its warmth in full; farther ones deliver tuning.shelter.farHeat
--   studySpeed   added to the study speed while resting (a desk)
-- Other systems read the numbers only through these functions.

local Grid = require("src.sim.grid")
local Home = require("src.sim.systems.home")
local Wardrobe = require("src.sim.systems.wardrobe")

local Shelter = {}

--- Anchors of every placed shelter.
function Shelter.anchors(world)
  return Grid.anchorsWith(world, "shelter")
end

local function def(world, anchor)
  return world.registry:get("objects", world.state.grid.objects[anchor].id)
end

--- Rank of the shelter at `anchor` (higher is better).
function Shelter.rank(world, anchor)
  return def(world, anchor).shelterRank or 0
end

--- Order shelters best first: rank, then lower anchor index (deterministic).
function Shelter.better(world, a, b)
  local ra, rb = def(world, a).shelterRank or 0, def(world, b).shelterRank or 0
  if ra ~= rb then
    return ra > rb
  end
  return a < b
end

--- The best shelter placed: its anchor and definition, or nil.
function Shelter.best(world)
  local best
  for _, anchor in ipairs(Shelter.anchors(world)) do
    if not best or Shelter.better(world, anchor, best) then
      best = anchor
    end
  end
  if best then
    return best, def(world, best)
  end
  return nil
end

--- Multiplier on the night's warmth need (D82).
function Shelter.insulation(world)
  local _, d = Shelter.best(world)
  return (d and d.insulation or world.tuning.shelter.defaultInsulation) * Home.insulationFactor(world, d and d.id)
end

--- Multiplier on the night's warmth need from the bed and the clothes together (D82, D149): the shelter's
--- insulation times the wardrobe's. The one product tonight's need, the thermostat and the readiness forecast
--- share, so they stay in step. Exactly the shelter's in the starter outfit.
function Shelter.nightInsulation(world)
  return Shelter.insulation(world) * Wardrobe.insulation(world)
end

--- Multiplier on the daily Condition recovery.
function Shelter.recovery(world)
  local _, d = Shelter.best(world)
  return d and d.recovery or world.tuning.shelter.defaultRecovery
end

--- Study speed the best shelter adds while resting (a desk).
function Shelter.studySpeed(world)
  local _, d = Shelter.best(world)
  return d and d.studySpeed or 0
end

--- Id of the best shelter placed ("truck", "camp", "shack"), or nil.
function Shelter.id(world)
  local _, d = Shelter.best(world)
  return d and d.id or nil
end

--- Tiles from `tile` to the nearest tile of the shelter at `anchor` (0 inside it).
function Shelter.distanceTo(world, anchor, tile)
  local grid = world.state.grid
  local d = def(world, anchor)
  local sx, sy = Grid.coords(grid, anchor)
  local x, y = Grid.coords(grid, tile)
  local dx = math.max(0, sx - x, x - (sx + (d.footprintW or 1) - 1))
  local dy = math.max(0, sy - y, y - (sy + (d.footprintH or 1) - 1))
  return math.max(dx, dy)
end

--- Tiles of the heater slot of a shelter definition with its top-left tile at (x, y): the footprint
--- grown by heaterRadius on every side (clipped to the map). For the placement preview and the card.
function Shelter.slotTiles(world, shelterDef, x, y)
  local grid = world.state.grid
  local r = shelterDef.heaterRadius or 0
  local tiles = {}
  for ty = y - r, y + (shelterDef.footprintH or 1) - 1 + r do
    for tx = x - r, x + (shelterDef.footprintW or 1) - 1 + r do
      if Grid.inBounds(grid, tx, ty) then
        tiles[#tiles + 1] = Grid.index(grid, tx, ty)
      end
    end
  end
  return tiles
end

--- Is `tile` inside the best shelter's heater slot?
function Shelter.inHeaterSlot(world, tile)
  local anchor, d = Shelter.best(world)
  if not anchor then
    return true
  end
  return Shelter.distanceTo(world, anchor, tile) <= (d.heaterRadius or 0)
end

--- Share (0..1) of a heat source's warmth that reaches the sleeping spot, for a source at `tile`.
function Shelter.heatReach(world, tile)
  if Shelter.inHeaterSlot(world, tile) then
    return 1
  end
  return world.tuning.shelter.farHeat
end

return Shelter
