-- First-time user experience: tip cards chosen by events, saved per slot (D69, #152).
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local serialize = require("src.core.serialize")
local Save = require("src.core.save")
local World = require("src.sim.world")
local Ftue = require("src.sim.systems.ftue")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local Land = require("src.sim.systems.land")
local Run = require("src.meta.run")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local RATE = tun.time.tickRate

--- A world whose slot meta has the tips on (`on` ~= false) or is a pre-D69 slot (`legacy`).
local function newWorld(opts)
  opts = opts or {}
  local meta = opts.meta or {}
  if not opts.legacy and not meta.ftue then
    Ftue.begin(meta, opts.on ~= false)
  end
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(opts.seed or 1)), meta
end

-- Game time passes without the rest of the sim running, so its own events (a first idea, a hunger
-- hint ...) cannot get in the way of the one the test is about.
local function run(world, seconds)
  world.state.calendar.elapsed = world.state.calendar.elapsed + seconds
  Ftue.tick(world)
end

-- The whole sim for `seconds`.
local function tickRun(world, seconds)
  for _ = 1, math.ceil(seconds * RATE) do
    world:tick(1 / RATE)
  end
end

local function currentId(world)
  local card = Ftue.current(world)
  return card and card.id
end

-- Run past the minimum gap so the next queued card may show.
local function pastGap(world)
  run(world, tun.ftue.minGap + 1)
end

-- Show and dismiss every card that becomes due, returning their ids in order (other systems answer
-- the events a test emits, so a test looks for its own card in the list).
local function drain(world)
  local shown = {}
  for _ = 1, 40 do
    pastGap(world)
    local id = currentId(world)
    if not id then
      break
    end
    shown[#shown + 1] = id
    Ftue.dismiss(world, id)
  end
  return shown
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

-- Content ---------------------------------------------------------------------

local function emittedEvents()
  local found = {}
  for _, name in ipairs(require("src.sim.systems.init")) do
    local fh = assert(io.open("game/src/sim/systems/" .. name .. ".lua", "r"))
    local text = fh:read("*a")
    fh:close()
    for event in text:gmatch('emit%(%s*"([%w_.]+)"') do -- (a long call is wrapped after the parenthesis)
      found[event] = true
    end
  end
  -- Events the scene raises for what the player did on screen (hud.*), D89.
  local fh = assert(io.open("game/src/scenes/homestead.lua", "r"))
  local text = fh:read("*a")
  fh:close()
  for event in text:gmatch('emit%("(hud%.[%w_.]+)"') do
    found[event] = true
  end
  return found
end

T.test("ftue content: every trigger and retire event is emitted somewhere in the sim", function()
  local emitted = emittedEvents()
  local ids = {}
  for _, def in ipairs(reg:all("ftue")) do
    ids[def.id] = true
  end
  for _, def in ipairs(reg:all("ftue")) do
    T.truthy(def.trigger or def.after or def.doneFlag, def.id .. " has no way to become due")
    if def.trigger and def.trigger ~= "start" then
      T.truthy(emitted[def.trigger], def.id .. " listens for " .. def.trigger .. ", which nothing emits")
    end
    for _, event in ipairs(def.retire or {}) do
      T.truthy(emitted[event], def.id .. " retires on " .. event .. ", which nothing emits")
    end
    if def.after then
      T.truthy(ids[def.after.step], def.id .. " follows an unknown step")
    end
    T.truthy(#def.text > 0 and #def.title > 0)
  end
end)

T.test("ftue content: text tokens resolve from tuning", function()
  local world = newWorld()
  for _, def in ipairs(reg:all("ftue")) do
    local text = Ftue.text(world, def)
    T.falsy(text:find("{", 1, true), def.id .. " has an unresolved token: " .. text)
  end
  T.truthy(Ftue.text(world, reg:get("ftue", "food_clock")):find(tostring(tun.needs.dailyCalories), 1, true))
end)

T.test("ftue: the truck's trip-ready event fires once, when the charge reaches a trip", function()
  local world = newWorld({ on = false })
  local truck = Land.truck(world)
  Power.drain(world, truck, Power.charge(world, truck))
  tickRun(world, 1)
  local count = 0
  world.events:on("market.tripReady", function()
    count = count + 1
  end)
  Power.add(world, truck, tun.economy.tripCost + 1)
  tickRun(world, 1)
  T.eq(count, 1)
  tickRun(world, 2)
  T.eq(count, 1, "does not repeat while it stays ready")
  Power.drain(world, truck, Power.charge(world, truck))
  tickRun(world, 1)
  Power.add(world, truck, tun.economy.tripCost + 1)
  tickRun(world, 1)
  T.eq(count, 2, "fires again after a drive empties it")
  T.truthy(Market.canTrip(world))
end)

-- Progression -------------------------------------------------------------------

T.test("ftue: a new slot shows the welcome card after its delay, and only once", function()
  local world = newWorld()
  T.eq(currentId(world), nil, "not due yet")
  run(world, reg:get("ftue", "welcome").delay + 1)
  T.eq(currentId(world), "welcome")
  Ftue.dismiss(world, "welcome")
  T.eq(currentId(world), nil)
  T.truthy(Ftue.isSeen(world, "welcome"))
  run(world, 600)
  T.truthy(currentId(world) ~= "welcome", "the welcome card does not come back")
end)

T.test("ftue: steps are queued by their events and match the payload", function()
  local world = newWorld()
  Ftue.dismiss(world, "welcome")
  world.events:emit("calendar.newSeason", { season = "winter", year = 1 })
  run(world, 5)
  T.eq(currentId(world), nil, "autumn is matched by season")
  world.events:emit("calendar.newSeason", { season = "autumn", year = 1 })
  T.eq(currentId(world), nil, "not due before its delay")
  T.truthy(contains(drain(world), "autumn"))
end)

T.test("ftue: several due cards come one at a time, in content order, with a gap between", function()
  local world = newWorld()
  Ftue.dismiss(world, "welcome")
  world.events:emit("hud.chipOpened", {}) -- the chip tip (D89) is not part of this test
  pastGap(world)
  -- Emitted in the "wrong" order on purpose.
  world.events:emit("needs.ate", { calories = 100, shortfall = 0 })
  world.events:emit("crop.planted", {})
  run(world, 5)
  T.eq(currentId(world), "water", "content order, not event order")
  Ftue.dismiss(world, "water")
  T.eq(currentId(world), nil, "rate limited right after a card")
  run(world, tun.ftue.minGap - 1)
  T.eq(currentId(world), nil)
  run(world, 2)
  T.eq(currentId(world), "food_clock")
  Ftue.dismiss(world, "food_clock")
  T.eq(currentId(world), nil)
end)

T.test("ftue: a step that already happened is not queued again after it was seen", function()
  local world = newWorld()
  Ftue.dismiss(world, "welcome")
  world.events:emit("hud.chipOpened", {})
  world.events:emit("crop.planted", {})
  run(world, 5)
  Ftue.dismiss(world, "water")
  world.events:emit("crop.planted", {})
  pastGap(world)
  T.eq(currentId(world), nil)
end)

T.test(
  "ftue: plant is due after the welcome if the player does not clear anything, and retires when they plant",
  function()
    local world = newWorld()
    run(world, 5)
    Ftue.dismiss(world, "welcome")
    world.events:emit("hud.chipOpened", {})
    local after = reg:get("ftue", "plant").after.seconds
    run(world, after - 5)
    T.eq(currentId(world), nil)
    run(world, 10)
    run(world, tun.ftue.defaultDelay + 1)
    T.eq(currentId(world), "plant", "the fallback timer")

    local other = newWorld()
    run(other, 5)
    Ftue.dismiss(other, "welcome")
    other.events:emit("hud.chipOpened", {})
    other.events:emit("crop.planted", {})
    T.truthy(Ftue.isSeen(other, "plant"), "planting first retires the plant tip")
    pastGap(other)
    T.eq(currentId(other), "water")
    Ftue.dismiss(other, "water")
    run(other, after + 10)
    T.eq(currentId(other), nil, "no plant card afterwards")
  end
)

T.test("ftue: the spoilage step is told by the D68 card, not by a second one", function()
  local meta = {}
  local world = newWorld({ meta = meta })
  Ftue.skip(world)
  Ftue.setEnabled(world, true) -- nothing queued: the welcome card is out of the way
  T.falsy(Ftue.isSeen(world, "spoil"))
  world.events:emit("food.spoilReport", { lost = {}, total = 0 })
  run(world, 30)
  T.eq(currentId(world), nil, "it never queues a card of its own")
  meta.spoilExplained = true
  T.truthy(Ftue.isSeen(world, "spoil"))
  local listed = {}
  for _, s in ipairs(Ftue.steps(world)) do
    listed[s.def.id] = s.seen
  end
  T.truthy(listed.spoil)
  T.falsy(listed.water)
end)

T.test("ftue: the truck card is dropped when the player already drove to town", function()
  local world = newWorld()
  Ftue.dismiss(world, "welcome")
  world.events:emit("market.trip", {})
  world.events:emit("market.tripReady", {})
  local shown = drain(world)
  T.truthy(contains(shown, "town"))
  T.falsy(contains(shown, "truck_ready"))
  T.truthy(Ftue.isSeen(world, "truck_ready"))
end)

-- Skip, toggle, reset ----------------------------------------------------------------

T.test("ftue: skip stops every card, now and later, and survives a save and load", function()
  local world, meta = newWorld()
  run(world, 5)
  world.events:emit("crop.planted", {})
  Ftue.skip(world)
  T.eq(currentId(world), nil)
  world.events:emit("crop.harvested", {})
  pastGap(world)
  T.eq(currentId(world), nil)

  local store = Save.new(Save.memoryBackend(), { slotCount = 1 })
  local data = Save.newSlotData("Skipper")
  data.meta = meta
  store:write(1, data)
  local loaded = store:read(1)
  T.truthy(loaded.meta.ftue.off)
  local again = newWorld({ meta = loaded.meta })
  world = again
  world.events:emit("crop.harvested", {})
  pastGap(world)
  T.eq(currentId(world), nil, "still off after loading")
end)

T.test("ftue: seen steps and the queue round-trip through a save", function()
  local world, meta = newWorld()
  run(world, 5)
  Ftue.dismiss(world, "welcome")
  world.events:emit("sleep.started", { actor = "x" })
  local copy = serialize.decode(serialize.encode({ meta = meta })).meta
  local loaded = newWorld({ meta = copy })
  loaded.state.calendar.elapsed = world.state.calendar.elapsed -- the run state loads with the meta
  T.truthy(Ftue.isSeen(loaded, "welcome"))
  pastGap(loaded)
  T.eq(currentId(loaded), "bedtime", "the queued card is still waiting")
  Ftue.dismiss(loaded, "bedtime")
  local third = newWorld({ meta = serialize.decode(serialize.encode(copy)) })
  T.truthy(Ftue.isSeen(third, "bedtime"))
  pastGap(third)
  T.eq(currentId(third), nil)
end)

T.test("ftue: a slot saved before the tips existed starts finished", function()
  local old = { career = { runs = 1, history = {} }, spoilExplained = true } -- no meta.ftue
  local world = newWorld({ meta = old, legacy = true })
  T.falsy(Ftue.enabled(world))
  T.truthy(old.ftue.off)
  world.events:emit("crop.planted", {})
  world.events:emit("sleep.started", { actor = "x" })
  run(world, 600)
  T.eq(currentId(world), nil, "veterans are not nagged")
  local fresh = Save.newSlotData("Old")
  fresh.meta = {}
  local loaded = newWorld({ meta = fresh.meta, legacy = true })
  T.falsy(Ftue.enabled(loaded))
end)

T.test("ftue: a brand-new slot starts fresh", function()
  local data = Save.newSlotData("Fresh")
  Ftue.begin(data.meta, true)
  local world = newWorld({ meta = data.meta })
  T.truthy(Ftue.enabled(world))
  for _, s in ipairs(Ftue.steps(world)) do
    T.falsy(s.seen, s.def.id .. " should be unseen")
  end
  run(world, 5)
  T.eq(currentId(world), "welcome")
end)

T.test("ftue: Tips can be turned off and on, and reset brings every tip back", function()
  local world = newWorld()
  run(world, 5)
  Ftue.dismiss(world, "welcome")
  Ftue.setEnabled(world, false)
  world.events:emit("crop.planted", {})
  pastGap(world)
  T.eq(currentId(world), nil)
  Ftue.setEnabled(world, true)
  T.truthy(Ftue.isSeen(world, "welcome"), "turning on keeps what was seen")
  Ftue.reset(world)
  T.falsy(Ftue.isSeen(world, "welcome"))
  run(world, 5)
  T.eq(currentId(world), "welcome")
end)

T.test("ftue: the tips end when the next run begins", function()
  local data = Save.newSlotData("Runs")
  Ftue.begin(data.meta, true)
  Run.career(data.meta)
  Run.startNext(data)
  T.truthy(data.meta.ftue.off)
  local world = newWorld({ meta = data.meta })
  T.eq(currentId(world), nil)
end)

-- Run 2 cards (D99, #173) ----------------------------------------------------------------

--- A slot that has failed once and started its second run: the world for run 2.
local function secondRun(opts)
  local data = Save.newSlotData("Runs")
  Ftue.begin(data.meta, true)
  if opts and opts.skip then
    data.meta.ftue.skipped, data.meta.ftue.off = true, true
  end
  Run.startNext(data) -- run 1 -> 2
  return newWorld({ meta = data.meta }), data
end

T.test("ftue: run 2 shows what carried over, once per slot", function()
  local world, data = secondRun()
  T.truthy(data.meta.ftue.off, "the first-run tips stay off")
  world.events:emit("crop.planted", {})
  run(world, 5)
  T.eq(currentId(world), "carried")
  Ftue.dismiss(world, "carried")
  pastGap(world)
  run(world, 10)
  T.eq(currentId(world), "carried_perks", "follows the first card")
  Ftue.dismiss(world, "carried_perks")
  -- Run 3 does not repeat them.
  Run.startNext(data)
  local third = newWorld({ meta = data.meta })
  run(third, 30)
  T.eq(currentId(third), nil)
  -- Nor does run 2 of the same slot if it is loaded again after they were seen.
  data.meta.career.runs = 2
  local again = newWorld({ meta = data.meta })
  run(again, 30)
  T.eq(currentId(again), nil)
end)

T.test("ftue: skipping the tips also skips the run 2 cards; the first run never shows them", function()
  local world = secondRun({ skip = true })
  run(world, 30)
  T.eq(currentId(world), nil)
  local first = newWorld()
  run(first, 30)
  T.truthy(currentId(first) ~= "carried", "run 1 has the first-run tips only")
  local card = first.meta.ftue.queue
  for _, entry in ipairs(card) do
    T.truthy(entry.id ~= "carried" and entry.id ~= "carried_perks")
  end
end)

-- Determinism -------------------------------------------------------------------------

T.test("ftue: is deterministic and never changes the simulation", function()
  local function play(on)
    local world = newWorld({ on = on, seed = 7 })
    for i = 1, 4000 do
      world:tick(1 / RATE)
      if i == 100 then
        world.events:emit("crop.planted", {})
      end
      local card = Ftue.current(world)
      if card then
        Ftue.dismiss(world, card.id)
      end
    end
    return serialize.encode(world.state), serialize.encode(world.meta.ftue)
  end
  local stateA, ftueA = play(true)
  local stateB, ftueB = play(true)
  T.eq(stateA, stateB)
  T.eq(ftueA, ftueB)
  local stateOff = play(false)
  T.eq(stateA, stateOff, "tips on or off, the world is the same")
end)

T.test("market: the cheapest order is the least price plus delivery fee among items waiting on money (D88)", function()
  local world = newWorld()
  local cheapest = Market.cheapestOrder(world)
  T.truthy(cheapest and cheapest > tun.economy.deliveryFee, "a catalog item is orderable")
  for _, item in ipairs(world.registry:all("catalog")) do
    if
      Market.cannotBuy(world, item.id, false) == nil or Market.cannotBuy(world, item.id, false) == "not enough money"
    then
      T.truthy(Market.itemPrice(world, item.id) + tun.economy.deliveryFee >= cheapest, item.id)
    end
  end
end)

T.test("ftue: the money card comes on the first junk cleared, once, and not for other clutter (D88, #161)", function()
  local world = newWorld()
  Ftue.dismiss(world, "welcome")
  world.events:emit("object.cleared", { object = "brush", tile = 1, yields = {} })
  T.falsy(contains(drain(world), "junk_money"), "brush pays no money")
  world.events:emit("object.cleared", { object = "junk", tile = 2, yields = { money = 3 } })
  T.truthy(contains(drain(world), "junk_money"))
  world.events:emit("object.cleared", { object = "junk", tile = 3, yields = { money = 4 } })
  T.falsy(contains(drain(world), "junk_money"), "told once")
end)

-- Chip step and highlights (D89, #171, #186) ---------------------------------------------

T.test("ftue chips: due after the welcome card, retired by opening any chip", function()
  local w2 = newWorld()
  pastGap(w2)
  T.eq(currentId(w2), "welcome")
  Ftue.dismiss(w2, "welcome")
  run(w2, tun.ftue.minGap + 10)
  run(w2, tun.ftue.defaultDelay + 1)
  T.eq(currentId(w2), "chips", "follows the welcome card")

  local w3 = newWorld()
  pastGap(w3)
  Ftue.dismiss(w3, "welcome")
  w3.events:emit("hud.chipOpened", { chip = "food" })
  run(w3, tun.ftue.minGap + 10)
  T.falsy(contains(drain(w3), "chips"), "no card once a chip was opened")
  T.truthy(Ftue.isSeen(w3, "chips"))
end)

T.test("ftue chips: opening a chip before the welcome card is dismissed retires it too", function()
  local world = newWorld()
  world.events:emit("hud.chipOpened", { chip = "food" })
  T.truthy(Ftue.isSeen(world, "chips"))
  Ftue.dismiss(world, "welcome")
  run(world, tun.ftue.minGap + 10)
  T.falsy(contains(drain(world), "chips"))
end)

T.test("ftue tips list: steps report which were seen", function()
  local world = newWorld()
  local function seen(id)
    for _, s in ipairs(Ftue.steps(world)) do
      if s.def.id == id then
        return s.seen
      end
    end
  end
  T.falsy(seen("welcome"))
  pastGap(world)
  Ftue.dismiss(world, "welcome")
  T.truthy(seen("welcome"))
  T.falsy(seen("water"))
  Ftue.reset(world)
  T.falsy(seen("welcome"), "Show all again forgets them")
end)

T.test("ftue highlight: every target in the content parses", function()
  local n = 0
  for _, def in ipairs(reg:all("ftue")) do
    if def.highlight then
      n = n + 1
      T.truthy(
        def.highlight == "seeds"
          or def.highlight:match("^button:%w+$")
          or def.highlight:match("^chip:%w+$")
          or def.highlight == "tile:truck",
        def.id .. ": " .. def.highlight
      )
    end
  end
  T.truthy(n >= 6)
end)

T.test("ftue highlight: targets resolve to a rect, fall back, and a missing target gives nothing", function()
  local Highlight = require("src.ui.highlight")
  local rects = {
    pantry = { x = 1, y = 2, w = 3, h = 4 },
    tools = { x = 9, y = 9, w = 9, h = 9 },
  }
  local find = {
    button = function(id)
      return rects[id]
    end,
    chip = function(id)
      return id == "food" and { x = 5, y = 0, w = 20, h = 20 } or nil
    end,
    tile = function(name)
      return name == "truck" and { x = 50, y = 50, w = 32, h = 32 } or nil
    end,
    seed = function()
      return nil
    end,
  }
  T.eq(Highlight.resolve("button:pantry", find), rects.pantry)
  T.eq(Highlight.resolve("button:place", find), rects.tools, "a tool not on the bar points at the Tools button")
  T.eq(Highlight.resolve("seeds", find), rects.tools, "no seed button: the Tools button")
  T.eq(Highlight.resolve("chip:food", find).w, 20)
  T.eq(Highlight.resolve("tile:truck", find).x, 50)
  T.eq(Highlight.resolve("button:journal", find), nil, "missing target")
  T.eq(Highlight.resolve("chip:nope", find), nil)
  T.eq(Highlight.resolve("tile:nope", find), nil)
  T.eq(Highlight.resolve("garbage", find), nil)
  T.eq(Highlight.resolve(nil, find), nil)
  T.eq(Highlight.resolve("chip:food", nil), nil)
  local view = { w = 100, h = 100 }
  T.eq(Highlight.visible({ x = 200, y = 0, w = 10, h = 10 }, view), nil, "off screen")
  T.truthy(Highlight.visible({ x = 90, y = 0, w = 30, h = 10 }, view))
  T.eq(Highlight.visible(nil, view), nil)
  T.truthy(Highlight.phase(7.3, 1.2) >= 0 and Highlight.phase(7.3, 1.2) < 1)
end)

T.test("ftue tips list: geometry comes from tuning.ftue, not literals in the scene", function()
  for _, key in ipairs({
    "tipsColumns",
    "tipsMaxColumns",
    "tipsBaseWidth",
    "tipsColumnWidth",
    "tipsMinColumnWidth",
    "tipsViewMargin",
    "tipsRowHeight",
    "tipsRowGap",
    "tipsPadding",
    "tipsHeaderHeight",
    "tipsLegendHeight",
    "tipsTitleTop",
    "tipsLegendNudge",
  }) do
    T.truthy(type(tun.ftue[key]) == "number" and tun.ftue[key] > 0, "tuning.ftue." .. key .. " is a positive number")
  end
  local fh = assert(io.open("game/src/scenes/tips.lua", "r"))
  local text = fh:read("*a")
  fh:close()
  for line in text:gmatch("[^\n]+") do
    local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
    T.falsy(code:find("[^%w_.]%d%d+[^%w_.]") or code:find("[^%w_.]%d%d+$"), "numeric literal in tips.lua: " .. line)
  end
end)

-- The homestead-depth tips (D202, #390) ------------------------------------------------------------------------------

-- A world past the welcome and chip cards, so the step a test is about is the one it looks for.
local function depthWorld(seed)
  local world = newWorld({ seed = seed })
  Ftue.dismiss(world, "welcome")
  world.events:emit("hud.chipOpened", {})
  pastGap(world)
  return world
end

T.test("ftue depth tips: each comes from its own event, once, in the first run", function()
  local cases = {
    { id = "tonight", event = "hud.tonightOpened", payload = {} },
    { id = "event", event = "event.offered", payload = { id = "sprained_ankle", class = "body", bad = true, day = 4 } },
    { id = "night_threat", event = "nightthreat.resolved", payload = { id = "fox", outcome = "turned", lost = {} } },
    { id = "status", event = "status.applied", payload = { id = "ankle_1" } },
    { id = "footing_slipped", event = "footing.slipped", payload = { day = 9, fuel = 0, food = 0 } },
    { id = "soil", event = "crop.harvested", payload = { crop = "radish", tile = 1, amount = 1, repeated = true } },
    { id = "weeds", event = "soil.weeds", payload = { tile = 1, from = 0, to = 0.1, cause = "sprout" } },
    { id = "contracts", event = "contract.offered", payload = { id = 1, def = "radish", standing = false } },
  }
  for n, c in ipairs(cases) do
    local world = depthWorld(20 + n)
    T.falsy(contains(drain(world), c.id), c.id .. " is not due before its event")
    world.events:emit(c.event, c.payload)
    run(world, reg:get("ftue", c.id).delay or 0) -- (a step with a long delay is not due inside drain's first gap)
    T.truthy(contains(drain(world), c.id), c.id .. " comes after " .. c.event)
    world.events:emit(c.event, c.payload)
    T.falsy(contains(drain(world), c.id), c.id .. " comes once")
  end
end)

T.test("ftue depth tips: the soil and weeds tips match their payloads", function()
  local world = depthWorld(31)
  world.events:emit("crop.harvested", { crop = "radish", tile = 1, amount = 1, repeated = false })
  world.events:emit("soil.weeds", { tile = 1, from = 0.2, to = 0.3, cause = "grow" })
  local shown = drain(world)
  T.falsy(contains(shown, "soil"), "a harvest that rotated its family says nothing")
  T.falsy(contains(shown, "weeds"), "weeds growing on are not the first sprout")
end)

T.test("ftue depth tips: what limits you comes a while after Footing is gained, and points at the goal line", function()
  local world = depthWorld(32)
  world.events:emit("footing.gained", { day = 7 })
  run(world, reg:get("ftue", "bottleneck").delay - 1)
  T.falsy(currentId(world) == "bottleneck", "the Footing card is read first")
  T.truthy(contains(drain(world), "bottleneck"))
  T.eq(reg:get("ftue", "bottleneck").highlight, "button:goal")
end)

T.test("ftue depth tips: nested tuning tokens read the Footing numbers", function()
  local world = newWorld()
  local text = Ftue.text(world, reg:get("ftue", "tonight"))
  T.truthy(text:find(tostring(tun.night.footing.streakNights) .. " good nights", 1, true), text)
  text = Ftue.text(world, reg:get("ftue", "footing_slipped"))
  T.truthy(text:find(tostring(tun.night.footing.regainNights) .. " good nights", 1, true), text)
end)

T.test("ftue depth tips: none of them come in a later run", function()
  local world, meta = newWorld({ seed = 33 })
  Ftue.endForRun(meta)
  world.events:emit("hud.tonightOpened", {})
  world.events:emit("footing.slipped", { day = 9, fuel = 0, food = 0 })
  T.eq(#drain(world), 0)
end)
