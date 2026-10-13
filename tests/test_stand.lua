-- Roadside stand (GDD §6.4, D52, D75): an unlockable object by the road that sells a capped number of
-- surplus goods a day at a fraction of the truck price.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Food = require("src.sim.systems.food")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Stand = require("src.sim.systems.stand")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.stand
local DPS = tun.time.daysPerSeason
local SPRING, SUMMER, AUTUMN, WINTER = 1, DPS + 1, 2 * DPS + 1, 3 * DPS + 1

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function force(world, kind)
  world.state.weather.sky.days[1] = kind
end

--- A free tile beside the road where the stand fits.
local function roadSpot(world)
  local grid = world.state.grid
  for i = 1, #grid.terrain do
    if Inventory.canPlace(world, "roadside_stand", i) then
      return i
    end
  end
end

--- A world with a stand placed, plain prices (x1), summer, clear skies, just before opening time.
local function standWorld(seed)
  local world = newWorld(seed)
  world.state.market.prices = {}
  local spot = roadSpot(world)
  T.truthy(spot, "a spot beside the road")
  Inventory.addObject(world, "roadside_stand")
  T.truthy(Inventory.place(world, "roadside_stand", spot))
  setTime(world, SUMMER, cfg.sellHour - 1)
  force(world, "clear")
  return world, spot
end

--- Add `n` of a resource and keep none of it, so all of it is surplus (D75).
local function stock(world, id, n)
  Ledger.add(world, id, n)
  Food.setKeep(world, id, 0)
end

--- Let the stand's hour pass on the current day.
local function openUp(world)
  setTime(world, world.state.calendar.day, cfg.sellHour + 0.25)
  world:tick(STEP)
end

local function collect(world, name)
  local list = {}
  world.events:on(name, function(e)
    list[#list + 1] = e
  end)
  return list
end

-- Content ---------------------------------------------------------------------------------------

T.test("stand content: object, art, gated catalog nodes, upgrades are capped equipment", function()
  local sprites = require("assets.manifest").sprites
  local def = reg:get("objects", "roadside_stand")
  T.truthy(def.placeable and def.stand and def.placeNear == "road")
  T.truthy(sprites.roadside_stand and sprites.icon_roadside_stand)
  local item = reg:get("catalog", "roadside_stand")
  T.eq(item.object, "roadside_stand")
  T.truthy(#item.needs > 0, "unlocked by notes")
  local bonus = 0
  for _, id in ipairs({ "stand_sign", "stand_cooler", "stand_display" }) do
    local up = reg:get("catalog", id)
    T.truthy(up.equipment and up.modifiers.standCap > 0 and #up.needs > 0, id)
    T.truthy(sprites["icon_" .. id], id .. " icon")
    bonus = bonus + up.modifiers.standCap
  end
  T.eq(cfg.baseCap + bonus, cfg.maxCap, "all upgrades reach exactly the ceiling")
  for _, flow in pairs(cfg.seasonFlow) do
    T.truthy(flow > 0 and flow <= 1)
  end
  for _, flow in pairs(cfg.weatherFlow) do
    T.truthy(flow > 0 and flow <= 1)
  end
end)

T.test("stand: the stand node is a journal idea only once the notes are written", function()
  local world = newWorld()
  T.eq(Journal.isIdea(world, "roadside_stand"), false)
  world.events:emit("market.trip", {})
  world.events:emit("food.spoiled", { category = "food", resource = "radish", amount = 1 })
  T.truthy(Journal.isIdea(world, "roadside_stand"))
end)

-- Placement -------------------------------------------------------------------------------------

T.test("stand placement: beside the road, never on it, never far from it", function()
  local world = newWorld()
  local grid = world.state.grid
  local ok = 0
  for i = 1, #grid.terrain do
    if Inventory.canPlace(world, "roadside_stand", i) then
      ok = ok + 1
      local x, y = Grid.coords(grid, i)
      local near = false
      for dy = -1, 1 do
        for tx = x - 1, x + 2 do
          if Grid.inBounds(grid, tx, y + dy) and Grid.terrain(world, Grid.index(grid, tx, y + dy)).id == "road" then
            near = true
          end
          if tx >= x and tx <= x + 1 and dy == 0 then
            T.truthy(Grid.terrain(world, Grid.index(grid, tx, y)).id ~= "road", "not on the road")
          end
        end
      end
      T.truthy(near, "touches the road")
    end
  end
  T.truthy(ok > 0, "somewhere to put it")
end)

T.test("stand placement: a spot beside the road exists on every seed", function()
  for seed = 1, 12 do
    T.truthy(roadSpot(newWorld(seed)), "seed " .. seed)
  end
end)

-- Selling ---------------------------------------------------------------------------------------

T.test("stand: sells up to the daily cap, at a fraction of the town price, once a day", function()
  local world = standWorld()
  stock(world, "sunfish", 20)
  local sold = collect(world, "stand.sold")
  local before = Ledger.get(world, "money")
  openUp(world)
  T.eq(#sold, 1)
  T.eq(sold[1].units, cfg.baseCap)
  local expected = math.floor(cfg.baseCap * Market.sellPrice(world, "sunfish") * cfg.priceFraction + 0.5)
  T.eq(sold[1].earned, expected)
  T.eq(Ledger.get(world, "money"), before + expected)
  T.eq(Ledger.get(world, "sunfish"), 20 - cfg.baseCap)
  -- The same day again: nothing more.
  world:tick(STEP)
  openUp(world)
  T.eq(#sold, 1)
  -- Next day: another batch.
  setTime(world, SUMMER + 1, cfg.sellHour + 0.25)
  force(world, "clear")
  world:tick(STEP)
  T.eq(#sold, 2)
  T.eq(Ledger.get(world, "sunfish"), 20 - 2 * cfg.baseCap)
  T.eq(Stand.total(world).units, 2 * cfg.baseCap)
  T.eq(Stand.last(world).day, SUMMER + 1)
end)

T.test("stand: waits for its opening hour", function()
  local world = standWorld()
  stock(world, "sunfish", 5)
  setTime(world, SUMMER, cfg.sellHour - 0.5)
  world:tick(STEP)
  T.eq(Ledger.get(world, "sunfish"), 5)
  openUp(world)
  T.eq(Ledger.get(world, "sunfish"), 0)
end)

T.test("stand: cheapest goods go first, so valuable ones wait for the truck", function()
  local world = standWorld()
  stock(world, "radish", 4)
  stock(world, "brook_trout", 10)
  openUp(world)
  T.eq(Ledger.get(world, "radish"), 0)
  T.eq(Ledger.get(world, "brook_trout"), 10 - (cfg.baseCap - 4))
end)

T.test("stand: pays less per item than the truck, and cannot drain the surplus like a trip", function()
  local world = standWorld()
  stock(world, "sunfish", 40)
  Market.autoLoad(world)
  local _, truckTotal, truckUnits = Market.loadQuote(world)
  T.eq(truckUnits, tun.economy.cargoCapacity)
  Market.clearLoad(world)
  local _, earned = Stand.sell(world)
  T.truthy(earned < truckTotal, "a day at the stand pays less than a trip")
  T.truthy(earned * 3 < truckTotal, "the trip is worth several days of stand income")
  T.truthy(cfg.priceFraction < 1)
  T.truthy(cfg.maxCap < tun.economy.cargoCapacity)
  for _, res in ipairs(reg:all("resources")) do
    if res.value and res.value > 1 then
      T.truthy(Stand.unitPrice(world, res.id) < Market.sellPrice(world, res.id), res.id .. " pays less at the stand")
    end
  end
end)

T.test("stand: stock exhaustion, and kept goods are never touched", function()
  local world = standWorld()
  stock(world, "sunfish", 2)
  Ledger.add(world, "potato", 3)
  Food.setKeep(world, "potato", 3)
  local sold = collect(world, "stand.sold")
  openUp(world)
  T.eq(sold[1].units, 2)
  T.eq(Ledger.get(world, "sunfish"), 0)
  T.eq(Ledger.get(world, "potato"), 3)
  -- Nothing left to sell: no event, no money, no crash.
  setTime(world, SUMMER + 1, cfg.sellHour + 0.25)
  force(world, "clear")
  local money = Ledger.get(world, "money")
  world:tick(STEP)
  T.eq(#sold, 1)
  T.eq(Ledger.get(world, "money"), money)
  T.eq(Ledger.get(world, "potato"), 3)
end)

T.test("stand: no stand placed means no sales", function()
  local world = newWorld()
  world.state.market.prices = {}
  setTime(world, SUMMER, cfg.sellHour + 0.25)
  stock(world, "sunfish", 5)
  world:tick(STEP)
  T.eq(Ledger.get(world, "sunfish"), 5)
end)

T.test("stand: the ledger stays whole, items leave and money arrives, nothing else moves", function()
  local world = standWorld()
  stock(world, "sunfish", 10)
  local changes = {}
  world.events:on("ledger.changed", function(e)
    if e.reason == "stand" then
      changes[#changes + 1] = e
    end
  end)
  openUp(world)
  local removed, added = 0, 0
  for _, e in ipairs(changes) do
    if e.id == "money" then
      added = added + e.delta
    else
      T.eq(e.id, "sunfish")
      removed = removed - e.delta
    end
  end
  T.eq(removed, cfg.baseCap)
  T.truthy(added > 0)
end)

-- Upgrades --------------------------------------------------------------------------------------

T.test("stand upgrades raise the cap and the ceiling holds", function()
  local world = standWorld()
  T.eq(Stand.cap(world), cfg.baseCap)
  Inventory.addEquipment(world, "stand_sign")
  T.eq(Stand.cap(world), cfg.baseCap + reg:get("catalog", "stand_sign").modifiers.standCap)
  stock(world, "sunfish", 40)
  local sold = collect(world, "stand.sold")
  openUp(world)
  T.eq(sold[1].units, Stand.cap(world))
  Inventory.addEquipment(world, "stand_cooler")
  Inventory.addEquipment(world, "stand_display")
  T.eq(Stand.cap(world), cfg.maxCap)
  setTime(world, SUMMER + 1, cfg.sellHour + 0.25)
  force(world, "clear")
  world:tick(STEP)
  T.eq(sold[2].units, cfg.maxCap)
  T.truthy(Ledger.get(world, "sunfish") > 0, "even a fully upgraded stand leaves the rest for the truck")
end)

T.test("stand: a second stand adds nothing", function()
  local world = standWorld()
  local spot
  for i = 1, #world.state.grid.terrain do
    if Inventory.canPlace(world, "roadside_stand", i) then
      spot = i
      break
    end
  end
  Inventory.addObject(world, "roadside_stand")
  Inventory.place(world, "roadside_stand", spot)
  stock(world, "sunfish", 40)
  openUp(world)
  T.eq(Ledger.get(world, "sunfish"), 40 - cfg.baseCap)
end)

-- Weather and season ----------------------------------------------------------------------------

T.test("stand: weather and season scale the cap down, never up", function()
  local world = standWorld()
  Inventory.addEquipment(world, "stand_sign")
  local cap = Stand.cap(world)
  for _, kind in ipairs(tun.weather.order) do
    for _, day in ipairs({ SPRING, SUMMER, AUTUMN, WINTER }) do
      setTime(world, day, 12)
      force(world, kind)
      local today = Stand.todayCap(world)
      T.truthy(today <= cap and today >= 0, kind .. " day " .. day)
    end
  end
  setTime(world, SUMMER, 12)
  force(world, "clear")
  T.eq(Stand.todayCap(world), cap)
  force(world, "storm")
  T.truthy(Stand.todayCap(world) < cap)
  force(world, "clear")
  setTime(world, WINTER, 12)
  T.truthy(Stand.todayCap(world) < cap)
end)

T.test("stand: a rainy day sells fewer items", function()
  local world = standWorld()
  stock(world, "sunfish", 20)
  force(world, "rain")
  openUp(world)
  T.eq(20 - Ledger.get(world, "sunfish"), math.floor(cfg.baseCap * cfg.weatherFlow.rain + 0.5))
end)

-- Journal, determinism, saves -------------------------------------------------------------------

T.test("stand: the first sale writes the stand_sale note", function()
  local world = standWorld()
  stock(world, "sunfish", 3)
  T.falsy(Journal.hasNote(world, "stand_sale"))
  openUp(world)
  T.truthy(Journal.hasNote(world, "stand_sale"))
end)

T.test("stand: deterministic per seed", function()
  local function run(seed)
    local world = standWorld(seed)
    stock(world, "sunfish", 60)
    stock(world, "radish", 30)
    for day = SUMMER, SUMMER + 5 do
      setTime(world, day, cfg.sellHour - 1)
      world:tick(STEP)
      openUp(world)
    end
    return serialize.encode(world.state.stand), Ledger.get(world, "money")
  end
  local a, am = run(5)
  local b, bm = run(5)
  T.eq(a, b)
  T.eq(am, bm)
end)

T.test("stand: state survives a save round-trip and carries on the same", function()
  local world = standWorld()
  stock(world, "sunfish", 30)
  openUp(world)
  local state = serialize.decode(serialize.encode(world.state))
  local restored = World.new({ registry = reg, tuning = tun }, state)
  T.same(restored.state.stand, world.state.stand)
  T.eq(Stand.isOpen(restored), true)
  for _, w in ipairs({ world, restored }) do
    setTime(w, SUMMER + 1, cfg.sellHour + 0.25)
    force(w, "clear")
    w:tick(STEP)
  end
  T.eq(Ledger.get(restored, "sunfish"), Ledger.get(world, "sunfish"))
  T.eq(Ledger.get(restored, "money"), Ledger.get(world, "money"))
end)

T.test("stand: a save from before the stand loads, and the stand still works", function()
  local world = standWorld()
  stock(world, "sunfish", 10)
  local state = serialize.decode(serialize.encode(world.state))
  state.stand = nil
  local old = World.new({ registry = reg, tuning = tun }, state)
  T.truthy(old.state.stand)
  T.eq(Stand.total(old).units, 0)
  T.eq(Stand.last(old), nil)
  setTime(old, SUMMER, cfg.sellHour + 0.25)
  force(old, "clear")
  old:tick(STEP)
  T.eq(Stand.total(old).units, cfg.baseCap)
end)

T.test("stand: a stand-less world adds its state key harmlessly", function()
  local world = newWorld()
  T.eq(Stand.isOpen(world), false)
  T.eq(Stand.total(world).earned, 0)
  T.eq(Land.truck(world) ~= nil, true)
end)

-- "Not at the stand" pin (D62, #106) ---------------------------------------------------------------

T.test("stand pin: a truck-only good is skipped, the rest still sell", function()
  local world = standWorld()
  stock(world, "radish", 4)
  stock(world, "brook_trout", 10)
  Food.setTruckOnly(world, "radish", true)
  openUp(world)
  T.eq(Ledger.get(world, "radish"), 4, "pinned good stays for the truck")
  T.eq(Food.surplus(world, "radish"), 4, "and stays surplus")
  T.eq(Ledger.get(world, "brook_trout"), 10 - cfg.baseCap)
end)

T.test("stand pin: all goods pinned means no sale, and unpinning sells next day", function()
  local world = standWorld()
  stock(world, "sunfish", 5)
  Food.setTruckOnly(world, "sunfish", true)
  local sold = collect(world, "stand.sold")
  openUp(world)
  T.eq(#sold, 0)
  T.eq(Ledger.get(world, "sunfish"), 5)
  Food.setTruckOnly(world, "sunfish", false)
  T.eq(Food.truckOnly(world, "sunfish"), false)
  setTime(world, SUMMER + 1, cfg.sellHour + 0.25)
  force(world, "clear")
  world:tick(STEP)
  T.eq(#sold, 1)
  T.eq(Ledger.get(world, "sunfish"), 0)
end)

T.test("stand pin: the truck still sells a pinned good", function()
  local world = standWorld()
  stock(world, "sunfish", 5)
  Food.setTruckOnly(world, "sunfish", true)
  Market.autoLoad(world)
  local _, _, units = Market.loadQuote(world)
  T.eq(units, 5)
end)

T.test("stand pin: persists in a save", function()
  local world = standWorld()
  stock(world, "sunfish", 8)
  Food.setTruckOnly(world, "sunfish", true)
  local state = serialize.decode(serialize.encode(world.state))
  local restored = World.new({ registry = reg, tuning = tun }, state)
  T.eq(Food.truckOnly(restored, "sunfish"), true)
  openUp(restored)
  T.eq(Ledger.get(restored, "sunfish"), 8)
end)

T.test("stand pin: independent of the keep target", function()
  local world = standWorld()
  Ledger.add(world, "sunfish", 5)
  Food.setKeep(world, "sunfish", 0)
  Food.setTruckOnly(world, "sunfish", true)
  Food.setKeep(world, "sunfish", nil)
  T.eq(Food.truckOnly(world, "sunfish"), true)
  Food.setKeep(world, "sunfish", 5)
  T.eq(Food.truckOnly(world, "sunfish"), true)
end)

-- Surplus and the truck load (D75, #196) ---------------------------------------------------------------

T.test("stand: sells surplus only; the automatic keep holds the pantry back", function()
  local world = standWorld()
  Ledger.add(world, "radish", 50)
  local keep, auto = Food.keep(world, "radish")
  T.truthy(auto and keep > 0 and keep < 50, "the automatic keep holds a few days of radishes")
  local sold = collect(world, "stand.sold")
  for day = SUMMER, SUMMER + 6 do
    setTime(world, day, cfg.sellHour - 1)
    force(world, "clear")
    world:tick(STEP)
    openUp(world)
  end
  T.eq(Ledger.get(world, "radish"), keep, "everything above the keep sold, nothing below it")
  T.truthy(#sold >= 2)
end)

T.test("stand: goods loaded on the truck are not for sale at the stand", function()
  local world = standWorld()
  stock(world, "radish", 10)
  stock(world, "sunfish", 3)
  T.eq(Market.setLoad(world, "radish", 8), 8)
  T.eq(Stand.forSale(world, "radish"), 2)
  openUp(world)
  T.eq(Ledger.get(world, "radish"), 8, "the loaded radishes stayed for the truck")
  T.eq(Ledger.get(world, "sunfish"), 0)
  T.eq(Market.loaded(world, "radish"), 8)
end)

T.test("stand: equal prices sell the food that spoils soonest first", function()
  local world = standWorld()
  stock(world, "stone", 10)
  stock(world, "radish", 10)
  T.eq(Market.sellPrice(world, "stone"), Market.sellPrice(world, "radish"))
  openUp(world)
  T.eq(Ledger.get(world, "radish"), 10 - cfg.baseCap, "radishes go before stone, which keeps")
  T.eq(Ledger.get(world, "stone"), 10)
end)
