-- The dusk check's fixes (D161, #340, docs/PLAN_DEPTH.md §3.1): for each gap the Tonight card shows
-- (Readiness.tonight), one tap that issues ordinary orders and nothing new:
--
--   warmth  "chop": mark the trees and logs nearest the homesteader as Axe marks (Marks, D147) until their wood
--           would lift the stock to the alert's amber line; with no fire placed "place_fire" and with no tree
--           in reach "buy_wood" point at the Catalog and the town menu instead (kind "open").
--   food    "fish": switch the routine's Fish category on and put it first; the scene hands over to the routine.
--           With no rod it points at the Pantry ("open").
--   water   "fill": order the homesteader to the nearest creek bank or well to fill the canteen, or to melt snow at
--           a fire; with neither in reach it points at the Catalog ("open").
--
-- `Dusk.fixes` only reads, so the card can ask every frame; `Dusk.apply` issues the order. No state of its own: the
-- marks, priorities and the homesteader's order live with their systems.

local Actors = require("src.sim.systems.actors")
local Fishing = require("src.sim.systems.fishing")
local Grid = require("src.sim.grid")
local Marks = require("src.sim.systems.marks")
local Readiness = require("src.sim.systems.readiness")
local Tasks = require("src.sim.systems.tasks")

local Dusk = {}

-- Wood an object yields on average (a yield is a number or a { min, max } range).
local function woodOf(def)
  local y = def.yields and def.yields.wood
  if type(y) == "table" then
    return (y[1] + y[2]) / 2
  end
  return y or 0
end

-- Wood the Axe marks already standing will bring in.
local function pendingWood(world)
  local total = 0
  for _, anchor in ipairs(Marks.list(world, "clear")) do
    local obj = world.state.grid.objects[anchor]
    if obj then
      total = total + woodOf(world.registry:get("objects", obj.id))
    end
  end
  return total
end

-- Squared distance from the homesteader to tile i.
local function distance(world, i)
  local hs = Actors.homesteader(world)
  local x, y = Grid.coords(world.state.grid, i)
  return (x - hs.x) ^ 2 + (y - hs.y) ^ 2
end

-- Trees and logs that would bring wood and carry no mark yet: { { anchor, wood } } nearest first, up to `wanted` wood
-- (or `tuning.night.fix.maxMarks` of them), and the wood they hold.
local function chopTargets(world, wanted)
  local found = {}
  for anchor, obj in pairs(world.state.grid.objects) do
    local def = world.registry:get("objects", obj.id)
    if
      def.chop
      and woodOf(def) > 0
      and not Marks.has(world, "clear", anchor)
      and Marks.target(world, "clear", anchor)
    then
      found[#found + 1] = { anchor = anchor, wood = woodOf(def), d = distance(world, anchor) }
    end
  end
  table.sort(found, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    return a.anchor < b.anchor
  end)
  local picked, total = {}, 0
  for _, t in ipairs(found) do
    if total >= wanted or #picked >= world.tuning.night.fix.maxMarks then
      break
    end
    picked[#picked + 1] = t
    total = total + t.wood
  end
  return picked, total
end

-- Where the canteen can be filled or snow melted: the tiles the two water tasks offer, nearest first.
local function drinkTargets(world)
  local hs = Actors.homesteader(world)
  local found = {}
  for _, id in ipairs({ "fetch_drinking", "melt_snow" }) do
    local task = Tasks.get(world, id)
    task.candidates(world, hs, function(i)
      found[#found + 1] = { tile = i, d = distance(world, i) }
    end)
  end
  table.sort(found, function(a, b)
    if a.d ~= b.d then
      return a.d < b.d
    end
    return a.tile < b.tile
  end)
  return found
end

--- The fixes for the gaps of `tonight` (Readiness.tonight; read here when omitted): a list of
---   { gap = "warmth" | "food" | "water", id, kind = "order" | "open", book = "catalog" | "truck" | "pantry" (open),
---     count, wood (chop: trees to mark, the wood they hold), short (chop: wood still wanted),
---     queued (chop: the marks already standing cover the gap) }
function Dusk.fixes(world, tonight)
  tonight = tonight or Readiness.tonight(world)
  local list = {}
  local warmth = tonight.warmth
  if warmth.noFire and warmth.need > 0 then
    list[#list + 1] = { gap = "warmth", id = "place_fire", kind = "open", book = "catalog" }
  elseif warmth.level > 0 then
    local line = world.tuning.alerts.fuelAmberNights
    local pending = pendingWood(world)
    local short = math.ceil(line * warmth.perNight - warmth.wood - pending - 1e-9)
    if short <= 0 then
      list[#list + 1] =
        { gap = "warmth", id = "chop", kind = "order", queued = true, count = Marks.count(world, "clear") }
    else
      local picked, wood = chopTargets(world, short)
      if #picked == 0 then
        list[#list + 1] = { gap = "warmth", id = "buy_wood", kind = "open", book = "truck" }
      else
        list[#list + 1] = { gap = "warmth", id = "chop", kind = "order", count = #picked, wood = wood, short = short }
      end
    end
  end
  if tonight.food.level > 0 then
    if Fishing.hasRod(world) then
      list[#list + 1] = { gap = "food", id = "fish", kind = "order" }
    else
      list[#list + 1] = { gap = "food", id = "open_pantry", kind = "open", book = "pantry" }
    end
  end
  if tonight.water.level > 0 then
    if #drinkTargets(world) > 0 then
      list[#list + 1] = { gap = "water", id = "fill", kind = "order" }
    else
      list[#list + 1] = { gap = "water", id = "find_water", kind = "open", book = "catalog" }
    end
  end
  return list
end

--- Issue the order of fix `id`. Returns true and a result (chop: marks added; fill: the task verb), or false.
function Dusk.apply(world, id)
  if id == "chop" then
    local tonight = Readiness.tonight(world)
    local line = world.tuning.alerts.fuelAmberNights
    local short = math.ceil(line * tonight.warmth.perNight - tonight.warmth.wood - pendingWood(world) - 1e-9)
    local picked = chopTargets(world, math.max(short, 0))
    local anchors = {}
    for _, t in ipairs(picked) do
      anchors[#anchors + 1] = t.anchor
    end
    local added = Marks.add(world, "clear", anchors)
    return added > 0, added
  elseif id == "fish" then
    Tasks.setPriorityEnabled(world, "fish", true)
    for _ = 1, #world.registry:all("task_categories") do
      Tasks.movePriority(world, "fish", -1)
    end
    return true
  elseif id == "fill" then
    local hs = Actors.homesteader(world)
    for _, t in ipairs(drinkTargets(world)) do
      local task = Actors.order(world, hs, t.tile, { categories = { water = true } })
      if task then
        return true, task.verb
      end
    end
    return false
  end
  return false
end

return Dusk
