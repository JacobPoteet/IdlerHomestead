-- Sandbox save mode (GDD D134): a slot flagged `meta.sandbox` costs nothing and cannot fail the run; a normal
-- slot is unchanged; the flag survives save and load and is tagged in the slot list.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local Run = require("src.meta.run")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Sandbox = require("src.sim.systems.sandbox")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()

local function newSession(sandbox, seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local data = Save.newSlotData("Slot", { sandbox = sandbox })
  return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = seed or 5 }), data
end

local function emptyLarder(world)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories or res.heat then
      Ledger.remove(world, res.id, Ledger.get(world, res.id), "test")
    end
  end
end

T.test("sandbox: the flag is in the slot's meta and header, and a normal slot has none", function()
  local _, sandbox = newSession(true)
  T.eq(sandbox.meta.sandbox, true)
  T.eq(sandbox.header.sandbox, true)
  local _, normal = newSession(false)
  T.eq(normal.meta.sandbox, nil)
  T.eq(normal.header.sandbox, nil)
end)

T.test("sandbox: no food or warmth for many days never ends the run", function()
  local session = newSession(true)
  local world = session.world
  T.truthy(Sandbox.on(world))
  local depleted = 0
  world.events:on("needs.depleted", function()
    depleted = depleted + 1
  end)
  emptyLarder(world)
  for _ = 1, 400 do -- well over a year of days with nothing to eat or burn, winters included
    world.events:emit("calendar.newDay", { day = 1 })
    Needs.daily(world)
  end
  T.eq(depleted, 0)
  T.near(Needs.condition(world), tun.sandbox.conditionFloor, 1e-9, "health drains, but only to the floor")
  T.truthy(Needs.condition(world) > 0)
end)

T.test("sandbox: whole days of sim time with nothing stocked never fail the run", function()
  local session = newSession(true)
  local world = session.world
  local depleted = false
  world.events:on("needs.depleted", function()
    depleted = true
  end)
  emptyLarder(world)
  local perDay = tun.time.tickRate * tun.time.dayLength
  for _ = 1, perDay * 40 do
    world:tick(1 / tun.time.tickRate)
    emptyLarder(world) -- the starting kit's food stays eaten
  end
  T.falsy(depleted)
  T.truthy(Needs.condition(world) > 0)
end)

T.test("sandbox: a normal slot still dies of hunger and cold", function()
  local session = newSession(false)
  local world = session.world
  local depleted = false
  world.events:on("needs.depleted", function()
    depleted = true
  end)
  emptyLarder(world)
  for _ = 1, 40 do
    Needs.daily(world)
  end
  T.truthy(depleted)
  T.eq(Needs.condition(world), 0)
end)

T.test("sandbox: costs are free and instant, in the catalog and in the ledger", function()
  local session = newSession(true)
  local world = session.world
  T.truthy(Market.cheatOn(world))
  T.eq(#Market.catalogList(world), #reg:all("catalog"), "every item is listed")
  local money = Ledger.get(world, "money")
  Ledger.remove(world, "money", 0, "order")
  local ok = Market.order(world, "woodshed")
  T.truthy(ok, "ordering hands the item over at once")
  T.eq(#world.state.market.orders, 0, "nothing waits for tomorrow")
  T.eq(Ledger.get(world, "money"), money, "and no money moves")
  Market.setCheat(world, false)
  T.truthy(Market.cheatOn(world), "the debug toggle cannot turn a sandbox off")
  -- Using a stock costs nothing; losses that are not costs still happen.
  local wood = Ledger.get(world, "wood")
  T.truthy(Ledger.remove(world, "wood", 2, "burn"))
  T.eq(Ledger.get(world, "wood"), wood, "burning wood in a sandbox leaves the pile")
  T.truthy(Ledger.remove(world, "wood", 1, "sold"))
  T.eq(Ledger.get(world, "wood"), wood - 1, "a sale is not a cost")
  T.falsy(Ledger.remove(world, "wood", wood + 5, "burn"), "the stock still has to exist")
end)

T.test("sandbox: a normal slot pays for everything as before", function()
  local world = newSession(false).world
  T.falsy(Sandbox.on(world))
  T.falsy(Market.cheatOn(world))
  local wood = Ledger.get(world, "wood")
  T.truthy(Ledger.remove(world, "wood", 2, "burn"))
  T.eq(Ledger.get(world, "wood"), wood - 2)
  T.eq(Sandbox.conditionFloor(world), 0)
end)

T.test("sandbox: the flag survives save and load, and the slot list tags it", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 2 })
  local session, data = newSession(true)
  session.store = store
  session.slot = 1
  T.truthy(session:save())
  store:write(2, Save.newSlotData("Plain"))
  local list = store:list()
  T.eq(list[1].header.sandbox, true)
  T.eq(list[2].header.sandbox, nil)
  local loaded = store:read(1)
  T.eq(loaded.meta.sandbox, true)
  local again = Session.new({ store = store, slot = 1, data = loaded, registry = reg, tuning = tun })
  T.truthy(Sandbox.on(again.world))
  T.eq(serialize.decode(serialize.encode(data)).meta.sandbox, true)
end)

T.test("sandbox: a sandbox run never feeds the career", function()
  local session, data = newSession(true)
  T.errors(function()
    Run.fail(data, session.world)
  end, "sandbox")
  T.eq(data.meta.career, nil)
  T.eq(data.meta.recovery, nil)
end)
