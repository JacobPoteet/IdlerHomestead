-- Starting loadouts (D201, #386): five bundles of existing items, each with a small penalty, unlocked by the Journal and
-- chosen on the recovery screen. Optional: the standard start is the default. Also the camp start perk (#215).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local Run = require("src.meta.run")
local World = require("src.sim.world")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Land = require("src.sim.systems.land")
local Perks = require("src.sim.systems.perks")
local Power = require("src.sim.systems.power")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local ctx = { registry = reg, tuning = tun }
local IDS = { "angler", "gardener", "herder", "lumberjack", "tinkerer" }

local function session(data, seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = seed })
end

-- A fresh run state with the loadout chosen (nil: the standard start), on a slot whose meta is `meta`.
local function start(loadout, meta, seed)
  local data = Save.newSlotData("Kit")
  data.meta = meta or data.meta
  data.run = World.newState(seed or 9)
  data.run.loadout = loadout
  return session(data).world
end

local function count(world, id)
  local n = 0
  for _, obj in pairs(world.state.grid.objects) do
    if obj.id == id then
      n = n + 1
    end
  end
  return n
end

T.test("loadouts: the five bundles exist, each with a Journal unlock and a small penalty", function()
  local seen = {}
  for _, def in ipairs(reg:all("loadouts")) do
    seen[def.id] = true
    T.truthy(Journal.kindOf({ registry = reg }, def.unlock), def.id .. " names a Journal node")
    T.truthy(next(def.penalty), def.id .. " has a penalty")
    T.truthy(def.penaltyLine ~= "")
    for id in pairs(def.startingResources or {}) do
      T.truthy(reg:has("resources", id), id)
    end
    for id in pairs(def.penalty) do
      T.truthy(reg:has("resources", id), id)
    end
    for _, id in ipairs(def.startingObjects or {}) do
      T.truthy(reg:has("objects", id), id)
    end
    for _, id in ipairs(def.startingEquipment or {}) do
      T.truthy(reg:get("catalog", id).equipment, id .. " is equipment")
    end
  end
  for _, id in ipairs(IDS) do
    T.truthy(seen[id], id .. " exists")
  end
end)

T.test("loadouts: the standard start is unchanged and has no loadout", function()
  local world = start(nil)
  T.eq(Perks.loadout(world), nil)
  T.eq(Ledger.get(world, "money"), tun.run.startingResources.money)
  T.eq(Ledger.get(world, "canned_food"), tun.run.startingResources.canned_food)
end)

T.test("loadouts: each one brings its bundle and takes its penalty off the starting stock", function()
  local plain = start(nil)
  for _, id in ipairs(IDS) do
    local def = reg:get("loadouts", id)
    local world = start(id)
    T.eq(Perks.loadout(world).id, id)
    local ids = {}
    for rid in pairs(def.startingResources or {}) do
      ids[rid] = true
    end
    for rid in pairs(def.penalty) do
      ids[rid] = true
    end
    for rid in pairs(ids) do
      local want = Ledger.get(plain, rid) + ((def.startingResources or {})[rid] or 0)
      want = math.max(0, want - (def.penalty[rid] or 0))
      T.eq(Ledger.get(world, rid), want, id .. ": " .. rid)
    end
    for _, eq in ipairs(def.startingEquipment or {}) do
      T.truthy(Inventory.hasEquipment(world, eq), id .. " owns " .. eq)
    end
    for _, obj in ipairs(def.startingObjects or {}) do
      T.eq(count(world, obj), count(plain, obj) + 1, id .. ": one more " .. obj .. " beside the truck")
    end
    if def.truckCharge then
      T.truthy(Power.charge(world, Land.truck(world)) > Power.charge(plain, Land.truck(plain)), id .. ": charged truck")
    end
  end
end)

T.test("loadouts: the herder's hens have a coop to live in", function()
  local world = start("herder")
  T.eq(Ledger.get(world, "hen"), 2)
  T.truthy(Ledger.get(world, "chicken_feed") > 0)
end)

T.test("loadouts: a penalty never takes a stock below zero", function()
  local world = start("angler")
  for _, id in ipairs(IDS) do
    for rid in pairs(reg:get("loadouts", id).penalty) do
      T.truthy(Ledger.get(start(id), rid) >= 0, id .. " " .. rid)
    end
  end
  T.truthy(Ledger.get(world, "canned_food") >= 0)
end)

T.test("loadouts: the Journal unlocks them; a locked one cannot be chosen, the default is no loadout", function()
  local data = Save.newSlotData("Kit")
  local world = session(data, 4).world
  Run.fail(data, world)
  local meta = Run.metaWorld(ctx, data.meta)
  for _, item in ipairs(Run.loadouts(meta)) do
    T.falsy(item.unlocked, item.def.id .. " starts locked")
    T.truthy(item.unlockName ~= "")
  end
  local ok, reason = Run.chooseLoadout(data, meta, "angler")
  T.falsy(ok)
  T.eq(reason, "locked")
  T.eq(data.meta.recovery.loadout, nil)
  T.eq(select(2, Run.chooseLoadout(data, meta, "nope")), "unknown")
  data.meta.journal.known.sturdy_rod = true -- the Journal has taught the sturdy rod
  for _, item in ipairs(Run.loadouts(meta)) do
    T.eq(item.unlocked, item.def.id == "angler", item.def.id)
  end
  T.truthy(Run.chooseLoadout(data, meta, "angler"))
  T.eq(data.meta.recovery.loadout, "angler")
  T.truthy(Run.chooseLoadout(data, meta, nil), "and it can be put back to the standard start")
  T.eq(data.meta.recovery.loadout, nil)
end)

T.test("loadouts: every loadout can be unlocked by learning its node", function()
  for _, id in ipairs(IDS) do
    local def = reg:get("loadouts", id)
    local data = Save.newSlotData("Kit")
    local world = session(data, 4).world
    Run.fail(data, world)
    local meta = Run.metaWorld(ctx, data.meta)
    data.meta.journal.known[def.unlock] = true
    T.truthy(Run.chooseLoadout(data, meta, id), id)
  end
end)

T.test("loadouts: Head out carries the chosen loadout into the next run, once, through a save", function()
  local data = Save.newSlotData("Kit")
  local world = session(data, 4).world
  Run.fail(data, world)
  local meta = Run.metaWorld(ctx, data.meta)
  data.meta.journal.known.axe = true
  Run.chooseLoadout(data, meta, "lumberjack")
  Run.startNext(data)
  T.eq(data.run.loadout, "lumberjack")
  local next = session(data).world
  T.truthy(Inventory.hasEquipment(next, "axe"))
  local wood = Ledger.get(next, "wood")
  local reloaded = session({
    meta = data.meta,
    header = data.header,
    run = serialize.decode(serialize.encode(next.state)),
  }).world
  T.eq(Ledger.get(reloaded, "wood"), wood, "a reload does not hand it out again")
  T.eq(Perks.loadout(reloaded).id, "lumberjack")
end)

T.test("loadouts: with a plot chosen too, both come along; without either the session draws a fresh seed", function()
  local data = Save.newSlotData("Kit")
  Run.fail(data, session(data, 4).world)
  local meta = Run.metaWorld(ctx, data.meta)
  local list = Run.offerPlots(data, meta, 3)
  data.meta.journal.known.hens = true
  Run.choosePlot(data, 2)
  Run.chooseLoadout(data, meta, "herder")
  Run.startNext(data)
  T.eq(data.run.seed, list[2].seed)
  T.eq(data.run.loadout, "herder")
  local plain = Save.newSlotData("Plain")
  Run.fail(plain, session(plain, 5).world)
  Run.startNext(plain)
  T.eq(plain.run, nil, "no plot and no kit: the run starts as it always did")
end)

T.test("camp perk (#215): knowing it starts every run with a camp beside the truck", function()
  local meta = Save.newSlotData("Camp").meta
  local before = count(start(nil, meta), "camp")
  meta.journal.known.pack_camp = true
  local world = start(nil, meta)
  T.eq(count(world, "camp"), before + 1)
  local def = reg:get("perks", "pack_camp")
  T.truthy(def.needs and #def.needs > 0, "it is learned from notes like any perk")
  local camp
  for anchor, obj in pairs(world.state.grid.objects) do
    if obj.id == "camp" then
      camp = anchor
    end
  end
  local cx, cy = Grid.coords(world.state.grid, camp)
  local sx, sy = Grid.coords(world.state.grid, Land.spawn(world))
  T.truthy(math.max(math.abs(cx - sx), math.abs(cy - sy)) <= 6, "within a short walk of the truck")
end)
