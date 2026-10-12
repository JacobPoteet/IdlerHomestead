-- Mice and the cat (GDD §7.7, D54).
--
-- Mice: once a night (tuning.cat.mice.raidHour) a roll from the seeded stream "mice" may bring a
-- raid, more likely in autumn and winter and in rough weather. A raid ruins some units of stored
-- fresh food through the ledger (reason "mice"). With a cat, each raid is caught with a
-- probability that depends on whether the cat is fed and how fond it is of the homesteader.
--
-- The cat: owning the equipment item Cat.ITEM (the catalog's shelter cat, or the stray cat find)
-- brings it to the homestead. It is not an actor of the task board: it wanders near the spawn,
-- naps in sunny spots by day, sleeps by the shelter at night and in bad weather, and can be
-- petted (Cat.pet). It eats fish from the ledger once a day; with none it is hungry and catches
-- less, but never leaves or starves (idle-friendly). Its wandering uses the seeded stream "cat".
--
-- State: world.state.cat = { here, x, y, prevX, prevY, mode ("walk" | "sit" | "nap" | "sleep"),
--   timer (game seconds left in a rest), path (tile indices), napGoal (bool), fed, lastFed,
--   bond, petDay, pets, caught, raidDay (day of the last raid roll), raids, lost }
-- Emits "cat.arrived" { day }, "cat.petted" { day, bond }, "mice.raided" { day, lost = { id = n }, units },
-- "mice.caught" { day }.

local Calendar = require("src.sim.systems.calendar")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Pathfind = require("src.sim.pathfind")
local Weather = require("src.sim.systems.weather")

local Cat = {}

--- The catalog equipment id that means "this run has a cat".
Cat.ITEM = "shelter_cat"

function Cat.init(world)
  local state = world.state
  state.cat = state.cat or {}
  local c = state.cat
  if c.here == nil then
    c.here = false
  end
  c.mode = c.mode or "sit"
  c.timer = c.timer or 0
  c.path = c.path or {}
  if c.fed == nil then
    c.fed = true
  end
  c.lastFed = c.lastFed or 0
  c.bond = c.bond or 0
  c.petDay = c.petDay or 0
  c.pets = c.pets or 0
  c.caught = c.caught or 0
  c.raidDay = c.raidDay or 0
  c.raids = c.raids or 0
  c.lost = c.lost or 0
  if c.here then
    c.prevX, c.prevY = c.x, c.y
  end
end

--- Does this run have a cat (it may take until the next tick to appear)?
function Cat.owned(world)
  return Inventory.hasEquipment(world, Cat.ITEM)
end

--- Is the cat on the homestead?
function Cat.present(world)
  return world.state.cat.here == true
end

--- The cat's position for drawing: x, y, prevX, prevY (tile coordinates), mode; nil when absent.
function Cat.position(world)
  local c = world.state.cat
  if not c.here then
    return nil
  end
  return c.x, c.y, c.prevX or c.x, c.prevY or c.y, c.mode
end

--- Tile index the cat is on, or nil when absent.
function Cat.tile(world)
  local c = world.state.cat
  if not c.here then
    return nil
  end
  return Grid.index(world.state.grid, math.floor(c.x + 0.5), math.floor(c.y + 0.5))
end

--- Is the cat on tile i?
function Cat.at(world, i)
  return Cat.tile(world) == i
end

--- Cat facts for the UI: { fed, bond, pets, caught, petToday }.
function Cat.info(world)
  local c = world.state.cat
  return { fed = c.fed, bond = c.bond, pets = c.pets, caught = c.caught, petToday = c.petDay == Calendar.now(world).day }
end

--- Probability that the cat catches the next raid (0 with no cat).
function Cat.catchChance(world)
  local c, cfg = world.state.cat, world.tuning.cat.cat
  if not c.here then
    return 0
  end
  local base = c.fed and cfg.fedCatch or cfg.hungryCatch
  return math.min(1, base + c.bond * cfg.bondCatch)
end

--- Probability that mice come tonight (before the cat), from season and weather.
function Cat.raidChance(world)
  local cfg = world.tuning.cat.mice
  local p = cfg.chancePerDay * cfg.seasons[Calendar.now(world).season] * Weather.threat(world)
  return math.min(1, p)
end

--- Pet the cat. Once a day it also grows fonder (up to tuning.cat.cat.maxBond), which helps it
--- catch mice. Returns true, or false + reason.
function Cat.pet(world)
  local c = world.state.cat
  if not c.here then
    return false, "no cat"
  end
  local day = Calendar.now(world).day
  if c.petDay ~= day then
    c.petDay = day
    c.bond = math.min(world.tuning.cat.cat.maxBond, c.bond + 1)
  end
  c.pets = c.pets + 1
  world.events:emit("cat.petted", { day = day, bond = c.bond })
  return true
end

-- Sunny: open ground with no tree within shadeRadius tiles.
local function sunny(world, i)
  if not Grid.walkable(world, i) then
    return false
  end
  local grid = world.state.grid
  local x, y = Grid.coords(grid, i)
  local r = world.tuning.cat.cat.shadeRadius
  for dy = -r, r do
    for dx = -r, r do
      if Grid.inBounds(grid, x + dx, y + dy) then
        local obj = Grid.object(world, Grid.index(grid, x + dx, y + dy))
        if obj and obj.id == "tree" then
          return false
        end
      end
    end
  end
  return true
end

-- Rain or snow keeps the cat in.
local function wet(world)
  return Weather.current(world).rainfall > 0
end

local function between(rng, range)
  return rng:range(range.min, range.max)
end

local function startPath(world, c, goal)
  local start = Cat.tile(world)
  c.path = Pathfind.find(
    world,
    start,
    function(i)
      return i == goal
    end,
    goal
  ) or {}
  return #c.path > 0
end

-- Decide what to do next: shelter at night and in bad weather, else a sunny spot or a stroll.
local function choose(world, c)
  local cfg = world.tuning.cat.cat
  local rng = world:rng("cat")
  local grid = world.state.grid
  local home = Land.spawn(world)
  c.napGoal = false
  local goal, rest = nil, "sit"
  if Calendar.isNight(world) then
    goal, rest = home, "sleep"
  elseif wet(world) then
    goal, rest = home, "nap"
  else
    local hx, hy = Grid.coords(grid, home)
    local wantNap = rng:chance(cfg.napChance)
    local tries = wantNap and cfg.sunnyTries or 1
    for _ = 1, tries do
      local x, y = hx + rng:int(-cfg.wanderRadius, cfg.wanderRadius), hy + rng:int(-cfg.wanderRadius, cfg.wanderRadius)
      if Grid.inBounds(grid, x, y) then
        local i = Grid.index(grid, x, y)
        if Grid.walkable(world, i) and not Grid.object(world, i) and (not wantNap or sunny(world, i)) then
          goal, rest = i, wantNap and "nap" or "sit"
          break
        end
      end
    end
  end
  c.rest = rest
  if goal and goal ~= Cat.tile(world) and Grid.walkable(world, goal) and startPath(world, c, goal) then
    c.mode = "walk"
    return
  end
  -- Already there (or no way): rest where it stands.
  c.mode = rest
  c.timer = between(rng, rest == "sit" and cfg.idleSeconds or cfg.napSeconds)
end

local function arrive(world, c)
  local grid = world.state.grid
  local x, y = Grid.coords(grid, Land.spawn(world))
  c.here = true
  c.x, c.y, c.prevX, c.prevY = x, y, x, y
  c.mode, c.timer, c.path = "sit", 0, {}
  c.fed, c.lastFed = true, Calendar.now(world).day
  world.events:emit("cat.arrived", { day = Calendar.now(world).day })
end

local function walk(world, c, dt)
  local grid = world.state.grid
  local remaining = world.tuning.cat.cat.walkSpeed * dt
  while remaining > 0 and #c.path > 0 do
    local nextTile = c.path[1]
    if not Grid.walkable(world, nextTile) then
      c.path = {} -- something now blocks the way; decide again
      return
    end
    local tx, ty = Grid.coords(grid, nextTile)
    local dx, dy = tx - c.x, ty - c.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local step = remaining / Grid.walkCost(world, nextTile)
    if step >= dist then
      c.x, c.y = tx, ty
      table.remove(c.path, 1)
      remaining = remaining - dist * Grid.walkCost(world, nextTile)
    else
      c.x, c.y = c.x + dx / dist * step, c.y + dy / dist * step
      remaining = 0
    end
  end
end

-- The cat eats one meal a day: the cheapest stocked fish goes first.
local function feed(world, c)
  local cfg = world.tuning.cat.cat
  local kinds = {}
  for _, category in ipairs(cfg.mealCategories) do
    kinds[category] = true
  end
  local best
  for _, res in ipairs(world.registry:all("resources")) do
    if kinds[res.category] and Ledger.get(world, res.id) >= cfg.mealUnits then
      if not best or (res.value or 0) < (best.value or 0) then
        best = res
      end
    end
  end
  c.lastFed = Calendar.now(world).day
  c.fed = best ~= nil and Ledger.remove(world, best.id, cfg.mealUnits, "cat")
end

--- Roll tonight's raid now. Returns "caught", "raided" or nil (no mice, or nothing to eat).
function Cat.raid(world)
  local c, cfg = world.state.cat, world.tuning.cat.mice
  local rng = world:rng("mice")
  local day = Calendar.now(world).day
  c.raidDay = day
  -- Always draw both rolls so the stream does not depend on the stores or the cat.
  local hit = rng:chance(Cat.raidChance(world))
  local catchRoll = rng:float()
  if not hit or day < cfg.firstDay then
    return nil
  end
  local targets = {}
  for _, category in ipairs(cfg.targetCategories) do
    targets[category] = true
  end
  local stock, total = {}, 0
  for _, res in ipairs(world.registry:all("resources")) do
    local n = targets[res.category] and math.floor(Ledger.get(world, res.id)) or 0
    if n > 0 then
      stock[#stock + 1] = { id = res.id, n = n }
      total = total + n
    end
  end
  if total == 0 then
    return nil
  end
  c.raids = c.raids + 1
  if catchRoll < Cat.catchChance(world) then
    c.caught = c.caught + 1
    world.events:emit("mice.caught", { day = day })
    return "caught"
  end
  local units = math.min(total, math.max(cfg.minLoss, math.min(cfg.maxLoss, math.floor(total * cfg.lossFraction))))
  local lost = {}
  for _ = 1, units do
    local entry = rng:weighted(stock, function(e)
      return e.n
    end)
    Ledger.remove(world, entry.id, 1, "mice")
    entry.n = entry.n - 1
    lost[entry.id] = (lost[entry.id] or 0) + 1
    if entry.n == 0 then
      for i, e in ipairs(stock) do
        if e == entry then
          table.remove(stock, i)
          break
        end
      end
    end
  end
  c.lost = c.lost + units
  world.events:emit("mice.raided", { day = day, lost = lost, units = units })
  return "raided"
end

function Cat.tick(world, dt)
  local c = world.state.cat
  local now = Calendar.now(world)
  if not c.here then
    if Cat.owned(world) then
      arrive(world, c)
    end
  else
    c.prevX, c.prevY = c.x, c.y
    if now.hour >= world.tuning.cat.cat.feedHour and c.lastFed < now.day then
      feed(world, c)
    end
    if c.mode == "walk" then
      walk(world, c, dt)
      if #c.path == 0 then
        c.mode = c.rest or "sit"
        local cfg = world.tuning.cat.cat
        c.timer = between(world:rng("cat"), c.mode == "sit" and cfg.idleSeconds or cfg.napSeconds)
      end
    else
      c.timer = c.timer - dt
      -- Night falls or the rain starts: stop napping in the open.
      if c.timer <= 0 or (c.mode ~= "sleep" and Calendar.isNight(world)) then
        choose(world, c)
      end
    end
  end
  if now.hour >= world.tuning.cat.mice.raidHour and c.raidDay < now.day then
    Cat.raid(world)
  end
end

return Cat
