-- Spoilage (GDD §7.2, D73): fresh food has a shelf life, tracked per batch.
--
-- Every harvest, catch or collection of a perishable becomes a batch with its own age. Nothing in a
-- batch spoils while it is younger than its food's shelf life (tuning.food.shelfLife); after that it
-- rots, tuning.food.rotShare of what is left each night. Preserved food (no shelf life) keeps.
--
-- The ledger stays the single source of truth for amounts. Batches only say how old the units the
-- ledger holds are, and they follow it: this system listens to "ledger.changed" for perishables, so
-- an increase becomes today's batch (merged with anything else added since last night) and a
-- decrease takes units from the oldest batch first. Every way food leaves the ledger (eating,
-- selling by truck or stand, preserving, the cat, mice) is therefore first in, first out without
-- those systems knowing batches exist. The sell crate (D31) is a count reserved on the same stock,
-- so moving food between pantry and crate never touches its age. If the two ever disagree (stock
-- added before this system subscribed, a test writing the ledger), `reconcile` trims the oldest
-- units or adds the missing ones as fresh.
--
-- Nightly (calendar.newDay) every batch ages by 1 / keeps (a powered freezer makes a night count
-- for less), then batches past their shelf life lose their share. Emits "food.spoiled"
-- { resource, category, amount } per resource and one "food.spoilReport" { lost, total } (D68).
--
-- State: world.state.spoilage = { batches = { [resourceId] = { { n = units, age = days }... } } },
-- oldest batch first; a resource with no stock has no entry.

local strict = require("src.core.strict")
local Ledger = require("src.sim.systems.ledger")
local Power = require("src.sim.systems.power")

local Spoilage = {}

local EPS = 1e-6 -- float slack for ages built from 1/keeps steps (not a balance value)

--- How much longer fresh food keeps right now (1 = normal). A powered chest freezer stretches it
--- (GDD §7.5); the effect eases in and out with the freezer's inertia.
function Spoilage.keeps(world)
  return 1 + Power.effect(world, "spoilSlow")
end

--- Base shelf life of a resource in days, or nil when it keeps (preserved food, non-food goods).
function Spoilage.shelfLife(world, id)
  local res = world.registry:get("resources", id)
  local cfg = world.tuning.food.shelfLife
  return strict.get(cfg.byResource, res.id) or strict.get(cfg.byCategory, res.category)
end

--- Does this resource spoil at all?
function Spoilage.perishable(world, id)
  return Spoilage.shelfLife(world, id) ~= nil
end

local function sum(list)
  local n = 0
  for _, b in ipairs(list) do
    n = n + b.n
  end
  return n
end

-- Add `n` units as today's batch (merged into the newest batch if it is from today).
local function addFresh(list, n)
  local last = list[#list]
  if last and last.age <= EPS then
    last.n = last.n + n
  else
    list[#list + 1] = { n = n, age = 0 }
  end
end

-- Take `n` units from the oldest batches first.
local function takeOldest(list, n)
  while n > EPS and #list > 0 do
    local b = list[1]
    if b.n <= n + EPS then
      n = n - b.n
      table.remove(list, 1)
    else
      b.n = b.n - n
      n = 0
    end
  end
end

-- Make `list` add up to `total`: missing units arrive fresh, extra units leave from the oldest.
local function fit(list, total)
  local have = sum(list)
  if have < total - EPS then
    addFresh(list, total - have)
  elseif have > total + EPS then
    takeOldest(list, have - total)
  end
end

local function store(world)
  return world.state.spoilage.batches
end

--- Bring a resource's batches in line with the ledger (mutates state; sim-side only).
function Spoilage.reconcile(world, id)
  if not Spoilage.perishable(world, id) then
    return
  end
  local batches = store(world)
  local list = batches[id] or {}
  fit(list, Ledger.get(world, id))
  batches[id] = #list > 0 and list or nil
end

-- The batches as they stand against the ledger, without changing state (for accessors the UI calls).
local function view(world, id)
  local list = store(world)[id] or {}
  local total = Ledger.get(world, id)
  if math.abs(sum(list) - total) <= EPS then
    return list
  end
  local copy = {}
  for i, b in ipairs(list) do
    copy[i] = { n = b.n, age = b.age }
  end
  fit(copy, total)
  return copy
end

--- A copy of a resource's batches, oldest first: { { n = units, age = days }... } (empty when none).
function Spoilage.batches(world, id)
  local out = {}
  if not Spoilage.perishable(world, id) then
    return out
  end
  for i, b in ipairs(view(world, id)) do
    out[i] = { n = b.n, age = b.age }
  end
  return out
end

-- Units of a batch of `n` past its shelf life that rot tonight.
local function rotOf(world, n)
  return math.min(n, math.max(1, math.ceil(n * world.tuning.food.rotShare - EPS)))
end

-- Units of `list` that rot tonight, and the units already past their shelf life.
local function tonightOf(world, list, life, step)
  local rot, past = 0, 0
  for _, b in ipairs(list) do
    if b.age > life + EPS then
      past = past + b.n
    end
    if b.age + step > life + EPS then
      rot = rot + rotOf(world, b.n)
    end
  end
  return rot, past
end

--- Everything the UI says about one resource's spoilage, or nil if it keeps:
--- { id, stock, shelfLife (days at today's keeps), batches (count), oldestAge (whole days),
---   daysLeft (whole days until the oldest batch starts to rot; 0 = tonight; nil without stock),
---   rotting (units already past their shelf life), tonight (units that rot tonight), warn }
function Spoilage.info(world, id)
  local life = Spoilage.shelfLife(world, id)
  if not life then
    return nil
  end
  local keeps = Spoilage.keeps(world)
  local step = 1 / keeps
  local list = view(world, id)
  local tonight, rotting = tonightOf(world, list, life, step)
  local oldest = list[1]
  local daysLeft
  if oldest then
    -- Nights until the oldest batch's age passes its shelf life (1 = tonight), less tonight itself.
    daysLeft = math.max(0, math.floor((life - oldest.age) / step + EPS))
  end
  return {
    id = id,
    stock = Ledger.get(world, id),
    shelfLife = life * keeps,
    batches = #list,
    oldestAge = oldest and math.floor(oldest.age * keeps + EPS) or nil,
    daysLeft = daysLeft,
    rotting = rotting,
    tonight = tonight,
    warn = tonight >= world.tuning.food.spoilWarnUnits,
  }
end

--- Info for every perishable in stock, in content order, plus the units that rot tonight and whether
--- any of them is worth a warning: { list = { info... }, units = n, warn = bool }.
function Spoilage.tonight(world)
  local list, total, warn = {}, 0, false
  for _, res in ipairs(world.registry:all("resources")) do
    if Ledger.get(world, res.id) > 0 and Spoilage.perishable(world, res.id) then
      local info = Spoilage.info(world, res.id)
      list[#list + 1] = info
      total = total + info.tonight
      warn = warn or info.warn
    end
  end
  return { list = list, units = total, warn = warn }
end

--- What slows spoilage, as the code really treats it:
--- { freezer = "none"|"off"|"on", keeps, preserves = { [category] = true } }
--- Only a powered freezer stretches shelf lives (pantry vs crate, season and a "preserve" pin make no
--- difference); a placed processor (the smoker) turns a category into preserved food, which never spoils.
function Spoilage.slowing(world)
  local freezer = "none"
  for _, obj in pairs(world.state.grid.objects) do
    local sink = world.registry:get("objects", obj.id).sink
    if sink and sink.effects and sink.effects.spoilSlow then
      freezer = Power.effect(world, "spoilSlow") > 0 and "on" or "off"
      break
    end
  end
  local preserves = {}
  local stations = {}
  for _, obj in pairs(world.state.grid.objects) do
    local station = world.registry:get("objects", obj.id).station
    if station then
      stations[station] = true
    end
  end
  for _, recipe in ipairs(world.registry:all("recipes")) do
    if stations[recipe.station] then
      preserves[recipe.inputCategory] = true
    end
  end
  return { freezer = freezer, keeps = Spoilage.keeps(world), preserves = preserves }
end

--- Age a resource's stock by `days` (tests, tools and the screenshot driver; the sim ages it nightly).
function Spoilage.ageStock(world, id, days)
  Spoilage.reconcile(world, id)
  for _, b in ipairs(store(world)[id] or {}) do
    b.age = b.age + days
  end
end

--- The night's spoilage: age every batch, then rot what is past its shelf life.
function Spoilage.daily(world)
  local step = 1 / Spoilage.keeps(world)
  local batches = store(world)
  local lost, total = {}, 0
  for _, res in ipairs(world.registry:all("resources")) do
    local life = Spoilage.shelfLife(world, res.id)
    if life then
      Spoilage.reconcile(world, res.id)
      local list = batches[res.id]
      local spoiled = 0
      for _, b in ipairs(list or {}) do
        b.age = b.age + step
        if b.age > life + EPS then
          local rot = rotOf(world, b.n)
          b.n = b.n - rot
          spoiled = spoiled + rot
        end
      end
      if spoiled > 0 then
        local kept = {}
        for _, b in ipairs(list) do
          if b.n > EPS then
            kept[#kept + 1] = b
          end
        end
        batches[res.id] = #kept > 0 and kept or nil
        -- The batches already lost these units; the "spoiled" change is not taken from them again.
        Ledger.remove(world, res.id, spoiled, "spoiled")
        world.events:emit("food.spoiled", { resource = res.id, category = res.category, amount = spoiled })
        lost[#lost + 1] = { resource = res.id, amount = spoiled }
        total = total + spoiled
      end
    end
  end
  if total > 0 then
    world.events:emit("food.spoilReport", { lost = lost, total = total })
  end
end

function Spoilage.init(world)
  world.state.spoilage = world.state.spoilage or { batches = {} }
  world.events:on("ledger.changed", function(e)
    if e.reason == "spoiled" or not Spoilage.perishable(world, e.id) then
      return
    end
    local batches = store(world)
    local list = batches[e.id] or {}
    if e.delta > 0 then
      addFresh(list, e.delta)
    else
      takeOldest(list, -e.delta)
    end
    fit(list, e.total)
    batches[e.id] = #list > 0 and list or nil
  end)
  world.events:on("calendar.newDay", function()
    Spoilage.daily(world)
  end)
  -- Stock added before this system subscribed (the starting kit) arrives as today's batch.
  for _, res in ipairs(world.registry:all("resources")) do
    if Spoilage.perishable(world, res.id) then
      Spoilage.reconcile(world, res.id)
    end
  end
end

return Spoilage
