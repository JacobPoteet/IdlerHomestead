-- Crop quality (PLAN_DEPTH 8.6, D182, D185, issue #368): the grade from fertility, weeds and thirst, the tier tally
-- that follows the ledger, the price multipliers at the truck and the stand, and the rule that the idle routine earns
-- fine on healthy soil (there is no tended mark).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Crops = require("src.sim.systems.crops")
local Gridpack = require("src.core.gridpack")
local Grid = require("src.sim.grid")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Quality = require("src.sim.systems.quality")
local QualityText = require("src.ui.quality_text")
local Save = require("src.core.save")
local Stand = require("src.sim.systems.stand")
local Tasks = require("src.sim.systems.tasks")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.quality
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SUMMER = DPS + 1

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 4))
  world.control = "active"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + (hour or 9) / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function run(world, seconds)
  for _ = 1, math.floor(seconds / STEP) do
    world:tick(STEP)
  end
end

local function freeTiles(world, n)
  local grid = world.state.grid
  local sx, sy = Grid.coords(grid, world.state.land.spawn)
  local tiles = {}
  for r = 1, 12 do
    for y = sy - r, sy + r do
      for x = sx - r, sx + r do
        local i = Grid.inBounds(grid, x, y) and Grid.index(grid, x, y)
        if
          i
          and #tiles < n
          and Grid.terrain(world, i).tillable
          and not world.occupancy[i]
          and not Crops.tileInUse(world, i)
          and i ~= world.state.land.spawn
        then
          world.state.fields.tilled[i] = true
          tiles[#tiles + 1] = i
        end
      end
    end
  end
  T.eq(#tiles, n, "room for the field")
  return tiles
end

--- A ripe crop on tile i with chosen conditions, harvested through the real task. Returns the harvest event.
local function harvest(world, i, cropId, opts)
  opts = opts or {}
  world.state.fields.tilled[i] = true
  world.state.grid.fertility[i] = opts.fertility or 1
  world.state.soil.weeds[i] = opts.weeds
  world.state.crops[i] = { id = cropId, growth = 1, moisture = 1, thirst = opts.thirst or 0 }
  local seen
  local off = world.events:on("crop.harvested", function(e)
    seen = e
  end)
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
  if type(off) == "function" then
    off()
  end
  return seen
end

-- The data ----------------------------------------------------------------------------------------------

T.test("quality: two tiers, worst first, fine worth more, and the bar is a share of the penalty", function()
  T.same(cfg.tiers, { "normal", "fine" })
  T.eq(cfg.priceMult.normal, 1)
  T.truthy(cfg.priceMult.fine > cfg.priceMult.normal)
  T.truthy(cfg.fineMax > 0 and cfg.fineMax < 1)
  T.near(cfg.weightFertility + cfg.weightWeeds + cfg.weightWater, 1, 1e-9, "the weights share one penalty")
  local world = newWorld()
  T.eq(Quality.rank(world, "normal"), 1)
  T.eq(Quality.rank(world, "fine"), 2)
  T.errors(function()
    Quality.rank(world, "excellent")
  end)
end)

-- The grade ----------------------------------------------------------------------------------------------

T.test("quality: clean rich ground is fine, neglect is normal", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  local e = harvest(world, i, "radish", { fertility = 1 })
  T.eq(e.quality, "fine", "clean rich ground")
  T.eq(e.tended, nil, "there is no tended mark")
  T.eq(
    harvest(world, i, "tomato", { fertility = 0.2, weeds = 0.8, thirst = 1 }).quality,
    "normal",
    "weedy, drained and thirsty"
  )
end)

T.test("quality: the more sensitive crop falls a tier sooner on the same ground", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  local mid = { fertility = 0.4, weeds = 0.4 }
  T.eq(harvest(world, i, "radish", mid).quality, "fine", "radish (0.3) shrugs it off")
  T.eq(harvest(world, i, "tomato", mid).quality, "normal", "tomato (0.8) shows it")
end)

T.test("quality: each input moves the penalty on its own", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  local def = reg:get("crops", "carrot")
  local function penalty(opts)
    world.state.grid.fertility[i] = opts.fertility or 1
    world.state.soil.weeds[i] = opts.weeds
    return Quality.penalty(world, i, { thirst = opts.thirst or 0 }, def)
  end
  T.eq(penalty({}), 0)
  T.near(penalty({ fertility = 0 }), cfg.weightFertility, 1e-9)
  T.near(penalty({ weeds = 1 }), cfg.weightWeeds, 1e-9)
  T.near(penalty({ thirst = cfg.thirstTolerance * def.growDays }), cfg.weightWater, 1e-9, "full at the tolerance")
  T.near(penalty({ thirst = 99 }), cfg.weightWater, 1e-9, "never past the weight")
end)

T.test("quality: thirst builds while a crop stands dry and unripe, and stops when it is watered or ripe", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  world.state.crops[i] = { id = "carrot", growth = 0, moisture = 0, thirst = 0 }
  run(world, tun.time.dayLength / 4)
  T.near(world.state.crops[i].thirst, 0.25, 0.01, "a quarter of a day dry is a quarter of a day thirsty")
  world.state.crops[i].moisture = 1
  local before = world.state.crops[i].thirst
  run(world, 10)
  T.eq(world.state.crops[i].thirst, before, "no thirst while it is moist")
  world.state.crops[i].growth, world.state.crops[i].moisture = 1, 0
  run(world, 10)
  T.eq(world.state.crops[i].thirst, before, "no thirst once it is ripe")
end)

-- The idle routine earns fine --------------------------------------------------------------------------------

T.test("quality: left to the routine, harvests on rich ground are fine", function()
  local world = newWorld(5)
  world.control = "idle"
  setTime(world, SUMMER, 6)
  local tiles = freeTiles(world, 8)
  for _, i in ipairs(tiles) do
    world.state.fields.plan[i] = "radish"
    world.state.grid.fertility[i] = 1
  end
  Ledger.add(world, "seed_radish", 8, "test")
  local tiers = { normal = 0, fine = 0 }
  world.events:on("crop.harvested", function(e)
    tiers[e.quality] = tiers[e.quality] + 1
  end)
  run(world, tun.time.dayLength * 5)
  T.truthy(tiers.fine > 0, "the routine earns fine on rich ground, no hand orders needed")
end)

T.test("quality: a hand order and the routine's own job leave the same crop", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  world.state.crops[i] = { id = "carrot", growth = 0.3, moisture = 0, thirst = 0 }
  local hs = Actors.homesteader(world)
  hs.bucket = 3
  Tasks.get(world, "water_crop").complete(world, hs, i, nil)
  local routine = serialize.encode(world.state.crops[i])
  world.state.crops[i].moisture = 0
  Tasks.get(world, "water_crop").complete(world, hs, i, {})
  T.eq(serialize.encode(world.state.crops[i]), routine, "no tended mark on either")
  T.truthy(QualityText.cropLine(world, i):find("Quality:", 1, true))
  T.falsy(QualityText.cropLine(world, i):find("tended", 1, true))
end)

-- The tally ----------------------------------------------------------------------------------------------------

T.test(
  "quality: a harvest stocks its tier, eating takes the lowest first, and the tally never exceeds the ledger",
  function()
    local world = newWorld()
    setTime(world, SUMMER + 2)
    local i = freeTiles(world, 1)[1]
    Ledger.add(world, "radish", 3, "test") -- three plain ones already in store
    local e = harvest(world, i, "radish", { fertility = 1 })
    T.eq(e.quality, "fine")
    local counts = Quality.counts(world, "radish")
    T.eq(counts.fine, e.amount)
    T.eq(counts.normal, 3)
    T.eq(Quality.atLeast(world, "radish", "fine"), e.amount, "the contracts hook: units at a tier or better")
    T.eq(Quality.atLeast(world, "radish", "normal"), Ledger.get(world, "radish"))
    T.truthy(QualityText.stock(world, "radish"):find("fine", 1, true))
    Ledger.remove(world, "radish", 3, "ate") -- the plain ones go first
    T.eq(Quality.counts(world, "radish").fine, e.amount)
    Ledger.remove(world, "radish", e.amount, "ate")
    T.falsy(Quality.hasAny(world, "radish"), "an empty store holds no tiers")
    T.falsy(QualityText.stock(world, "radish"))
  end
)

T.test("quality: a harvest that overflows a full store tallies only what fitted", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  Ledger.setCapacity(world, "radish", 2)
  Ledger.add(world, "radish", 2, "test")
  world.state.grid.fertility[i] = 1
  world.state.crops[i] = { id = "radish", growth = 1, moisture = 1, thirst = 0 }
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i) -- the safety net: nothing fits
  T.eq(Quality.counts(world, "radish").fine, 0)
  T.eq(Ledger.get(world, "radish"), 2)
end)

T.test("quality: pick and worth read the best or the worst units first", function()
  local world = newWorld()
  Ledger.add(world, "radish", 6, "test")
  world.state.quality.radish = { fine = 3 }
  T.same(Quality.pick(world, "radish", 2, "best"), { fine = 2 })
  T.same(Quality.pick(world, "radish", 5, "worst"), { normal = 3, fine = 2 })
  T.near(Quality.worth(world, "radish", 2, "best"), 2 * cfg.priceMult.fine, 1e-9)
  T.near(Quality.worth(world, "radish", 3, "worst"), 3, 1e-9)
end)

-- Prices ---------------------------------------------------------------------------------------------------------

T.test("quality: the town pays the tier's multiplier and sells the best units first", function()
  local world = newWorld()
  world.state.market.prices.potato = 1 -- this week's drift off, so the price is the base value (2)
  local base = reg:get("resources", "potato").value
  T.eq(Market.tierPrice(world, "potato", "normal"), base)
  T.near(
    Market.tierPrice(world, "potato", "fine"),
    base * cfg.priceMult.fine,
    1e-9,
    "better tiers are not rounded per unit"
  )
  Ledger.add(world, "potato", 10, "test")
  world.state.quality.potato = { fine = 5 }
  Market.setLoad(world, "potato", 4, true)
  local lines, total = Market.loadQuote(world)
  T.eq(#lines, 1)
  T.same(lines[1].tiers, { fine = 4 })
  T.eq(total, math.floor(4 * Market.tierPrice(world, "potato", "fine") + 0.5), "a line rounds once")
  world.state.market.prices.radish = 1
  Ledger.add(world, "radish", 5, "test")
  world.state.quality.radish = { fine = 5 }
  T.eq(
    Market.worth(world, "radish", 5, "best"),
    7,
    "five $1 radishes at fine are worth $7, not $5 (1.3 each, rounded once)"
  )
  T.eq(lines[1].price, base, "price stays the normal unit price")
  world.state.market.inTown = true
  local money = Ledger.get(world, "money")
  local earned = Market.sellLoad(world)
  T.eq(earned, total)
  T.eq(Ledger.get(world, "money"), money + total)
  T.eq(Ledger.get(world, "potato"), 6)
  T.same(world.state.quality.potato, { fine = 1 }, "the four fine ones went; one is left")
end)

T.test("quality: the stand sells the worst units first at their tier's price", function()
  local world = newWorld()
  world.state.market.prices.potato = 1
  Ledger.add(world, "potato", 5, "test")
  world.state.quality.potato = { fine = 2 } -- three normal, two fine
  local worth = Quality.worth(world, "potato", 2, "worst")
  T.eq(worth, 2, "two of the three plain ones")
  T.near(
    Stand.unitPrice(world, "potato") * worth,
    Market.sellPrice(world, "potato") * tun.stand.priceFraction * 2,
    1e-9
  )
  Ledger.remove(world, "potato", 2, "stand")
  T.same(world.state.quality.potato, { fine = 2 }, "the ledger took the plain ones")
end)

-- Save -------------------------------------------------------------------------------------------------------------

T.test("quality: the tally and the crop's thirst and blight survive a save", function()
  local world = newWorld()
  setTime(world, SUMMER + 2)
  local i = freeTiles(world, 1)[1]
  Ledger.add(world, "radish", 5, "test")
  world.state.quality.radish = { fine = 3 }
  world.state.crops[i] = { id = "carrot", growth = 0.5, moisture = 0.4, thirst = 0.3, blighted = true }
  local data = Save.newSlotData("Quality")
  data.run = world.state
  local disk = serialize.decode(serialize.encode(Save.forDisk(data)))
  Gridpack.unpack(disk.run.grid)
  local back = World.new({ registry = reg, tuning = tun }, disk.run)
  T.same(back.state.quality.radish, { fine = 3 })
  T.eq(back.state.crops[i].thirst, 0.3)
  T.truthy(back.state.crops[i].blighted)
  T.eq(Quality.counts(back, "radish").fine, 3)
end)
