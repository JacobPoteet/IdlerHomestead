-- Status chips and the detail card (D167, #346, docs/PLAN_DEPTH.md §7): the words (src/ui/status_text.lua), the run's
-- history of what hurt the homesteader (src/sim/systems/status.lua), its place in the run summary the recovery scene
-- reads, the key and the icons. The layout is in test_hud.lua; the scenes are played by tools/driver/scenarios/status.lua.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local World = require("src.sim.world")
local KeyBindings = require("src.core.key_bindings")
local Run = require("src.meta.run")
local Status = require("src.sim.systems.status")
local StatusText = require("src.ui.status_text")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.ui.status
local manifest = require("assets.manifest")

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function width(s)
  return #s * 6
end

-- History -------------------------------------------------------------------------------------------------------------

T.test("status ui: a run never hurt carries no history, so its saved shape is unchanged", function()
  local world = newWorld(1)
  T.eq(world.state.status.history, nil)
  T.eq(#Status.history(world), 0)
  T.eq(Run.summary(world).hurt, nil, "the summary has no hurt field")
end)

T.test("status ui: every status that takes hold is counted once per hit, in the order first seen", function()
  local world = newWorld(2)
  Status.apply(world, "ankle_1") -- new
  Status.apply(world, "back") -- new
  Status.apply(world, "ankle_1") -- escalates to ankle_2
  Status.apply(world, "back") -- the cap: renewed
  local h = Status.history(world)
  T.eq(#h, 3)
  T.eq(h[1].id, "ankle_1")
  T.eq(h[1].count, 1)
  T.eq(h[2].id, "back")
  T.eq(h[2].count, 2, "a renewal is another hit")
  T.eq(h[3].id, "ankle_2")
  -- Clearing does not erase what happened.
  Status.clear(world, "back")
  T.eq(#Status.history(world), 3)
end)

T.test("status ui: a status dropped from a full list is not recorded", function()
  local world = newWorld(3)
  Status.apply(world, "ankle_3")
  Status.apply(world, "back")
  Status.apply(world, "fever")
  T.eq(Status.apply(world, "burn"), "dropped", "it would not outlast the shortest of the three")
  for _, h in ipairs(Status.history(world)) do
    T.truthy(h.id ~= "burn")
  end
end)

T.test("status ui: the history is in the summary, survives a save and is a copy", function()
  local world = newWorld(4)
  Status.apply(world, "fever")
  Status.apply(world, "burn")
  local summary = Run.summary(world)
  T.eq(#summary.hurt, 2)
  summary.hurt[1].count = 99
  T.eq(Status.history(world)[1].count, 1, "the summary holds a copy")
  local back = serialize.decode(serialize.encode(world.state))
  T.eq(back.status.history[2].id, "burn")
end)

-- Words ---------------------------------------------------------------------------------------------------------------

T.test("status ui: a chip says the main effect and the days left, or the name when that is too wide", function()
  local world = newWorld(5)
  Status.apply(world, "ankle_1")
  local st = Status.get(world, "ankle_1")
  local text = StatusText.chip(cfg, st, 400, width)
  T.eq(text, "Work 50% slower today · 1d")
  local short = StatusText.chip(cfg, st, 60, width)
  T.eq(short, "Hobbling 1d", "the name stands in when the effect does not fit")
  Status.apply(world, "tired") -- no end date
  T.eq(StatusText.chip(cfg, Status.get(world, "tired"), 400, width), "Slower work, slower study · until cured")
end)

T.test("status ui: a modifier reads as words, and a modifier of 1 says nothing", function()
  T.eq(StatusText.effect(cfg, "workSpeed", 0.8), "Work 20% slower")
  T.eq(StatusText.effect(cfg, "workSpeed", 1.25), "Work 25% faster")
  T.eq(StatusText.effect(cfg, "carryCapacity", 0.6), "Carries 40% less")
  T.eq(StatusText.effect(cfg, "conditionDrain", 1), "Loses 1 Condition a day")
  T.eq(StatusText.effect(cfg, "conditionDrain", 0), nil)
  T.eq(StatusText.effect(cfg, "waterNeed", 1), nil)
  -- Every modifier a status can carry has words.
  for _, def in ipairs(reg:all("statuses")) do
    for name in pairs(def.modifiers) do
      T.truthy(cfg.effects[name], def.id .. " carries " .. name .. ", which the card has no words for")
    end
  end
end)

T.test("status ui: the card tells the time left, how it ends and what happens if hurt again", function()
  local world = newWorld(6)
  Status.apply(world, "ankle_2")
  local d = StatusText.detail(cfg, reg, Status.get(world, "ankle_2"), Status.count(world), Status.maxActive(world))
  T.eq(d.title, "Strained ankle")
  T.eq(d.time, "Ends tomorrow morning")
  T.eq(d.how, cfg.clearedBy.time)
  T.truthy(d.worse:find("torn ankle"), "names the next step")
  T.eq(d.footer, "1 of 3 statuses at once")
  T.eq(d.effects[1], "Falls 100% more likely")
  Status.apply(world, "ankle_2")
  Status.apply(world, "ankle_3")
  local top = StatusText.detail(cfg, reg, Status.get(world, "ankle_3"), 1, 3)
  T.eq(top.worse, cfg.capped, "the top of a family cannot get worse")
  T.eq(top.how, cfg.clearedBy.rest)
  local one = StatusText.detail(
    cfg,
    reg,
    { id = "ankle_1", name = "x", line = "y", left = 1, clearedBy = "time", modifiers = {} },
    1,
    3
  )
  T.eq(one.time, cfg.daysLeft.one)
  local open =
    StatusText.detail(cfg, reg, { id = "tired", name = "x", line = "y", clearedBy = "rest", modifiers = {} }, 1, 3)
  T.eq(open.time, cfg.daysLeft.open)
end)

T.test("status ui: the recovery line names what hurt the run, with the count of repeats", function()
  T.eq(StatusText.hurtLine(cfg, reg, nil), nil)
  T.eq(StatusText.hurtLine(cfg, reg, {}), nil)
  T.eq(
    StatusText.hurtLine(cfg, reg, { { id = "ankle_1", count = 1 }, { id = "fever", count = 2 } }),
    "Hurt this run: Hobbling, Fever x2"
  )
  T.eq(StatusText.hurtLine(cfg, reg, { { id = "gone_status", count = 1 } }), nil, "an unknown status is left out")
end)

-- Icons, key -----------------------------------------------------------------------------------------------------------

T.test("status ui: every status family has an icon of its own in the manifest", function()
  local has = function(id)
    return manifest.sprites[id] ~= nil
  end
  T.truthy(has("icon_status"), "the plain icon exists")
  local seen = {}
  for _, def in ipairs(reg:all("statuses")) do
    if not seen[def.family] then
      seen[def.family] = true
      T.truthy(has("icon_status_" .. def.family), def.family .. " has no icon")
      T.eq(StatusText.icon(has, { family = def.family }), "icon_status_" .. def.family)
    end
  end
  T.eq(StatusText.icon(has, { family = "unheard_of" }), "icon_status")
end)

T.test("status ui: H opens the card, it is rebindable and the Controls screen names it", function()
  local map = KeyBindings.keyMap(tun.input, {})
  T.eq(map.h, "status")
  local listed = false
  for _, a in ipairs(tun.input.rebindable) do
    listed = listed or a == "status"
  end
  T.truthy(listed)
  T.truthy(require("src.ui.controls_text").actions.status)
end)
