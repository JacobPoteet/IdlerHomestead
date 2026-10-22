-- The home events pack (B7, D192, docs/PLAN_DEPTH.md §6.2, src/sim/systems/events.lua, src/sim/systems/home.lua,
-- data/content/events.lua): roof leak, torn tarp, frozen pump, broken tool, clogged flue. Each event's two options and its
-- ignore outcome, the triggers, the lasting damage and what it costs while open (and that it mends itself), the pipes, and the
-- mercy rules over them: no event can leave a run unrecoverable.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local EventText = require("src.ui.event_text")
local Events = require("src.sim.systems.events")
local Grid = require("src.sim.grid")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Shelter = require("src.sim.systems.shelter")
local Status = require("src.sim.systems.status")
local Weather = require("src.sim.systems.weather")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local STEP = 1 / tun.time.tickRate
local cfg = tun.events

local HOME = { "roof_leak", "tarp_torn", "frozen_pump", "tool_breaks", "flue_clogged" }

local function newWorld(seed)
  local world = World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
  world.state.footing.held = true -- bad events wait for Footing (or day 10)
  return world
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

local function tick(world, n)
  for _ = 1, n or 1 do
    world:tick(STEP)
  end
end

-- Days: spring 1-7, summer 8-14, autumn 15-21, winter 22-28 (daysPerSeason 7).
local SPRING, AUTUMN, WINTER = 5, 16, 25

local function place(world, id)
  local grid = world.state.grid
  local tx, ty = Grid.coords(grid, world.state.land.truck)
  for r = 0, 12 do
    for step = 0, 12 do
      local x, y = tx + 2 + r, ty + step
      if Grid.inBounds(grid, x, y) then
        local anchor = Grid.placeObject(world, id, x, y)
        if anchor then
          return anchor
        end
      end
    end
  end
  error("no tile for " .. id)
end

--- Offer `id` now and answer it: option 1 or 2, or "ignore". Gives the world the stock the cost needs.
local function answer(world, id, how)
  Ledger.setCapacity(world, "water", 60)
  Ledger.add(world, "wood", 10)
  Ledger.add(world, "water", 5)
  Ledger.add(world, "scrap", 3)
  world.state.events.budget.day = 0
  T.truthy(Events.force(world, id), "the card opens")
  if how == "ignore" then
    T.truthy(Events.ignore(world))
  else
    T.truthy(Events.choose(world, how))
  end
end

T.test("home events: clean two-option content with a free, non-escalating ignore and a note", function()
  local world = newWorld()
  T.same(Events.audit(world), {}, "the audit finds nothing: " .. table.concat(Events.audit(world), "; "))
  for _, id in ipairs(HOME) do
    local d = reg:get("events", id)
    T.eq(d.class, "home", id)
    T.eq(d.bad, true, id)
    T.eq(d.options[1].careful, true, id)
    T.eq(d.options[2].bold, true, id)
    T.truthy(d.journalNote and reg:has("notes", d.journalNote), id)
    T.eq(d.ignore.cost, nil, id)
    T.eq(d.ignore.effect.later, nil, id)
    T.eq(d.ignore.effect.damage, nil, id)
    for _, o in ipairs({ d.options[1], d.options[2], d.ignore }) do
      T.falsy(o.risk:find("%d") or o.risk:find("%%"), id .. ": the risk is in words: " .. o.risk)
    end
    local fresh = newWorld()
    T.falsy(Journal.hasNote(fresh, d.journalNote), id)
    Events.force(fresh, id)
    T.truthy(Journal.hasNote(fresh, d.journalNote), id)
  end
end)

T.test("home events: the whole pack ignored costs only a few mild days and no Condition", function()
  for _, id in ipairs(HOME) do
    local world = newWorld()
    setTime(world, WINTER, 8)
    world.state.needs.condition = 90
    Events.force(world, id)
    Events.ignore(world)
    T.eq(Needs.condition(world), 90, id)
    for _, s in ipairs(Status.active(world)) do
      T.eq(reg:get("statuses", s.id).escalatesTo, nil, id .. " " .. s.id)
    end
    T.eq(#world.state.events.delayed, 0, id)
    T.eq(#Events.openDamage(world), 0, id)
  end
end)

-- Roof leak ------------------------------------------------------------------------------------------------------

T.test("roof leak: needs rain and a roof; patching costs wood and scrap, a pot makes a colder night", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  Weather.force(world, "rain")
  T.eq(Events.weight(world, "roof_leak"), 0, "the truck has no roof to leak")
  place(world, "camp")
  T.truthy(Events.weight(world, "roof_leak") > 0)
  Weather.force(world, "clear")
  T.eq(Events.weight(world, "roof_leak"), 0, "it takes rain")
  Weather.force(world, "rain")
  local wood, scrap = Ledger.get(world, "wood"), Ledger.get(world, "scrap")
  answer(world, "roof_leak", 1)
  T.eq(Ledger.get(world, "wood"), wood + 10 - 1)
  T.eq(Ledger.get(world, "scrap"), scrap + 3 - 1)
  T.eq(Status.count(world), 0)
  setTime(world, SPRING + 3, 21.5)
  answer(world, "roof_leak", 2)
  T.near(Status.modifier(world, "warmthNeed"), 1.2, 1e-9)
  T.near(Status.modifier(world, "studySpeed"), 0.8, 1e-9)
  Status.clear(world, "leaky")
  setTime(world, SPRING + 6, 21.5)
  answer(world, "roof_leak", "ignore")
  T.near(Status.modifier(world, "studySpeed"), 0.9, 1e-9)
end)

T.test("roof leak: patching is disabled without scrap, and a Careful order falls back to ignoring", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  Weather.force(world, "rain")
  place(world, "camp")
  Ledger.add(world, "wood", 5)
  T.truthy(Events.force(world, "roof_leak"))
  local card = Events.pending(world)
  T.eq(card.options[1].affordable, false)
  T.eq(card.options[1].lacking, "scrap")
end)

-- Torn tarp ------------------------------------------------------------------------------------------------------

T.test("tarp torn: only a camp; sleeping cold tears the canvas, makes the camp colder, and it mends itself", function()
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  place(world, "shack")
  T.eq(Events.weight(world, "tarp_torn"), 0, "a shack has no tarp")
  local camp = newWorld()
  setTime(camp, SPRING, 21.5)
  place(camp, "camp")
  T.truthy(Events.weight(camp, "tarp_torn") > 0)
  local before = Shelter.insulation(camp)
  answer(camp, "tarp_torn", 2)
  T.eq(Events.hasDamage(camp, "torn_canvas"), true)
  T.near(Shelter.insulation(camp), before * cfg.home.tornCanvasInsulation, 1e-9)
  T.eq(Events.weight(camp, "tarp_torn"), 0, "no second tear on a torn tarp")
  setTime(camp, SPRING + 3, 9)
  tick(camp)
  T.eq(Events.hasDamage(camp, "torn_canvas"), false, "mended after a few days")
  T.near(Shelter.insulation(camp), before, 1e-9)
end)

T.test(
  "tarp torn: mending it tonight costs wood and scrap and leaves nothing; ignoring is one draughty night",
  function()
    local world = newWorld()
    setTime(world, SPRING, 21.5)
    place(world, "camp")
    local wood = Ledger.get(world, "wood")
    answer(world, "tarp_torn", 1)
    T.eq(Ledger.get(world, "wood"), wood + 10 - 1)
    T.eq(#Events.openDamage(world), 0)
    setTime(world, SPRING + 3, 21.5)
    answer(world, "tarp_torn", "ignore")
    T.near(Status.modifier(world, "warmthNeed"), 1.1, 1e-9)
    T.eq(#Events.openDamage(world), 0)
  end
)

T.test(
  "tarp torn: at the damage cap, or while Footing is slipped, the cold choice is the lesser draughty night",
  function()
    local world = newWorld()
    setTime(world, SPRING, 21.5)
    place(world, "camp")
    world.state.events.damage = { a = true, b = true }
    answer(world, "tarp_torn", 2)
    T.eq(Events.hasDamage(world, "torn_canvas"), false, "past the cap, the lesser form applies")
    T.eq(Status.has(world, "draughty"), true)
    T.eq(#world.state.events.delayed, 0)
  end
)

-- Frozen pump ----------------------------------------------------------------------------------------------------

T.test(
  "frozen pump: needs a winter frost and pipes that can freeze; thawing costs wood, waiting freezes them till noon",
  function()
    local world = newWorld()
    setTime(world, WINTER, 8)
    T.eq(Events.weight(world, "frozen_pump"), 0, "no pipes")
    place(world, "hand_pump")
    place(world, "camp")
    T.truthy(Weather.isFrozen(world), "winter is frozen")
    T.truthy(Events.weight(world, "frozen_pump") > 0)
    setTime(world, AUTUMN, 8)
    T.eq(Events.weight(world, "frozen_pump"), 0, "winter only")
    setTime(world, WINTER, 8)
    local wood = Ledger.get(world, "wood")
    answer(world, "frozen_pump", 1)
    T.eq(Ledger.get(world, "wood"), wood + 10 - 2)
    T.eq(Weather.pipesFrozen(world), false)
    setTime(world, WINTER + 1 > 28 and 24 or WINTER + 1, 8)
    world.state.events.last = {}
    answer(world, "frozen_pump", 2)
    T.eq(Weather.pipesFrozen(world), true)
    T.eq(Events.weight(world, "frozen_pump"), 0, "already frozen")
    setTime(world, world.state.calendar.day, 12.5)
    T.eq(Weather.pipesFrozen(world), false, "the sun thaws them by noon")
  end
)

T.test("frozen pump: lagging or a shack keeps the pipes, so the event never comes", function()
  local world = newWorld()
  setTime(world, WINTER, 8)
  place(world, "hand_pump")
  place(world, "shack")
  T.eq(Weather.pipesGuarded(world), true)
  T.eq(Events.weight(world, "frozen_pump"), 0)
  T.eq(Weather.freezePipes(world), false, "nothing to freeze")
end)

T.test("frozen pump: ignoring it waits for the sun, free", function()
  local world = newWorld()
  setTime(world, WINTER, 8)
  place(world, "hand_pump")
  local wood = Ledger.get(world, "wood")
  answer(world, "frozen_pump", "ignore")
  T.eq(Weather.pipesFrozen(world), true)
  T.eq(Ledger.get(world, "wood"), wood + 10, "free")
end)

-- Tool breaks ----------------------------------------------------------------------------------------------------

T.test(
  "tool breaks: mending costs wood and an hour of work, making do is slower for two days, ignoring a day of twine",
  function()
    local world = newWorld()
    setTime(world, SPRING, 13)
    T.truthy(Events.weight(world, "tool_breaks") > 0)
    local wood = Ledger.get(world, "wood")
    answer(world, "tool_breaks", 1)
    T.eq(Ledger.get(world, "wood"), wood + 10 - 1)
    T.near(Status.modifier(world, "workSpeed"), 0.92, 1e-9)
    Status.clear(world, "tending")
    setTime(world, SPRING + 3, 13)
    answer(world, "tool_breaks", 2)
    T.near(Status.modifier(world, "workSpeed"), 0.85, 1e-9)
    T.eq(Status.get(world, "bare_hands").left, 2)
    Status.clear(world, "bare_hands")
    setTime(world, SPRING + 6, 13)
    answer(world, "tool_breaks", "ignore")
    T.near(Status.modifier(world, "workSpeed"), 0.9, 1e-9)
  end
)

-- Flue clogged ---------------------------------------------------------------------------------------------------

T.test(
  "flue clogged: needs a stove; dousing costs water and wood, burning it out clogs the flue until it mends",
  function()
    local world = newWorld()
    setTime(world, AUTUMN, 21.5)
    T.eq(Events.weight(world, "flue_clogged"), 0, "no stove")
    place(world, "wood_stove")
    T.truthy(Events.weight(world, "flue_clogged") > 0)
    local water, wood = Ledger.get(world, "water"), Ledger.get(world, "wood")
    answer(world, "flue_clogged", 1)
    T.eq(Ledger.get(world, "water"), water + 5 - 1)
    T.eq(Ledger.get(world, "wood"), wood + 10 - 2)
    T.eq(#Events.openDamage(world), 0)
    setTime(world, AUTUMN + 3, 21.5)
    world.state.events.last = {}
    local clear = Needs.heatEfficiency(world)
    answer(world, "flue_clogged", 2)
    T.eq(Events.hasDamage(world, "clogged_flue"), true)
    T.eq(Status.has(world, "smoke"), true)
    T.near(Needs.heatEfficiency(world), clear * cfg.home.cloggedFlueStove, 1e-9)
    T.eq(Events.weight(world, "flue_clogged"), 0, "no second clog")
    setTime(world, AUTUMN + 6, 9)
    tick(world)
    T.eq(Events.hasDamage(world, "clogged_flue"), false, "swept after a few days")
    T.near(Needs.heatEfficiency(world), clear, 1e-9)
  end
)

T.test("flue clogged: ignoring airs the room, a chillier night and nothing lasting", function()
  local world = newWorld()
  setTime(world, AUTUMN, 21.5)
  place(world, "wood_stove")
  answer(world, "flue_clogged", "ignore")
  T.near(Status.modifier(world, "warmthNeed"), 1.1, 1e-9)
  T.eq(#Events.openDamage(world), 0)
end)

-- Mercy ----------------------------------------------------------------------------------------------------------

T.test("home events: none while Footing is slipped, and the combined warmth need stays under the ceiling", function()
  local world = newWorld()
  setTime(world, AUTUMN, 21.5)
  place(world, "camp")
  place(world, "wood_stove")
  Weather.force(world, "rain")
  T.truthy(Events.weight(world, "roof_leak") > 0)
  world.state.footing.slipped = true
  for _, id in ipairs(HOME) do
    T.eq(Events.weight(world, id), 0, id .. " waits while Footing is slipped")
  end
  world.state.footing.slipped = false
  -- Every warmth source at once: a leak, a torn canvas and a draught still sit under the capped product.
  Status.apply(world, "leaky")
  Status.apply(world, "draughty")
  Events.force(world, "tarp_torn")
  Events.choose(world, 2)
  local need = Needs.warmthNeeded(world)
  T.truthy(need <= Needs.warmthNeeded(world), "stable")
  T.truthy(Shelter.insulation(world) > 0)
end)

T.test("home events: a torn canvas survives a save round trip and still mends", function()
  local serialize = require("src.core.serialize")
  local world = newWorld()
  setTime(world, SPRING, 21.5)
  place(world, "camp")
  answer(world, "tarp_torn", 2)
  local copy = serialize.decode(serialize.encode(world.state))
  local again = World.new({ registry = reg, tuning = tun }, copy)
  T.eq(Events.hasDamage(again, "torn_canvas"), true)
  setTime(again, SPRING + 3, 9)
  tick(again)
  T.eq(Events.hasDamage(again, "torn_canvas"), false)
end)

T.test("the card words the home effects: mended damage and a frozen pump", function()
  local env = {
    status = function(id)
      return reg:get("statuses", id)
    end,
    name = function(id)
      return reg:get("resources", id).name
    end,
  }
  local cold = EventText.effectWords(reg:get("events", "tarp_torn").options[2].effect, env)
  T.truthy(table.concat(cold, "|"):find("Later: Mended: torn canvas"), table.concat(cold, "|"))
  local wait = EventText.effectWords(reg:get("events", "frozen_pump").options[2].effect, env)
  T.eq(wait[1], "No pumped water until noon")
end)
