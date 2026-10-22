-- Plot preview at run start (D200, #384): three offered plots with traits, a risk and reward tag, and the chosen
-- seed becomes the run's seed. Choosing is optional: Head out without a choice takes the first plot.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local Session = require("src.session")
local Run = require("src.meta.run")
local Plots = require("src.sim.plots")
local PlotText = require("src.ui.plot_text")
local Ledger = require("src.sim.systems.ledger")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local ctx = { registry = reg, tuning = tun }

local function newSession(data, seed)
  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  return Session.new({ store = store, slot = 1, data = data, registry = reg, tuning = tun, seed = seed })
end

-- A slot that has just failed a run, so it is recovering.
local function recovering(seed)
  local data = Save.newSlotData("Plots")
  local world = newSession(data, seed or 11).world
  Run.fail(data, world)
  return data
end

T.test("plots: the same seed gives the same summary, and the same base the same offer", function()
  local a, b = Plots.summarize(reg, tun, 4242), Plots.summarize(reg, tun, 4242)
  T.same(a, b)
  T.same(Plots.offer(reg, tun, 99), Plots.offer(reg, tun, 99))
  T.truthy(Plots.offer(reg, tun, 99)[1].seed ~= Plots.offer(reg, tun, 100)[1].seed, "another base, other plots")
end)

T.test("plots: the offer is three distinct plots with levels 1 to 3 and a hazard that carries a bonus", function()
  local seen = {}
  for base = 1, 12 do
    local list = Plots.offer(reg, tun, base)
    T.eq(#list, tun.plots.offered)
    for n, plot in ipairs(list) do
      T.falsy(seen[plot.seed], "no plot seed repeats")
      seen[plot.seed] = true
      for _, trait in ipairs({ "soil", "water", "wood", "sun" }) do
        T.truthy(plot[trait] >= 1 and plot[trait] <= 3, trait .. " is a level 1 to 3")
      end
      T.eq(plot.hazard ~= nil, plot.bonus ~= nil, "a hazard plot, and only it, comes with a bonus")
      T.truthy(PlotText.tag(reg, tun, plot) ~= "", "every plot has a tag")
      T.truthy(PlotText.traits(tun, plot):find("Soil"), "and a trait line")
      T.truthy(PlotText.name(tun, n) ~= "")
    end
  end
end)

T.test("plots: across seeds the traits and hazards vary, so the choice is real", function()
  local levels, hazards, easy = { soil = {}, water = {}, wood = {}, sun = {} }, {}, 0
  for seed = 1, 60 do
    local plot = Plots.summarize(reg, tun, seed * 31)
    for trait, set in pairs(levels) do
      set[plot[trait]] = true
    end
    if plot.hazard then
      hazards[plot.hazard] = true
    else
      easy = easy + 1
    end
  end
  for trait, set in pairs(levels) do
    local n = 0
    for _ in pairs(set) do
      n = n + 1
    end
    T.truthy(n >= 2, trait .. " takes more than one level")
  end
  T.truthy(next(hazards) ~= nil and easy > 0, "some plots have a hazard and some are easy")
end)

T.test("plots: making the offer is cheap (perf check)", function()
  local started = os.clock()
  Plots.offer(reg, tun, 5)
  local ms = (os.clock() - started) * 1000
  T.truthy(ms < tun.perf.testPlotPreviewMs, string.format("three previews took %.0f ms", ms))
end)

T.test("plots: the offer is made once, kept in the slot, and survives a save", function()
  local data = recovering()
  local meta = Run.metaWorld(ctx, data.meta)
  T.eq(data.meta.recovery.plots, nil, "nothing is offered until the recovery scene asks")
  local list = Run.offerPlots(data, meta, 7)
  T.eq(#list, tun.plots.offered)
  T.same(Run.offerPlots(data, meta, 8), list, "asking again keeps the first offer")
  local loaded = serialize.decode(serialize.encode(data))
  T.same(Run.offerPlots(loaded, Run.metaWorld(ctx, loaded.meta)), list, "and a reload shows the same three")
end)

T.test("plots: the chosen plot's seed is the next run's seed", function()
  local data = recovering()
  local list = Run.offerPlots(data, Run.metaWorld(ctx, data.meta), 21)
  Run.choosePlot(data, 3)
  Run.startNext(data)
  T.eq(data.run.seed, list[3].seed)
  local world = newSession(data).world
  T.eq(world.state.seed, list[3].seed, "the session keeps the run state it is given")
end)

T.test("plots: the land the card showed is the land the run gets", function()
  local data = recovering()
  local list = Run.offerPlots(data, Run.metaWorld(ctx, data.meta), 33)
  Run.choosePlot(data, 2)
  Run.startNext(data)
  local world = newSession(data).world
  local grid = world.state.grid
  local fresh = newSession(Save.newSlotData("Fresh"), list[2].seed).world.state.grid
  for i = 1, #grid.terrain do
    T.eq(grid.terrain[i], fresh.terrain[i])
  end
  for anchor, obj in pairs(grid.objects) do
    T.truthy(fresh.objects[anchor] and fresh.objects[anchor].id == obj.id, "same objects")
  end
end)

T.test("plots: skipping the choice takes the first plot, and no offer at all still starts a run", function()
  local data = recovering()
  local list = Run.offerPlots(data, Run.metaWorld(ctx, data.meta), 5)
  Run.startNext(data)
  T.eq(data.run.seed, list[1].seed, "Head out with no choice is the first plot")
  T.truthy(newSession(data).world.state.land.truck, "and it is a normal run")
  local plain = recovering(12)
  Run.startNext(plain)
  T.eq(plain.run, nil, "without an offer the session draws a fresh seed, as before")
  T.truthy(newSession(plain).world.state.seed ~= nil)
end)

T.test("plots: a choice can be changed or cleared, and a bad index is ignored", function()
  local data = recovering()
  Run.offerPlots(data, Run.metaWorld(ctx, data.meta), 5)
  Run.choosePlot(data, 2)
  T.eq(data.meta.recovery.plots.chosen, 2)
  Run.choosePlot(data, 9)
  T.eq(data.meta.recovery.plots.chosen, 2, "no such plot")
  Run.choosePlot(data, nil)
  T.eq(Run.pickedPlot(data), data.meta.recovery.plots.list[1])
end)

T.test("plots: a hazard plot's bonus arrives with the starting kit, once", function()
  local hazard
  for seed = 1, 200 do
    local plot = Plots.summarize(reg, tun, seed * 17)
    if plot.hazard then
      hazard = plot
      break
    end
  end
  T.truthy(hazard, "a hazard plot exists among the seeds")
  local plain = newSession(Save.newSlotData("Plain"), hazard.seed).world
  local data = Save.newSlotData("Bonus")
  data.run = require("src.sim.world").newState(hazard.seed)
  data.run.startBonus = hazard.bonus
  local world = newSession(data).world
  for id, amount in pairs(hazard.bonus) do
    T.eq(Ledger.get(world, id), Ledger.get(plain, id) + amount, id .. " is topped up by the plot's bonus")
  end
  local reloaded =
    newSession({ meta = data.meta, header = data.header, run = serialize.decode(serialize.encode(world.state)) })
  for id in pairs(hazard.bonus) do
    T.eq(Ledger.get(reloaded.world, id), Ledger.get(world, id), "a reload does not give it twice")
  end
end)
