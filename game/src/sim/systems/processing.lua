-- Processing (GDD §5.3, §6.2): stations such as the smoker turn fresh food into preserved food.
-- Loading a station is a task (category "process"); the batch then runs on its own for the
-- recipe's hours and the output goes straight into stock.
--
-- State: world.state.processing = { [anchor] = { recipe, count, remaining } } for running batches.
-- Emits "processing.started" { recipe, tile, count }, "processing.done" { recipe, tile, output, count }
-- (count = units that went into stock; a batch that doesn't fit is delivered in parts) and
-- "processing.blocked" { recipe, tile, output, count } once when finished output is waiting for room,
-- and "processing.discarded" { recipe, tile, output, count } when the player throws that output away (D93).

local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Food = require("src.sim.systems.food")
local Market = require("src.sim.systems.market")
local Tasks = require("src.sim.systems.tasks")

local Processing = {}

local function recipeFor(world, anchor)
  local obj = world.state.grid.objects[anchor]
  if not obj then
    return nil
  end
  local station = world.registry:get("objects", obj.id).station
  if not station then
    return nil
  end
  for _, recipe in ipairs(world.registry:all("recipes")) do
    if recipe.station == station then
      return recipe
    end
  end
  return nil
end

-- Units available to process: inputs of the right category inside their keep target (D75: the
-- automatic keep holds fresh food for a placed processor while the winter stock is short; surplus
-- waits for the stand and the truck) and not loaded on the truck.
local function inputs(world, recipe)
  local list, total = {}, 0
  local keep
  for _, res in ipairs(world.registry:all("resources")) do
    if res.category == recipe.inputCategory and Ledger.get(world, res.id) > 0 then
      keep = keep or Food.keeps(world)
      local stock = Ledger.get(world, res.id)
      local n = math.min(stock, keep[res.id] or 0, stock - Market.loaded(world, res.id))
      if n > 0 then
        list[#list + 1] = { id = res.id, n = n }
        total = total + n
      end
    end
  end
  return list, total
end

-- Output units a load of up to `recipe.batch` of `available` input units makes (`yield` per input
-- unit, default 1; whole units only, so a recipe that halves needs an even number of inputs).
local function makes(recipe, available)
  return math.floor(math.min(available, recipe.batch) * (recipe.yield or 1) + 1e-9)
end

local function canLoad(world, anchor)
  local recipe = recipeFor(world, anchor)
  if not recipe or world.state.processing[anchor] then
    return false
  end
  local _, total = inputs(world, recipe)
  return makes(recipe, total) > 0 and Ledger.canAfford(world, recipe.fuel or {})
end

--- Is a batch running at this station? Returns the batch or nil.
function Processing.batch(world, anchor)
  return world.state.processing[anchor]
end

--- Finished batches still sitting in their station for lack of storage room, sorted by anchor:
--- list of { tile, recipe, output, count }.
function Processing.blockedBatches(world)
  local list = {}
  for anchor, batch in pairs(world.state.processing) do
    if batch.blocked then
      local recipe = world.registry:get("recipes", batch.recipe)
      list[#list + 1] = { tile = anchor, recipe = recipe.id, output = recipe.output, count = batch.count }
    end
  end
  table.sort(list, function(a, b)
    return a.tile < b.tile
  end)
  return list
end

--- Throw away the finished output waiting in a station for room (D93, #135), freeing the station.
--- Whatever fits already went into stock each tick, so this is only the remainder. Returns the number
--- of units discarded, or nil when the station holds no blocked batch.
--- Emits "processing.discarded" { recipe, tile, output, count }.
function Processing.discard(world, anchor)
  local batch = world.state.processing[anchor]
  if not batch or not batch.blocked then
    return nil
  end
  local recipe = world.registry:get("recipes", batch.recipe)
  world.state.processing[anchor] = nil
  world.events:emit(
    "processing.discarded",
    { recipe = recipe.id, tile = anchor, output = recipe.output, count = batch.count }
  )
  return batch.count
end

--- Drop whatever batch the station at `anchor` holds, running or waiting (its station was destroyed, D110).
--- Returns the batch or nil.
function Processing.scrap(world, anchor)
  local batch = world.state.processing[anchor]
  world.state.processing[anchor] = nil
  return batch
end

--- Carry the batch of the station at `from` to the station now at `to` (it was moved, D98).
function Processing.relocate(world, from, to)
  local batches = world.state.processing
  batches[to], batches[from] = batches[from], nil
end

function Processing.init(world)
  world.state.processing = world.state.processing or {}
  Tasks.register(world, {
    id = "load_station",
    category = "process",
    verb = "Load",
    clickOrder = 25,
    candidates = function(w, _, add)
      for anchor in pairs(w.state.grid.objects) do
        if canLoad(w, anchor) then
          add(anchor)
        end
      end
    end,
    canDo = function(w, _, i)
      local _, anchor = Grid.object(w, i)
      return anchor ~= nil and canLoad(w, anchor)
    end,
    workTime = function(w)
      return w.tuning.food.loadStationTime
    end,
    complete = function(w, _, i)
      local _, anchor = Grid.object(w, i)
      local recipe = recipeFor(w, anchor)
      if not recipe or not Ledger.spend(w, recipe.fuel or {}, "fuel") then
        return
      end
      local list, total = inputs(w, recipe)
      local count = makes(recipe, total) -- output units; `batch.count` is what will be delivered
      local want = math.ceil(count / (recipe.yield or 1) - 1e-9) -- input units that make them
      local taken = 0
      for _, input in ipairs(list) do
        local take = math.min(input.n, want - taken)
        if take > 0 then
          Ledger.remove(w, input.id, take, "process")
          taken = taken + take
        end
      end
      w.state.processing[anchor] = {
        recipe = recipe.id,
        count = count,
        remaining = recipe.hours * w.tuning.time.dayLength / 24,
      }
      w.events:emit("processing.started", { recipe = recipe.id, tile = anchor, count = count })
    end,
  })
end

function Processing.tick(world, dt)
  for anchor, batch in pairs(world.state.processing) do
    batch.remaining = math.max(0, batch.remaining - dt)
    if batch.remaining <= 0 then
      local recipe = world.registry:get("recipes", batch.recipe)
      -- Whatever fits goes into stock; the rest waits in the station (and keeps it busy)
      -- until there is room, so a full store never swallows a finished batch.
      local moved = Ledger.add(world, recipe.output, batch.count, "processed")
      batch.count = batch.count - moved
      if moved > 0 then
        world.events:emit(
          "processing.done",
          { recipe = recipe.id, tile = anchor, output = recipe.output, count = moved }
        )
      end
      if batch.count <= 0 then
        world.state.processing[anchor] = nil
      elseif not batch.blocked then
        batch.blocked = true
        world.events:emit(
          "processing.blocked",
          { recipe = recipe.id, tile = anchor, output = recipe.output, count = batch.count }
        )
      end
    end
  end
end

return Processing
