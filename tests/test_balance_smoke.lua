-- Smoke test for the balance harness (tools/balance, issue #31): one seed, a short span, every
-- policy. Keeps the harness from rotting; real runs are done with `lovec tools/balance`.
local T = require("harness")

package.path = "tools/balance/?.lua;" .. package.path
local Balance = require("balance")
local Policies = require("policies")

local ctx = Balance.context()
local WEEK = 0.25 -- years: one season (7 days)

-- Determinism is checked once per play path rather than once per test: here for "idle" (the cheapest
-- policy), below for "active" with every feature on, and across the thread boundary for the parallel
-- test. Playing every policy twice here only repeated those checks.
T.test("balance harness: every policy plays one seed for a season", function()
  for _, name in ipairs(Policies.list) do
    local a = Balance.playSeed(ctx, name, 1, WEEK, 1)
    T.eq(#a, 1)
    T.truthy(a[1].snaps[2], name .. " recorded the first morning")
    if name == "idle" then
      local b = Balance.playSeed(ctx, name, 1, WEEK, 1)
      T.eq(a[1].alive, b[1].alive, name .. " alive")
      T.eq(a[1].final.money, b[1].final.money, name .. " money repeats")
      T.eq(a[1].final.warmth, b[1].final.warmth, name .. " warmth repeats")
    end
  end
end)

T.test("balance harness: summaries, careers after failure, and tuning overrides", function()
  local starter = ctx.tuning.farming.starterField
  ctx.tuning.farming.starterField = {} -- the routine plans no field (#66 fixed that), so the idle player starves
  local results = Balance.playSeed(ctx, "idle", 1, WEEK, 2)
  ctx.tuning.farming.starterField = starter
  T.eq(results[1].alive, false, "an idle player with no field starves in the first spring")
  T.eq(results[1].cause, "hunger")
  T.eq(results[2] and results[2].run, 2, "a failed run is followed by a second run")
  local summary = Balance.summarize(ctx, { results[1] }, 1)
  T.eq(summary.n, 1)
  T.eq(summary.failed, 1)
  T.eq(#summary.points, #ctx.tuning.time.seasons)
  T.truthy(Balance.jsonEncode(summary):find("daysSurvived", 1, true))
  T.errors(function()
    Balance.applyOverrides({ "needs.noSuchKnob=1" })
  end, "no such number")
end)

-- Parallel seeds (parallel.lua, worker.lua; issue #123) -------------------------------------------

local Parallel = require("parallel")

T.test("balance parallel: results survive the thread boundary exactly", function()
  local value = { 0.1, 1 / 3, -2.5e-300, 2 ^ 60 + 1, 0, 7, 'a\tb\n"c"', true, { [3] = false, x = { y = math.huge } } }
  local back = Parallel.decode(Parallel.encode(value))
  T.same(back, value)
  T.eq(Parallel.decode(Parallel.encode(-math.huge)), -math.huge)
  local nan = Parallel.decode(Parallel.encode(0 / 0))
  T.truthy(nan ~= nan, "NaN stays NaN")
end)

T.test("balance parallel: worker threads give the same results as playing in this thread", function()
  local years, all = 0.125, require("features").parse("all")
  local played = Parallel.play({
    names = { "idle", "scripted" },
    seeds = 2,
    seed0 = 3,
    years = years,
    runs = 1,
    sets = {},
    jobs = 2,
  })
  for _, name in ipairs({ "idle", "scripted" }) do
    for seed = 3, 4 do
      local here = Balance.playSeed(ctx, name, seed, years, 1, all)
      T.same(played[name][seed], here, name .. " seed " .. seed .. " matches")
    end
  end
  T.errors(function()
    Parallel.play({ names = { "nope" }, seeds = 1, seed0 = 1, years = years, runs = 1, jobs = 2 })
  end, "unknown policy")
end)

-- Optional policy behaviours (features.lua) ----------------------------------------------------------

local Features = require("features")
local World = require("src.sim.world")
local Inventory = require("src.sim.systems.inventory")
local Stand = require("src.sim.systems.stand")
local Crops = require("src.sim.systems.crops")
local Ledger = require("src.sim.systems.ledger")
local Water = require("src.sim.systems.water")
local Grid = require("src.sim.grid")

local function newWorld(seed)
  return World.new({ registry = ctx.registry, tuning = ctx.tuning }, World.newState(seed or 1))
end

T.test("balance features: parse and label", function()
  T.eq(Features.label(Features.parse(nil)), "cat,stand,chickens,goats,water,power,machines,finds,weather")
  T.eq(Features.label(Features.parse("all")), Features.label(Features.parse(nil)))
  T.eq(Features.label(Features.parse("none")), "none")
  T.eq(Features.label(Features.parse("power,cat")), "cat,power", "reports use the canonical order")
  T.errors(function()
    Features.parse("nonsense")
  end, "unknown feature")
end)

T.test("balance features: shopping list is strict-priority and feature-gated", function()
  local none = Features.shopping({})
  T.eq(#none.early + #none.rest, 0)
  local both = Features.shopping(Features.parse("cat,water"))
  T.eq(both.early[1].id, "shelter_cat")
  T.eq(both.rest[1].id, "well")
  -- Every id on the list is a real catalog item.
  for _, id in ipairs(Features.studyIds(Features.parse("all"))) do
    ctx.registry:get("catalog", id)
  end
  -- Saving up: the cistern is known but unaffordable, so nothing after it is ordered.
  local world = newWorld(1)
  world.meta.journal.known.well = true
  world.meta.journal.known.cistern = true
  Ledger.add(world, "money", 30)
  Features.buy(world, both.rest, 0)
  T.eq(Features.held(world, "well"), 1, "the well is affordable")
  T.eq(Features.held(world, "cistern"), 0, "the cistern is not (saving up)")
end)

T.test("balance features: the stand is placed beside the road and opens", function()
  local world = newWorld(1)
  Inventory.addObject(world, "roadside_stand")
  T.truthy(Features.place(world, "roadside_stand", 2), "found a legal tile")
  T.truthy(Stand.isOpen(world))
end)

T.test("balance features: a drip line goes where it waters the most planned tiles", function()
  local world = newWorld(1)
  local grid = world.state.grid
  local patch
  for i = 1, #grid.terrain do
    local x, y = Grid.coords(grid, i)
    local ok = x > 4 and y > 4 and x < grid.w - 4 and y < grid.h - 4
    local tiles = {}
    for dy = 0, 2 do
      for dx = 0, 2 do
        if ok then
          local t = Grid.index(grid, x + dx, y + dy)
          ok = Grid.terrain(world, t).tillable and not world.occupancy[t]
          tiles[#tiles + 1] = t
        end
      end
    end
    if ok then
      patch = tiles
      break
    end
  end
  T.truthy(patch, "a free 3x3 patch exists")
  for _, t in ipairs(patch) do
    Crops.setPlan(world, t, "radish")
  end
  Inventory.addObject(world, "drip_line")
  T.truthy(Features.place(world, "drip_line", 2))
  local anchor
  for a, obj in pairs(grid.objects) do
    if obj.id == "drip_line" then
      anchor = a
    end
  end
  local covered = {}
  for _, t in ipairs(Water.dripTiles(world, anchor)) do
    covered[t] = true
  end
  local n = 0
  for _, t in ipairs(patch) do
    n = n + (covered[t] and 1 or 0)
  end
  T.truthy(n >= 6, "the drip line sits beside the patch and covers two columns of it, got " .. n)
end)

T.test("balance features: finds are chosen by need", function()
  local world = newWorld(1)
  local h = {
    warmthDeficit = function()
      return 100
    end,
  }
  local pick = Features.chooseFind(world, { choices = { "loose_cash", "rusty_axe", "stray_cat" } }, h)
  T.eq(pick, "stray_cat", "no cat yet: the cat is wanted most")
  Inventory.addEquipment(world, "shelter_cat")
  pick = Features.chooseFind(world, { choices = { "loose_cash", "stray_cat", "rusty_axe" } }, h)
  T.eq(pick, "rusty_axe", "the owned cat is worthless, the axe is lacking")
  T.eq(
    Features.chooseFind(world, { choices = { "nothing_known", "also_unknown" } }, h),
    "nothing_known",
    "unknown finds keep the offer's order"
  )
end)

T.test("balance harness: policies play a season with every feature on, deterministically", function()
  local all = Features.parse("all")
  for _, name in ipairs({ "scripted", "active" }) do
    local a = Balance.playSeed(ctx, name, 2, WEEK, 1, all)
    if name == "active" then
      local b = Balance.playSeed(ctx, name, 2, WEEK, 1, all)
      T.eq(a[1].final.money, b[1].final.money, name .. " money repeats with features")
    end
    T.truthy(a[1].counters.kwhMade > 0, name .. " counted the energy the panel made")
    T.eq(a[1].features, "cat,stand,chickens,goats,water,power,machines,finds,weather")
  end
  local summary = Balance.summarize(ctx, Balance.playSeed(ctx, "scripted", 2, WEEK, 1, Features.parse("none")), 1)
  T.eq(type(summary.income), "table", "income by source is summarized")
  T.truthy(summary.totals.earned, "per-run totals are summarized")
end)

T.test("balance harness: an idle player with the starter field survives the first spring (#66)", function()
  local results = Balance.playSeed(ctx, "idle", 1, WEEK, 1)
  T.eq(results[1].alive, true, "the routine plans and works a starter field, so day 6 is survived")
end)
