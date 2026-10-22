-- The farm dog (C4, #358, D189, docs/PLAN_DEPTH.md §6.1, §10.3). A companion that keeps watch over the night threats.
--
-- Owning the equipment item Dog.ITEM (the catalog's farm dog, or the stray dog find) brings the dog; it arrives at the
-- spawn point on the next tick. Like the cat it is not an actor of the task board: it lies near the spawn point (the first
-- free tile within `postRadius`), asleep at night and in rain, and it needs nothing from the player.
--
-- UPKEEP, WITHOUT A CHORE. Once a day at `feedHour` the dog eats `mealUnits` of the cheapest stocked food (or fish) through
-- the food ledger (reason "dog"); there is no feed to buy and nothing to tap. THE MERCY RULE: it eats only when the
-- homesteader would still hold `keepFoodDays` days of food afterwards; otherwise it goes hungry, which only halves
-- its guard (`hungryScale`). It never leaves, never starves and never takes a meal the homesteader needs. A dog that is fed
-- every day costs about one cheap unit of food.
--
-- WHAT IT GUARDS. `Dog.guard(world, threatId)` is the chance the dog turns that threat aside, added to the threat's own
-- guard roll (the raiders' counters, the coop door and fence), listed per threat in tuning.dog.guards. The mice are not
-- listed: they are the cat's, so the two companions do not duplicate. The Tonight card's exposure word counts the dog too
-- (tuning.night.exposure.guards), lowering the chance of the threats it covers.
--
-- State: world.state.dog = { here, x, y, fed, lastFed, meals, hungry }
-- Emits "dog.arrived" { day }, "dog.fed" { day, id }, "dog.hungry" { day }.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Weather = require("src.sim.systems.weather")

local Dog = {}

--- The catalog equipment id that means "this run has a dog".
Dog.ITEM = "farm_dog"

function Dog.init(world)
  local state = world.state
  state.dog = state.dog or {}
  local d = state.dog
  if d.here == nil then
    d.here = false
  end
  if d.fed == nil then
    d.fed = true
  end
  d.lastFed = d.lastFed or 0
  d.meals = d.meals or 0
  d.hungry = d.hungry or 0
end

--- Does this run have a dog (it may take until the next tick to appear)?
function Dog.owned(world)
  return Inventory.hasEquipment(world, Dog.ITEM)
end

--- Is the dog on the homestead?
function Dog.present(world)
  return world.state.dog.here == true
end

--- Is the dog fed (it ate at its last mealtime, or has not yet had one)?
function Dog.fed(world)
  return world.state.dog.fed == true
end

--- The chance (0..1) the dog turns `threatId` aside: its listed guard, halved while hungry; 0 with no dog or for a threat
--- it does not cover.
function Dog.guard(world, threatId)
  local d, cfg = world.state.dog, world.tuning.dog
  if not d.here then
    return 0
  end
  local g = rawget(cfg.guards, threatId) or 0
  return d.fed and g or g * cfg.hungryScale
end

--- Does the dog cover this threat?
function Dog.covers(world, threatId)
  return (rawget(world.tuning.dog.guards, threatId) or 0) > 0
end

--- Dog facts for the UI: { fed, meals, hungry (days it went without) }.
function Dog.info(world)
  local d = world.state.dog
  return { fed = d.fed, meals = d.meals, hungry = d.hungry }
end

--- The dog's position for drawing: x, y (tile coordinates) and mode ("sit" | "sleep"); nil when absent.
function Dog.position(world)
  local d = world.state.dog
  if not d.here then
    return nil
  end
  local asleep = Calendar.isNight(world) or Weather.current(world).rainfall > 0
  return d.x, d.y, asleep and "sleep" or "sit"
end

-- The tile nearest the spawn point (within postRadius, not the spawn tile itself) that is walkable and has nothing on it.
local function findPost(world)
  local grid, cfg = world.state.grid, world.tuning.dog
  local sx, sy = Grid.coords(grid, Land.spawn(world))
  for r = 1, cfg.postRadius do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r and Grid.inBounds(grid, sx + dx, sy + dy) then
          local i = Grid.index(grid, sx + dx, sy + dy)
          if Grid.walkable(world, i) and not Grid.object(world, i) then
            return sx + dx, sy + dy
          end
        end
      end
    end
  end
  return sx, sy
end

-- Is the dog's tile still free (a building may have been placed on it)?
local function postFree(world, d)
  local i = Grid.index(world.state.grid, d.x, d.y)
  return Grid.walkable(world, i) and not Grid.object(world, i)
end

-- The dog eats one meal a day: the cheapest stocked food, and only down to the homesteader's reserve.
local function feed(world, d)
  local cfg = world.tuning.dog
  local kinds = {}
  for _, category in ipairs(cfg.mealCategories) do
    kinds[category] = true
  end
  local keep = cfg.keepFoodDays * world.tuning.needs.dailyCalories
  local calories = Needs.calories(world)
  local best
  for _, res in ipairs(world.registry:all("resources")) do
    if
      kinds[res.category]
      and (res.calories or 0) > 0
      and Ledger.get(world, res.id) >= cfg.mealUnits
      and calories - cfg.mealUnits * res.calories >= keep
      and (not best or (res.value or 0) < (best.value or 0))
    then
      best = res
    end
  end
  local day = Calendar.now(world).day
  d.lastFed = day
  d.fed = best ~= nil and Ledger.remove(world, best.id, cfg.mealUnits, "dog")
  if d.fed then
    d.meals = d.meals + 1
    world.events:emit("dog.fed", { day = day, id = best.id })
  else
    d.hungry = d.hungry + 1
    world.events:emit("dog.hungry", { day = day })
  end
end

local function arrive(world, d)
  d.here = true
  d.x, d.y = findPost(world)
  d.fed, d.lastFed = true, Calendar.now(world).day
  world.events:emit("dog.arrived", { day = d.lastFed })
end

function Dog.tick(world)
  local d = world.state.dog
  if not d.here then
    if Dog.owned(world) then
      arrive(world, d)
    end
    return
  end
  if not postFree(world, d) then
    d.x, d.y = findPost(world)
  end
  local now = Calendar.now(world)
  if now.hour >= world.tuning.dog.feedHour and d.lastFed < now.day then
    feed(world, d)
  end
end

return Dog
