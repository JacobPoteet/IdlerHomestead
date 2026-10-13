local T = require("harness")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local tuning = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Ledger = require("src.sim.systems.ledger")
local Session = require("src.session")

local tun = tuning.load()
local reg = Registry.new():loadAll()

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

-- Save slots -----------------------------------------------------------------

T.test("save: empty slots, write, read, list", function()
  local store = Save.new(Save.memoryBackend(), { slotCount = 3 })
  local _, err = store:read(1)
  T.eq(err, "empty")
  local data = Save.newSlotData("Pine Hollow")
  data.header.playtime = 125
  T.truthy(store:write(2, data))
  local loaded = store:read(2)
  T.eq(loaded.name, "Pine Hollow")
  local list = store:list()
  T.eq(#list, 3)
  T.eq(list[1].state, "empty")
  T.eq(list[2].state, "ok")
  T.eq(list[2].header.playtime, 125)
end)

T.test("save: falls back to backup when the main file is corrupt", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 3 })
  store:write(1, Save.newSlotData("First"))
  local second = Save.newSlotData("Second")
  store:write(1, second)
  backend.files["slot1.sav"] = "{ this is not valid"
  local data, fromBackup = store:read(1)
  T.eq(data.name, "First")
  T.eq(fromBackup, true)
end)

T.test("save: corrupt with no backup is reported, delete clears", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 3 })
  backend.files["slot3.sav"] = "garbage("
  T.eq(store:list()[3].state, "corrupt")
  store:delete(3)
  T.eq(store:list()[3].state, "empty")
end)

T.test("save: rejects saves from a newer format", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  backend.files["slot1.sav"] = serialize.encode({ version = Save.FORMAT_VERSION + 1, name = "x" })
  local data, err = store:read(1)
  T.eq(data, nil)
  T.truthy(err:find("newer"))
end)

T.test("save: a corrupt main file never replaces a good backup", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  store:write(1, Save.newSlotData("first"))
  store:write(1, Save.newSlotData("second")) -- backup now holds "first"
  backend.files["slot1.sav"] = "garbage("
  store:write(1, Save.newSlotData("third"))
  T.eq(store:read(1).name, "third")
  T.eq(serialize.decode(backend.files["slot1.bak"]).name, "first")
end)

T.test("save: a non-numeric version is reported as corrupt, not a crash", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  backend.files["slot1.sav"] = serialize.encode({ version = "2", name = "x" })
  local data, err = store:read(1)
  T.eq(data, nil)
  T.truthy(err:find("version"))
  T.eq(store:list()[1].state, "corrupt")
end)

T.test("save: invalid slot index errors", function()
  local store = Save.new(Save.memoryBackend(), { slotCount = 3 })
  T.errors(function()
    store:read(4)
  end, "Invalid save slot")
end)

-- Count how many full slot decodes a function triggers, by wrapping the backend's main-file reads.
local function countMainReads(backend, fn)
  local reads = 0
  local original = backend.read
  backend.read = function(path)
    local contents = original(path)
    if contents and path:match("%.sav$") then
      reads = reads + 1
    end
    return contents
  end
  fn()
  backend.read = original
  return reads
end

T.test("save: list reads only the header sidecar", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 3 })
  local data = Save.newSlotData("Pine Hollow")
  data.header.playtime = 90
  store:write(1, data)
  store:write(2, Save.newSlotData("Other"))
  T.truthy(backend.files["slot1.hdr"])
  local list
  T.eq(
    countMainReads(backend, function()
      list = store:list()
    end),
    0
  )
  T.eq(list[1].name, "Pine Hollow")
  T.eq(list[1].header.playtime, 90)
  T.eq(list[2].name, "Other")
  T.eq(list[3].state, "empty")
end)

T.test("save: old saves without a sidecar still list, and gain one", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  local data = Save.newSlotData("Legacy")
  data.header.playtime = 7
  backend.files["slot1.sav"] = serialize.encode(data)
  T.eq(store:list()[1].name, "Legacy")
  T.truthy(backend.files["slot1.hdr"])
  local list
  T.eq(
    countMainReads(backend, function()
      list = store:list()
    end),
    0
  )
  T.eq(list[1].header.playtime, 7)
end)

T.test("save: rename updates the sidecar, delete removes it", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  store:write(1, Save.newSlotData("Before"))
  local data = store:read(1)
  data.name = "After"
  store:write(1, data)
  T.eq(store:list()[1].name, "After")
  store:delete(1)
  T.eq(backend.files["slot1.hdr"], nil)
  T.eq(store:list()[1].state, "empty")
end)

T.test("save: a stale or damaged sidecar falls back to the slot itself", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 2 })
  store:write(1, Save.newSlotData("First"))
  -- Main file corrupted after the sidecar was written: list must not claim the slot is fine.
  backend.files["slot1.sav"] = "garbage("
  T.eq(store:list()[1].state, "corrupt")
  -- Main replaced by a different save (size differs): the sidecar must not win.
  store:write(2, Save.newSlotData("Old"))
  backend.files["slot2.sav"] = serialize.encode(Save.newSlotData("A much longer replacement name"))
  T.eq(store:list()[2].name, "A much longer replacement name")
  -- Damaged sidecar.
  backend.files["slot2.hdr"] = "not ( valid"
  T.eq(store:list()[2].name, "A much longer replacement name")
end)

-- World & ledger -------------------------------------------------------------

T.test("ledger: add, remove, capacity, events", function()
  local world = newWorld()
  local changes = {}
  world.events:on("ledger.changed", function(e)
    changes[#changes + 1] = e
  end)
  T.eq(Ledger.add(world, "scrap", 5, "test"), 5)
  T.eq(Ledger.get(world, "scrap"), 5)
  T.truthy(Ledger.remove(world, "scrap", 2))
  T.falsy(Ledger.remove(world, "scrap", 10))
  T.eq(Ledger.get(world, "scrap"), 3)
  Ledger.setCapacity(world, "scrap", 4)
  T.eq(Ledger.add(world, "scrap", 5), 1)
  T.eq(#changes, 3)
  T.eq(changes[1].reason, "test")
  T.eq(changes[3].total, 4)
end)

T.test("ledger: spend is atomic", function()
  local world = newWorld()
  Ledger.add(world, "scrap", 3)
  Ledger.add(world, "stone", 1)
  T.falsy(Ledger.spend(world, { scrap = 2, stone = 2 }))
  T.eq(Ledger.get(world, "scrap"), 3)
  T.truthy(Ledger.spend(world, { scrap = 2, stone = 1 }))
  T.eq(Ledger.get(world, "scrap"), 1)
  T.eq(Ledger.get(world, "stone"), 0)
end)

T.test("ledger: unknown resource ids error", function()
  local world = newWorld()
  T.errors(function()
    Ledger.add(world, "wod", 1)
  end, "Unknown resources id 'wod'")
end)

T.test("world: state survives a save round-trip, rng streams continue", function()
  local world = newWorld(99)
  Ledger.add(world, "money", 12)
  local money = Ledger.get(world, "money") -- (the starting kit has some)
  world:rng("land"):float()
  for _ = 1, 10 do
    world:tick(0.05)
  end
  local restored = World.new({ registry = reg, tuning = tun }, serialize.decode(serialize.encode(world.state)))
  T.eq(restored.state.tick, 10)
  T.eq(Ledger.get(restored, "money"), money)
  T.eq(restored:rng("land"):float(), world:rng("land"):float())
end)

T.test("world: same seed, same streams; streams independent", function()
  local a, b = newWorld(7), newWorld(7)
  T.eq(a:rng("weather"):float(), b:rng("weather"):float())
  a:rng("land"):float()
  T.eq(a:rng("weather"):float(), b:rng("weather"):float())
end)

-- Session --------------------------------------------------------------------

T.test("session: ticks at the tuned rate, tracks playtime, autosaves", function()
  local store = Save.new(Save.memoryBackend(), { slotCount = 3 })
  local session = Session.new({ store = store, slot = 1, data = Save.newSlotData("Test"), registry = reg, tuning = tun, seed = 3 })
  session:update(1)
  T.eq(session.world.state.tick, tun.time.tickRate)
  T.near(session.data.header.playtime, 1)
  T.eq(store:list()[1].state, "empty")
  session:update(tun.save.autosaveInterval)
  T.eq(store:list()[1].state, "ok")
  local reloaded = store:read(1)
  T.eq(reloaded.run.seed, 3)
end)
