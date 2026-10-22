-- Night raiders (C2 + C3, #356, D188, docs/PLAN_DEPTH.md §6.1, src/sim/systems/raiders.lua): the raccoon, deer and
-- rabbits, and the black bear, built on the night threat framework. Each is planned at dusk and lands at its hour; a
-- guard from the catalog turns part of the raids back; damage is a share of one store or of a few tiles' yield, never a
-- death; the mercy rules and the content gates hold.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local Actors = require("src.sim.systems.actors")
local Animals = require("src.sim.systems.animals")
local Cat = require("src.sim.systems.cat")
local Crops = require("src.sim.systems.crops")
local Events = require("src.sim.systems.events")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local NightText = require("src.ui.night_text")
local NightThreats = require("src.sim.systems.nightthreats")
local Raiders = require("src.sim.systems.raiders")
local Tasks = require("src.sim.systems.tasks")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local DPS = tun.time.daysPerSeason
local SUMMER, AUTUMN, WINTER = DPS + 1, 2 * DPS + 1, 3 * DPS + 1
local cfg = tun.raiders
local IDS = { "raccoon", "deer", "bear" }

-- Mice would claim the night slot too (they come for the same stores): silence them, this file is about the raiders.
tun.cat.mice.chancePerDay = 0

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true
  world.state.weather.sky.days[1] = "clear"
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- Run `fn` with tuning values overridden, then restore them (also when `fn` fails).
local function with(overrides, fn)
  local saved = {}
  for _, o in ipairs(overrides) do
    saved[#saved + 1] = { o[1], o[2], o[1][o[2]] }
    o[1][o[2]] = o[3]
  end
  local ok, err = pcall(fn)
  for _, s in ipairs(saved) do
    s[1][s[2]] = s[3]
  end
  assert(ok, err)
end

-- Every raider certain, so a test sets one threat's stage and the others stay home: only `id` has a chance.
local function only(id, fn, extra)
  local overrides = {}
  for _, other in ipairs(IDS) do
    overrides[#overrides + 1] = { cfg[other], "chancePerDay", other == id and 8 or 0 }
  end
  for _, o in ipairs(extra or {}) do
    overrides[#overrides + 1] = o
  end
  with(overrides, fn)
end

--- `n` free tillable tiles near the spawn, tilled.
local function field(world, n)
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

--- A night just after sunset on `day`, with the stores a raider wants.
local function duskWorld(seed, day)
  local world = newWorld(seed)
  setTime(world, day, 19.25)
  Ledger.add(world, "potato", 20)
  Ledger.add(world, "smoked_fish", 8)
  Ledger.add(world, "cheese", 4)
  return world
end

local function landAt(world, id)
  setTime(world, Events.slot(world).day, cfg[id].hour + 0.25)
  return NightThreats.land(world)
end

-- Content ----------------------------------------------------------------------------------------------

T.test(
  "raiders: the three threats are content on one handler, the audit finds nothing, each counter carries its guard",
  function()
    local world = newWorld()
    T.same(NightThreats.audit(world), {})
    for _, id in ipairs(IDS) do
      local d = reg:get("night_threats", id)
      T.eq(d.handler, "raiders")
      T.truthy(d.guard and d.counter and d.warn.line and d.outcomes.turned.report and d.outcomes.landed.report)
      T.truthy(reg:get("catalog", d.counter).modifiers[d.guard] > 0, id .. "'s counter carries its guard stat")
      T.truthy(reg:get("catalog", d.counter).equipment, "the counter is equipment")
      T.truthy(cfg[id].maxGuard < 1, "no defence is perfect")
      T.eq(
        reg:get("catalog", d.counter).needs[1],
        d.journalNote,
        "the landed raid writes the note that teaches the counter"
      )
      T.truthy(reg:has("notes", d.journalNote))
    end
    T.same(reg:get("night_threats", "bear").seasons, { "autumn" })
    T.truthy(not reg:get("night_threats", "raccoon").seasons[4], "no raccoon in winter")
    T.eq(reg:has("night_threats", "skunk"), false, "the skunk is cut (D184)")
    T.truthy(cfg.bear.yearScale[1] < cfg.bear.yearScale[2], "a bear is rarer in year 1")
    T.truthy(cfg.deer.browseCut > 0 and cfg.deer.browseCut < 1, "browsing is a share of a harvest, never all of it")
  end
)

-- The raccoon ---------------------------------------------------------------------------------------------

T.test(
  "raiders: a raccoon is planned at dusk, claims the night slot and spoils a share of ONE store, capped",
  function()
    only("raccoon", function()
      local world = duskWorld(3, SUMMER + 2)
      NightThreats.plan(world)
      T.eq(NightThreats.tonight(world).id, "raccoon")
      T.eq(Events.slot(world).kind, "threat", "it claims the night slot")
      T.truthy(NightThreats.sign(world).line:find("raccoon"), "the dusk sign names it")
      local before = { potato = 20, smoked_fish = 8, cheese = 4 }
      T.truthy(landAt(world, "raccoon"))
      local last = NightThreats.history(world)[1]
      T.eq(last.outcome, "landed")
      local lostKinds, units = 0, 0
      for id, n in pairs(before) do
        local took = n - Ledger.get(world, id)
        if took > 0 then
          lostKinds = lostKinds + 1
          units = took
        end
      end
      T.eq(lostKinds, 1, "one kind of food spoiled")
      T.truthy(units >= cfg.raccoon.minLoss and units <= cfg.raccoon.maxLoss)
      T.eq(Ledger.get(world, "smoked_fish"), 8, "the raccoon is not after smoked fish")
    end)
  end
)

T.test("raiders: the raccoon's loss is a share of the store and capped at maxLoss", function()
  only("raccoon", function()
    local world = duskWorld(3, SUMMER + 2)
    Ledger.add(world, "potato", 20) -- 40 in store: 40% would be 16
    local seen
    world.events:on("raider.raided", function(e)
      seen = e
    end)
    NightThreats.plan(world)
    landAt(world, "raccoon")
    T.eq(seen.units, cfg.raccoon.maxLoss)
    T.eq(Ledger.get(world, "potato"), 40 - cfg.raccoon.maxLoss)
  end)
end)

T.test("raiders: lidded bins turn a raccoon back with their guard; the roll is drawn either way", function()
  only("raccoon", function()
    local plans = {}
    for _, equipped in ipairs({ false, true }) do
      local world = duskWorld(5, SUMMER + 2)
      if equipped then
        Inventory.addEquipment(world, "lidded_bins")
      end
      local plan = Raiders.nightPlan(world, 1, reg:get("night_threats", "raccoon"))
      T.truthy(plan)
      plans[#plans + 1] = plan
      plan.guardRoll = 0.5 -- inside the bins' guard (0.8), outside no guard at all
      local result = Raiders.nightLand(world, plan)
      T.eq(result, equipped and "stopped" or "raided")
      if equipped then
        T.eq(Ledger.get(world, "potato"), 20, "nothing was taken")
      end
    end
    T.eq(plans[1].guardRoll, 0.5)
    local a, b = duskWorld(5, SUMMER + 2), duskWorld(5, SUMMER + 2)
    Inventory.addEquipment(b, "lidded_bins")
    local pa = Raiders.nightPlan(a, 1, reg:get("night_threats", "raccoon"))
    local pb = Raiders.nightPlan(b, 1, reg:get("night_threats", "raccoon"))
    T.eq(pa.guardRoll, pb.guardRoll, "the stream does not depend on the guard")
    T.eq(a.state.rng.raccoon.s, b.state.rng.raccoon.s)
  end)
end)

T.test(
  "raiders: a turned-away raid uses the night slot, is tallied as turned and takes nothing; a landed one writes the note",
  function()
    only("raccoon", function()
      local world = duskWorld(2, SUMMER + 2)
      Inventory.addEquipment(world, "lidded_bins")
      NightThreats.plan(world)
      T.truthy(NightThreats.tonight(world))
      world.state.nightthreats.tonight.plan.guardRoll = 0 -- inside the bins' guard
      landAt(world, "raccoon")
      T.eq(NightThreats.tonight(world).outcome, "turned")
      T.eq(NightThreats.counts(world, "raccoon").turned, 1)
      T.eq(Ledger.get(world, "potato"), 20)
      T.eq(Events.slot(world).kind, "threat", "the slot was used")
      T.eq(Journal.hasNote(world, "raccoon_raid"), false, "a raid turned back is no lesson")
      local other = duskWorld(2, SUMMER + 2)
      NightThreats.plan(other)
      other.state.nightthreats.tonight.plan.guardRoll = 1
      landAt(other, "raccoon")
      T.eq(NightThreats.tonight(other).outcome, "landed")
      T.truthy(Journal.hasNote(other, "raccoon_raid"), "a raid that landed teaches the counter")
    end)
  end
)

T.test("raiders: no raccoon without food to take, none before its first day, none in winter", function()
  only("raccoon", function()
    local bare = newWorld(1)
    setTime(bare, SUMMER + 2, 19.25)
    NightThreats.plan(bare)
    T.eq(NightThreats.tonight(bare), nil, "nothing to take")
    local early = duskWorld(1, cfg.raccoon.firstDay - 1)
    NightThreats.plan(early)
    T.eq(NightThreats.tonight(early), nil, "too early in the run")
    local winter = duskWorld(1, WINTER + 2)
    NightThreats.plan(winter)
    T.eq(NightThreats.tonight(winter), nil, "the content's seasons stop it")
  end)
end)

-- Deer and rabbits ------------------------------------------------------------------------------------------

--- A 4 x 3 block of tomatoes (growing) at the spawn; returns the tiles.
local function tomatoField(world)
  local tiles = field(world, 12)
  for _, i in ipairs(tiles) do
    world.state.crops[i] = { id = "tomato", growth = 0.4, moisture = 1, thirst = 0 }
  end
  return tiles
end

T.test(
  "raiders: the crops accessor offers unripe crops on the field's edge, not ripe, resting or browsed ones",
  function()
    local world = newWorld()
    local tiles = tomatoField(world)
    local edge = Crops.edgeTiles(world)
    T.truthy(#edge > 0 and #edge <= #tiles)
    for k = 2, #edge do
      T.truthy(edge[k] > edge[k - 1], "ascending, so seeded picks are deterministic")
    end
    local first = edge[1]
    world.state.crops[first].growth = 1
    T.eq(#Crops.edgeTiles(world), #edge - 1, "a ripe crop is left alone")
    world.state.crops[first].growth = 0.4
    T.truthy(Crops.browse(world, first))
    T.eq(Crops.browse(world, first), false, "browsed once")
    T.truthy(Crops.isBrowsed(world, first))
    T.eq(#Crops.edgeTiles(world), #edge - 1, "a browsed crop is not browsed again")
    T.eq(Crops.edgeTiles(newWorld()) and #Crops.edgeTiles(newWorld()), 0, "no crops, no edge")
  end
)

T.test("raiders: deer browse a few edge crops: they keep growing, give a smaller harvest and never die", function()
  only("deer", function()
    local world = newWorld(6)
    setTime(world, SUMMER + 2, 19.25)
    local tiles = tomatoField(world)
    local planted = #Crops.plantedTiles(world)
    local seen = {}
    world.events:on("crop.browsed", function(e)
      seen[#seen + 1] = e.tile
    end)
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world).id, "deer")
    T.truthy(NightThreats.sign(world).line:find("deer"))
    landAt(world, "deer")
    T.eq(NightThreats.tonight(world).outcome, "landed")
    T.truthy(#seen >= 1 and #seen <= cfg.deer.maxTiles, "at most maxTiles tiles")
    T.eq(#Crops.plantedTiles(world), planted, "no crop died")
    for _, i in ipairs(seen) do
      T.truthy(Crops.isBrowsed(world, i))
      T.near(world.state.crops[i].growth, 0.4, 1e-9, "growth is untouched")
    end
    local inner = 0
    for _, i in ipairs(tiles) do
      inner = inner + (Crops.isBrowsed(world, i) and 1 or 0)
    end
    T.eq(inner, #seen, "only the tiles it reported")
  end)
end)

T.test("raiders: a browsed crop's harvest is cut by browseCut, never to nothing", function()
  local function harvest(browsed)
    local world = newWorld(9)
    local i = field(world, 1)[1]
    world.state.grid.fertility[i] = 1
    world.state.crops[i] = { id = "tomato", growth = 1, moisture = 1, thirst = 0, browsed = browsed or nil }
    local seen
    world.events:on("crop.harvested", function(e)
      seen = e
    end)
    Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
    return seen
  end
  local plain, cut = harvest(false), harvest(true)
  T.eq(plain.browsed, false)
  T.eq(cut.browsed, true)
  T.truthy(cut.amount >= 1, "never nothing")
  T.truthy(cut.amount < plain.amount, "a smaller harvest")
  T.truthy(cut.amount >= math.floor(plain.amount * (1 - cfg.deer.browseCut)) - 1, "by about browseCut")
end)

T.test("raiders: a perennial's browse mark clears when its fruit is picked", function()
  local world = newWorld(9)
  local i = field(world, 1)[1]
  world.state.grid.fertility[i] = 1
  local crop = Crops.newCrop(world, reg:get("crops", "apple"))
  crop.growth, crop.stage, crop.rest, crop.browsed = 1, "mature", false, true
  world.state.crops[i] = crop
  Tasks.get(world, "harvest").complete(world, Actors.homesteader(world), i)
  T.truthy(world.state.crops[i], "the tree stays")
  T.eq(world.state.crops[i].browsed, nil)
end)

T.test("raiders: a scarecrow turns deer back and the crops stay whole", function()
  only("deer", function()
    local world = newWorld(6)
    setTime(world, SUMMER + 2, 19.25)
    tomatoField(world)
    Inventory.addEquipment(world, "scarecrow")
    local plan = Raiders.nightPlan(world, 1, reg:get("night_threats", "deer"))
    T.truthy(plan)
    plan.guardRoll = 0.1 -- inside the scarecrow's guard
    T.eq(Raiders.nightLand(world, plan), "stopped")
    T.eq(#Crops.edgeTiles(world) > 0, true)
    for _, i in ipairs(Crops.plantedTiles(world)) do
      T.eq(Crops.isBrowsed(world, i), false)
    end
  end)
end)

T.test("raiders: no deer without a crop on the edge or a young tree they like", function()
  only("deer", function()
    local world = newWorld(6)
    setTime(world, SUMMER + 2, 19.25)
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world), nil, "an empty field draws no deer")
  end)
  local world = newWorld(6)
  local tiles = field(world, 25) -- a 25-tile field with a young apple in the middle of it
  local crop = Crops.newCrop(world, reg:get("crops", "apple"))
  crop.rest = false
  crop.growth = 0.5
  world.state.crops[tiles[13]] = crop
  T.truthy(Crops.vulnerableTo(world, tiles[13], "deer"))
  local found
  for _, i in ipairs(Crops.edgeTiles(world)) do
    found = found or i == tiles[13]
  end
  T.truthy(found, "a young perennial the deer like is a target wherever it stands")
end)

-- The bear ------------------------------------------------------------------------------------------------------

T.test("raiders: the bear comes in autumn only, rare in year 1, and strips ONE of the stores that smell", function()
  only("bear", function()
    local summer = duskWorld(4, SUMMER + 2)
    NightThreats.plan(summer)
    T.eq(NightThreats.tonight(summer), nil, "not in summer")
    local world = duskWorld(4, AUTUMN + 2)
    NightThreats.plan(world)
    T.eq(NightThreats.tonight(world).id, "bear")
    T.truthy(NightThreats.sign(world).line:find("bear"))
    local before = { smoked_fish = 8, cheese = 4 }
    landAt(world, "bear")
    local kinds, took = 0, 0
    for id, n in pairs(before) do
      local lost = n - Ledger.get(world, id)
      if lost > 0 then
        kinds, took = kinds + 1, lost
      end
    end
    T.eq(kinds, 1, "one store stripped")
    T.truthy(took >= cfg.bear.minLoss and took <= cfg.bear.maxLoss)
    T.eq(Ledger.get(world, "potato"), 20, "fresh produce is the raccoon's, not the bear's")
  end)
end)

T.test("raiders: year 1 is rare for the bear, year 2 is not", function()
  local d = reg:get("night_threats", "bear")
  with({ { cfg.bear, "chancePerDay", 1 } }, function()
    local function nights(year)
      local hits = 0
      for seed = 1, 60 do
        local world = duskWorld(seed, (year - 1) * 4 * DPS + AUTUMN + 2)
        hits = hits + (Raiders.nightPlan(world, 1, d) and 1 or 0)
      end
      return hits
    end
    local one, two = nights(1), nights(2)
    T.truthy(one < two, "fewer bears in year 1 (" .. one .. " against " .. two .. ")")
    T.eq(two, 60, "at full chance every year-2 night brings one")
  end)
end)

T.test("raiders: a bear box turns the bear back", function()
  only("bear", function()
    local world = duskWorld(4, AUTUMN + 2)
    Inventory.addEquipment(world, "bear_box")
    local plan = Raiders.nightPlan(world, 1, reg:get("night_threats", "bear"))
    plan.guardRoll = 0.85 -- inside the box's 0.9 (capped at maxGuard)
    T.eq(Raiders.nightLand(world, plan), "stopped")
    T.eq(Ledger.get(world, "smoked_fish"), 8)
    plan.guardRoll = cfg.bear.maxGuard + 0.01
    T.eq(Raiders.nightLand(world, plan), "raided", "no defence is perfect")
  end)
end)

-- Mercy and the framework -----------------------------------------------------------------------------------

T.test("raiders: while Footing is slipped the chance is scaled down, and nothing here ever kills", function()
  local world = newWorld(2)
  for _, id in ipairs(IDS) do
    local d = reg:get("night_threats", id)
    local normal = NightThreats.scale(world, d)
    world.state.footing.held = false
    world.state.footing.slipped = true
    T.truthy(NightThreats.scale(world, d) <= normal * tun.events.mercy.slippedThreatScale + 1e-9)
    world.state.footing.held = true
    world.state.footing.slipped = false
    T.eq(d.outcomes.landed.capital, nil, id .. " destroys no capital")
  end
end)

T.test("raiders: a raid after a landed threat is eased (the post-bad cooldown)", function()
  local world = newWorld(2)
  local d = reg:get("night_threats", "raccoon")
  local normal = NightThreats.scale(world, d)
  Events.claimSlot(world, "threat", "raccoon")
  Events.slotOutcome(world, "landed")
  T.near(NightThreats.scale(world, d), normal * tun.night.threats.coolingScale, 1e-9)
end)

T.test("raiders: each has its own stream, so adding one never moves the mice or the fox", function()
  local a, b = duskWorld(8, SUMMER + 2), duskWorld(8, SUMMER + 2)
  NightThreats.plan(a)
  Cat.nightPlan(b, 1)
  Animals.nightPlan(b, 1)
  T.eq(a.state.rng.mice.s, b.state.rng.mice.s)
  T.eq(a.state.rng.predators and a.state.rng.predators.s, b.state.rng.predators and b.state.rng.predators.s)
  T.truthy(a.state.rng.raccoon and a.state.rng.deer and a.state.rng.bear, "one stream each")
end)

T.test("raiders: the same seed gives the same night, and the state survives a save round trip", function()
  local function play(seed)
    local world = duskWorld(seed, SUMMER + 2)
    tomatoField(world)
    for _, id in ipairs(IDS) do
      cfg[id].chancePerDay = cfg[id].chancePerDay
    end
    local log = {}
    world.events:on("nightthreat.resolved", function(e)
      log[#log + 1] = e.id .. ":" .. e.outcome .. ":" .. tostring(e.tiles)
    end)
    for day = SUMMER + 2, SUMMER + 5 do
      setTime(world, day, 19.25)
      for _ = 1, 3 do
        world:tick(STEP)
      end
      setTime(world, day, 23.25)
      world:tick(STEP)
    end
    return world, log
  end
  with(
    { { cfg.raccoon, "chancePerDay", 1 }, { cfg.deer, "chancePerDay", 1 }, { cfg.bear, "chancePerDay", 1 } },
    function()
      local a, la = play(11)
      local b, lb = play(11)
      T.same(la, lb)
      T.truthy(#la > 0, "some raider came")
      local copy = serialize.decode(serialize.encode(a.state))
      T.same(copy.nightthreats.history, a.state.nightthreats.history)
      T.same(copy.crops, a.state.crops)
      T.eq(b.state.nightthreats.tally.raccoon ~= nil or b.state.nightthreats.tally.deer ~= nil, true)
    end
  )
end)

-- Words -----------------------------------------------------------------------------------------------------------

T.test("raiders: the words say what a raid took", function()
  local world = newWorld()
  T.eq(
    NightText.raided(world, { id = "raccoon", lost = { potato = 6 } }),
    "A raccoon got into the stores and spoiled 6 potato."
  )
  T.truthy(NightText.raided(world, { id = "deer", tiles = 2 }):find("2 crops"))
  T.eq(
    NightText.raided(world, { id = "bear", lost = { smoked_fish = 1 } }),
    "A bear tore into the stores and took 1 smoked fish."
  )
end)

T.test(
  "raiders: the idle player is not silently punished: a season of certain deer browses, but nothing dies",
  function()
    only("deer", function()
      local world = newWorld(5)
      local tiles = tomatoField(world)
      local planted = #Crops.plantedTiles(world)
      local browsed = 0
      world.events:on("crop.browsed", function()
        browsed = browsed + 1
      end)
      for night = 1, DPS do
        local day = SUMMER + night
        setTime(world, day, 19.25)
        NightThreats.plan(world)
        local before = browsed
        setTime(world, day, cfg.deer.hour + 0.25)
        NightThreats.land(world)
        T.truthy(browsed - before <= cfg.deer.maxTiles, "a night is capped")
      end
      T.eq(#Crops.plantedTiles(world), planted, "every crop is still in the ground")
      T.truthy(browsed <= #tiles, "a crop is browsed once")
    end)
  end
)

T.test("raiders: the food reserve: a raid never takes food under keepFoodDays in stock, feed is fair game", function()
  only("raccoon", function()
    local d = reg:get("night_threats", "raccoon")
    local thin = newWorld(3)
    setTime(thin, SUMMER + 2, 19.25)
    Ledger.add(thin, "potato", 2)
    with({ { tun.raiders.mercy, "keepFoodDays", 1000 } }, function() -- more days than the larder holds
      T.eq(Raiders.nightPlan(thin, 1, d), nil, "nothing it may take")
      Ledger.add(thin, "chicken_feed", 10)
      local plan = Raiders.nightPlan(thin, 1, d)
      T.truthy(plan, "feed is not human food: it may be scattered")
      plan.guardRoll = 1
      T.eq(Raiders.nightLand(thin, plan), "raided")
      T.eq(Ledger.get(thin, "potato"), 2, "the potatoes were kept")
      T.truthy(Ledger.get(thin, "chicken_feed") < 10)
    end)
    local stocked = newWorld(3)
    setTime(stocked, SUMMER + 2, 19.25)
    Ledger.add(stocked, "potato", 20) -- 18000 calories: 12000 may go
    local p2 = Raiders.nightPlan(stocked, 1, d)
    p2.guardRoll = 1
    Raiders.nightLand(stocked, p2)
    local kept = tun.raiders.mercy.keepFoodDays * tun.needs.dailyCalories
    T.truthy(Ledger.get(stocked, "potato") * 900 >= kept, "never under the reserve")
  end)
end)
