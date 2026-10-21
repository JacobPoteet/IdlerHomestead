-- Perennials (D183, #369): berry canes and an apple tree on the field. The tile card names the stage and when the
-- plant fruits, says to prune a picked plant and to wrap a young one before the freeze, and calls a resting plant
-- resting; a tap on a plant that wants pruning or wrapping sends the homesteader (the Prune and Wrap orders); a
-- sapling, a leafy young plant and a ripe tree look different on the ground. Plant state is set through the sim (a
-- scenario cannot wait for seasons); the taps and the camera are real.
local Crops = require("src.sim.systems.crops")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")

local function hasLine(lines, text)
  for _, l in ipairs(lines) do
    if l:find(text, 1, true) then
      return true
    end
  end
  return false
end

local function plantAt(d, dx, dy, id, fields)
  local x, y = d:freeTileNear(dx, dy)
  local world = d:world()
  local i = Grid.index(world.state.grid, x, y)
  local crop = Crops.newCrop(world, world.registry:get("crops", id))
  for k, v in pairs(fields or {}) do
    crop[k] = v
  end
  world.state.fields.tilled[i] = true
  world.state.fields.plan[i] = id
  world.state.crops[i] = crop
  return i, x, y
end

return function(d)
  d:newGame()
  local world = d:world()
  local scene = d:scene()
  d:advance(0.2)
  d:setSpeed(0)
  d:frames(3)

  -- Three plants in a row beside the start: a sapling, a young leafy plant and a ripe established tree.
  local sapling = plantAt(d, 2, 3, "berries")
  local young = plantAt(d, 4, 3, "apple", { stage = "first", seasons = 1, rest = true })
  local tree =
    plantAt(d, 6, 3, "apple", { stage = "mature", seasons = 5, winters = 1, rest = false, growth = 1, moisture = 1 })
  d:frames(6)
  d:shot("orchard")

  assert(hasLine(scene:tileInfo(sapling), "Sapling: small first crop in summer"), "a sapling says when it fruits")
  assert(hasLine(scene:tileInfo(sapling), "Berry canes: resting"), "and rests")
  assert(hasLine(scene:tileInfo(sapling), "Draws deer while young"), "and names what it draws")
  assert(hasLine(scene:tileInfo(sapling), "Wrap it before the first frost"), "and says to wrap it")
  assert(
    hasLine(scene:tileInfo(young), "Young: 40% crop in autumn, full after winter"),
    "a young plant says what it gives"
  )
  assert(hasLine(scene:tileInfo(young), "Draws deer and bear while young"), "an apple tree draws both")
  assert(hasLine(scene:tileInfo(tree), "Apple tree: ready"), "a ripe tree is ready")
  assert(hasLine(scene:tileInfo(tree), "Established: full crop in autumn"), "and established")
  scene.selected = sapling
  d:frames(12)
  d:shot("sapling_card")

  -- A picked plant wants pruning: the card says so, a tap sends the homesteader and the plant is pruned.
  world.state.crops[tree].growth, world.state.crops[tree].rest, world.state.crops[tree].pruneDue = 0, true, true
  assert(hasLine(scene:tileInfo(tree), "Needs pruning"), "a picked plant wants pruning")
  local x, y = Grid.coords(world.state.grid, tree)
  scene.selected = nil
  d:frames(2)
  d:clickTile(x, y)
  d:frames(4)
  d:setSpeed(1)
  d:advance(25)
  d:setSpeed(0)
  d:frames(4)
  assert(not world.state.crops[tree].pruneDue, "the homesteader pruned it")
  assert(not hasLine(scene:tileInfo(tree), "Needs pruning"), "and the card no longer asks")

  -- Wrapping: a tap on a young plant wraps it before the freeze, and the card says wrapped.
  local wx, wy = Grid.coords(world.state.grid, young)
  d:clickTile(wx, wy)
  d:frames(4)
  d:setSpeed(1)
  d:advance(25)
  d:setSpeed(0)
  d:frames(4)
  assert(world.state.crops[young].wrapped, "the homesteader wrapped it")
  assert(hasLine(scene:tileInfo(young), "Wrapped against the frost"), "the card says so")
  scene.selected = young
  d:frames(12)
  d:shot("wrapped_card")
  scene.selected = nil

  -- The Hoe's packets list the new seeds once they are in the store.
  Ledger.add(world, "seed_berries", 2)
  Ledger.add(world, "seed_apple", 1)
  d:frames(4)
  d:shot("seed_tray")
end
