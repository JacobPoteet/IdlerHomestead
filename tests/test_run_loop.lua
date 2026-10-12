-- The roguelite loop (GDD §4.3): fail -> rescue -> recovery -> new land, knowledge kept.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local Run = require("src.meta.run")
local Journal = require("src.sim.systems.journal")
local Fishing = require("src.sim.systems.fishing")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local ctx = { registry = reg, tuning = tun }

local function newSession(data, seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = seed })
end

-- Starve the homesteader until Condition hits zero. Returns true once needs.depleted fires.
local function starve(world)
  local depleted = false
  world.events:on("needs.depleted", function()
    depleted = true
  end)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  for _ = 1, 20 do
    Needs.daily(world)
    if depleted then
      return true
    end
  end
  return false
end

T.test("run loop: failing records the run, finishes the study, and drops the run state", function()
  local data = Save.newSlotData("Loop")
  local session = newSession(data, 11)
  local world = session.world
  Fishing.land(world, "creek_chub", 12, "active")
  world.events:emit("food.spoiled", { resource = "creek_chub", category = "fish", amount = 1 })
  T.truthy(Journal.study(world, "smoker"))
  T.truthy(starve(world), "condition reaches zero")
  local summary = Run.fail(data, world)
  T.eq(data.run, nil)
  T.truthy(Run.isRecovering(data))
  T.truthy(data.header.recovering)
  T.eq(summary.run, 1)
  T.eq(#data.meta.career.history, 1)
  T.eq(data.meta.recovery.finishedStudy, "smoker", "the study in progress finishes during recovery")
  local noted = {}
  for _, id in ipairs(summary.notes) do
    noted[id] = true
  end
  T.truthy(noted.first_catch and noted.fish_spoil, "notes written this run are in the summary")
  T.eq(Run.rescues(data.meta), 1)
end)

T.test("run loop: one free study, then new land with the same knowledge", function()
  local data = Save.newSlotData("Loop")
  local world = newSession(data, 11).world
  world.meta.journal.notes.bucket_hauling = { day = 1, run = 1 }
  world.meta.journal.notes.felled_tree = { day = 1, run = 1 }
  T.truthy(starve(world))
  Run.fail(data, world)
  local metaWorld = Run.metaWorld(ctx, data.meta)
  T.truthy(Run.freeStudy(data, metaWorld, "big_bucket"))
  T.eq(select(2, Run.freeStudy(data, metaWorld, "axe")), "used", "only one free study")
  T.eq(Journal.status(metaWorld, "axe"), "idea")
  -- Save, reload, head out.
  local reloaded = serialize.decode(serialize.encode(data))
  Run.startNext(reloaded)
  T.falsy(Run.isRecovering(reloaded))
  T.eq(Run.number(reloaded.meta), 2)
  local next = newSession(reloaded, 22)
  local world2 = next.world
  T.truthy(reloaded.run, "a fresh run was generated")
  T.eq(world2.state.calendar.day, 1)
  T.eq(Journal.status(world2, "big_bucket"), "known", "knowledge carried over")
  T.truthy(Journal.hasNote(world2, "felled_tree"))
  T.falsy(world2.state.land.truck == world.state.land.truck and world2.state.seed == world.state.seed, "new land")
  -- No salvage: money and stock reset to the starting kit.
  T.eq(Ledger.get(world2, "money"), 0)
  Fishing.land(world2, "sunfish", 12, "active")
  T.eq(reloaded.meta.journal.notes.first_catch.run, 2, "notes remember which run wrote them")
end)

T.test("run loop: the rescuer remembers you", function()
  local data = Save.newSlotData("Loop")
  for _ = 1, 2 do
    local world = newSession(data, 3).world
    T.truthy(starve(world))
    Run.fail(data, world)
    Run.startNext(data)
  end
  T.eq(Run.rescues(data.meta), 2)
  T.eq(Run.number(data.meta), 3)
end)
