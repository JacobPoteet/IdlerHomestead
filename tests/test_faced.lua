-- The run summary of what came at the homestead (D202, #156): Run.faced reads the night threats, the growing-season threats
-- and the bad events through their systems, the summary keeps it, FacedText words it, and the recovery scene shows it
-- whole, as one line, or not at all, so the free study never runs into the footer.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local World = require("src.sim.world")
local Run = require("src.meta.run")
local Events = require("src.sim.systems.events")
local FacedText = require("src.ui.faced_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.ui.faced

local function newWorld(seed)
  local data = Save.newSlotData("Faced")
  return World.new({ registry = reg, tuning = tun, meta = data.meta }, World.newState(seed or 1)), data
end

-- A run where the fox got in twice and was turned away once, the mice never got in, hail struck twice (once costing
-- crops) and a drought passed, and two bad events and one good one came.
local function eventfulWorld()
  local world, data = newWorld(3)
  world.state.nightthreats.tally.fox = { landed = 2, turned = 1 }
  world.state.nightthreats.tally.mice = { landed = 0, turned = 4 }
  local history = world.state.threats.history
  history[#history + 1] = { year = 1, id = "hail", struck = true, lost = 4, damaged = 1, saved = 2 }
  history[#history + 1] = { year = 2, id = "hail", struck = true, lost = 2, damaged = 1, saved = 2 }
  history[#history + 1] = { year = 1, id = "drought", struck = false, lost = 0, damaged = 0, saved = 0 }
  world.state.events.done.sprained_ankle = 3
  world.state.events.done.festering_cut = 1
  return world, data
end

T.test("faced: a quiet run records empty lists", function()
  local world = newWorld(1)
  local faced = Run.faced(world)
  T.eq(#faced.night, 0)
  T.eq(#faced.field, 0)
  T.eq(#faced.events, 0)
  local lines = FacedText.lines(cfg, reg, faced)
  T.eq(#lines, 1)
  T.eq(lines[1].text, cfg.quiet)
end)

T.test("faced: night threats, field threats summed by threat, and bad events only, in content order", function()
  local world = eventfulWorld()
  local good
  for _, d in ipairs(reg:all("events")) do
    if not d.bad then
      good = d.id
      break
    end
  end
  T.truthy(good, "a good event exists to leave out")
  world.state.events.done[good] = 2
  local faced = Run.faced(world)
  T.eq(#faced.night, 2)
  T.eq(faced.night[1].id, "mice", "content order: mice before the fox")
  T.eq(faced.night[2].landed, 2)
  T.eq(faced.night[2].turned, 1)
  T.eq(#faced.field, 2)
  T.eq(faced.field[1].id, "hail")
  T.eq(faced.field[1].came, 2)
  T.eq(faced.field[1].struck, 2)
  T.eq(faced.field[1].lost, 6)
  T.eq(faced.field[1].damaged, 2)
  T.eq(faced.field[1].saved, 4)
  T.eq(faced.field[2].struck, 0, "the drought never struck")
  T.eq(#faced.events, 2, "the good event is not a misfortune")
  T.eq(faced.events[1].id, "sprained_ankle")
  T.eq(faced.events[1].count, 3)
  local tally = Events.tally(world)
  local counted = {}
  for _, e in ipairs(tally) do
    counted[e.id] = e
  end
  T.eq(counted[good].count, 2)
  T.falsy(counted[good].bad)
end)

T.test("faced: the summary keeps it through a failed run and a save", function()
  local world, data = eventfulWorld()
  world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
  Run.fail(data, world)
  local summary = data.meta.recovery.summary
  T.truthy(summary.faced)
  T.eq(summary.faced.night[2].id, "fox")
  local serialize = require("src.core.serialize")
  local back = serialize.decode(serialize.encode(data))
  T.eq(back.meta.recovery.summary.faced.events[1].count, 3)
end)

T.test("faced text: one line per kind, then what hurt most", function()
  local lines = FacedText.lines(cfg, reg, Run.faced(eventfulWorld()))
  T.eq(#lines, 4)
  T.eq(lines[1].text, "Nights: mice 4, all turned away; fox 3, 2 got in.")
  T.eq(lines[2].text, "Field threats: hail struck 2 times, 6 crops lost, 2 knocked back, 4 saved; drought passed by.")
  T.eq(lines[3].text, "Misfortunes: sprained ankle x3; festering cut.")
  T.eq(lines[4].text, "Hurt most: Sprained ankle (3 times).")
  T.truthy(lines[4].accent)
end)

T.test("faced text: ties go to the night, and nothing that only came and went hurt", function()
  local faced = {
    night = { { id = "fox", landed = 1, turned = 0 }, { id = "mice", landed = 0, turned = 3 } },
    field = { { id = "hail", came = 1, struck = 1, lost = 0, damaged = 0, saved = 5 } },
    events = { { id = "festering_cut", count = 1 } },
  }
  local lines = FacedText.lines(cfg, reg, faced)
  T.eq(lines[#lines].text, "Hurt most: Fox (one night).")
  faced.night[1] = { id = "fox", landed = 0, turned = 2 }
  faced.events = {}
  lines = FacedText.lines(cfg, reg, faced)
  T.eq(lines[2].text, "Field threats: hail struck, 5 saved.")
  T.falsy(lines[#lines].accent, "everything turned away or saved: no hurt-most line")
end)

T.test("faced text: an id no longer in content is left out", function()
  local lines =
    FacedText.lines(cfg, reg, { night = { { id = "gone", landed = 1, turned = 0 } }, field = {}, events = {} })
  T.eq(#lines, 1)
  T.eq(lines[1].text, cfg.quiet)
end)

T.test(
  "faced: the recovery scene shows the summary whole, as one line, or not at all, never into the footer",
  function()
    local Recovery = require("src.scenes.recovery")
    local Text = require("src.ui.text")
    -- The pixel font needs the image module, which a headless run does not load: a flat 9 px line stands in.
    local wrappedHeight, measure = Text.wrappedHeight, Text.measure
    Text.wrappedHeight = function()
      return 9
    end
    Text.measure = function(s)
      return #s * 6, 9
    end
    local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
    local function scene(w, h, faced)
      local world, data = eventfulWorld()
      world.events:emit("needs.depleted", { hunger = 0, cold = 0.7, shelter = "truck" })
      Run.fail(data, world)
      data.meta.recovery.summary.faced = faced and data.meta.recovery.summary.faced or nil
      local s = Recovery.new()
      s.app = { ctx = { tuning = tun, registry = reg, store = store }, view = { w = w, h = h, scale = 1 }, stack = {} }
      s:enter(1, data)
      s:resize({ w = w, h = h, scale = 1 })
      return s
    end
    local tall = scene(390, 844, true)
    T.eq(#tall.facedLines, 4, "a phone held upright has room for all of it")
    T.truthy(tall.facedTitled)
    for _, h in ipairs({ 300, 360, 390 }) do
      local short = scene(640, h, true)
      local b = short.box
      if short.facedLines then
        T.truthy(
          b.y + 150 + short.shift + short:studyHeight() <= b.y + b.h - 40,
          h .. ": shown only where the free study stays above the footer"
        )
      end
    end
    T.eq(scene(640, 300, true).facedLines, nil, "no room at all: the free study comes first")
    T.eq(scene(390, 844, false).facedLines, nil, "a summary saved before D202 shows nothing")
    Text.wrappedHeight, Text.measure = wrappedHeight, measure
  end
)
