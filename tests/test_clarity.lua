-- The clarity batch (D72): chip explanation cards (#158), journal unlock hints (#160), the truck panel's
-- trip numbers (#162), clearer toolbar labels (#168) and the toolbar palette (#17). Sim accessors and
-- pure UI text/layout, so it all runs headless; the real screens are checked with the screenshot driver.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Journal = require("src.sim.systems.journal")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Power = require("src.sim.systems.power")
local ChipStatus = require("src.ui.chip_status")
local ChipStrip = require("src.ui.chip_strip")
local ChipText = require("src.ui.chip_text")
local Truck = require("src.scenes.truck")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local RATE = tun.time.tickRate

local function newWorld(seed)
  return World.new({ registry = reg, tuning = tun }, World.newState(seed or 1))
end

local function words(s)
  local n = 0
  for _ in s:gmatch("%S+") do
    n = n + 1
  end
  return n
end

-- Journal hints (#160) ------------------------------------------------------------------------

T.test("notes: every note has a short hint written as an action", function()
  for _, note in ipairs(reg:all("notes")) do
    T.truthy(type(note.hint) == "string" and #note.hint > 0, note.id .. " has no hint")
    T.truthy(words(note.hint) <= 10, note.id .. " hint is too long: " .. note.hint)
  end
end)

T.test("notes: a hint never names the idea it unlocks", function()
  local nodes = {}
  for _, def in ipairs(reg:all("catalog")) do
    nodes[#nodes + 1] = def
  end
  for _, def in ipairs(reg:all("perks")) do
    nodes[#nodes + 1] = def
  end
  for _, node in ipairs(nodes) do
    for _, noteId in ipairs(node.needs or {}) do
      local hint = reg:get("notes", noteId).hint:lower()
      T.falsy(hint:find(node.name:lower(), 1, true), noteId .. " hint gives away " .. node.name)
    end
  end
end)

T.test("journal: an unknown idea lists the hints of the notes it is missing, and no name", function()
  local world = newWorld()
  -- The smoker needs a first catch and a fish that spoiled.
  local needs = reg:get("catalog", "smoker").needs
  T.truthy(#needs >= 2)
  local missing = Journal.missingNotes(world, "smoker")
  T.eq(#missing, #needs)
  for n, entry in ipairs(missing) do
    T.eq(entry.id, needs[n])
    T.eq(entry.hint, reg:get("notes", entry.id).hint)
  end
  -- Writing one note drops it from the list.
  world.events:emit("fish.caught", { fish = "creek_chub", size = 20, first = true, mode = "idle" })
  world:tick(1 / RATE)
  local after = Journal.missingNotes(world, "smoker")
  T.eq(#after, #needs - 1)
  T.eq(Journal.status(world, "smoker"), "unknown")
end)

T.test("journal: nothing is missing once the item is an idea or known", function()
  local world = newWorld()
  T.eq(#Journal.missingNotes(world, "axe"), 1, "the axe needs the felled-tree note")
  world.events:emit("object.cleared", { object = "tree" })
  world:tick(1 / RATE)
  T.eq(#Journal.missingNotes(world, "axe"), 0)
  T.eq(Journal.status(world, "axe"), "idea")
end)

-- Chip modals and chip status (#158, D112, #267) -------------------------------------------------

local CHIP_IDS = {
  "weather",
  "money",
  "food",
  "condition",
  "battery",
  "surplus",
  "wood",
  "spoiled",
  "water",
  "hens",
  "eggs",
  "goats",
  "milk",
}

--- Every state key a chip's words must cover, by chip: the states ChipStatus can return.
local STATES = {
  weather = { "clear", "cloudy", "rain", "windy", "storm", "cold" },
  money = { "have" },
  food = { "ok", "low", "bad" },
  condition = { "ok", "low", "bad" },
  battery = { "ready", "charging", "draining", "idle" },
  surplus = { "spare", "none" },
  wood = { "ok", "low", "bad", "none", "nofire", "full" },
  spoiled = { "rot" },
  water = { "ok", "low", "bad" },
  hens = { "ok", "short", "none" },
  eggs = { "some", "none" },
  goats = { "ok", "low", "short", "none" },
  milk = { "some", "none" },
}

T.test("chips: every chip has words for each state it can be in", function()
  local world = newWorld()
  for _, id in ipairs(CHIP_IDS) do
    local def = world.registry:get("chips", id)
    for _, state in ipairs(STATES[id]) do
      T.truthy(def.status[state], id .. " has no headline for " .. state)
    end
    for state in pairs(def.status) do
      local known = false
      for _, s in ipairs(STATES[id]) do
        known = known or s == state
      end
      T.truthy(known, id .. " has words for a state that cannot happen: " .. state)
    end
  end
  T.eq(#ChipText.ids(world), #CHIP_IDS, "every chip with content is covered by this test")
end)

T.test("chips: a modal is a short summary, not a paragraph", function()
  local world = newWorld()
  for _, id in ipairs(CHIP_IDS) do
    local card = ChipText.card(world, id)
    T.truthy(card.title and #card.title > 0, id .. " title")
    T.truthy(card.headline and #card.headline > 0, id .. " headline")
    T.truthy(words(card.headline) <= 6, id .. " headline is too long: " .. card.headline)
    T.truthy(#card.rows <= 4, id .. " has too many rows")
    local total = words(card.headline) + (card.why and words(card.why) or 0)
    for _, row in ipairs(card.rows) do
      total = total + words(row.label) + words(row.value)
    end
    T.truthy(total <= 30, id .. " modal is too wordy (" .. total .. " words)")
    if card.why then
      T.truthy(words(card.why) <= 12, id .. " why is too long: " .. card.why)
    end
    if card.shortcut then
      T.truthy(
        ({ pantry = 1, power = 1, water = 1, catalog = 1, truck = 1, load = 1, journal = 1 })[card.shortcut.panel],
        id .. " shortcut panel"
      )
      T.truthy(#card.shortcut.label > 0, id .. " shortcut label")
    end
  end
end)

T.test("chips: the modal and the bar read the same accessors", function()
  local world = newWorld()
  Ledger.add(world, "money", 37, "test")
  T.eq(ChipText.card(world, "money").rows[1].value, "$" .. Ledger.get(world, "money"))
  local food = ChipText.card(world, "food")
  T.truthy(food.rows[2].value:find(tostring(tun.needs.dailyCalories), 1, true), "food names the daily need")
  T.eq(food.level, ChipStatus.of(world, "food").level)
  local truck = Land.truck(world)
  Power.add(world, truck, tun.economy.tripCost + 5)
  T.eq(ChipText.card(world, "battery").headline, "Ready for a trip")
  T.eq(ChipText.card(world, "surplus").headline, "Nothing spare")
  Ledger.add(world, "scrap", 7, "test")
  Market.setLoad(world, "scrap", 3)
  local surplus = ChipText.card(world, "surplus")
  T.eq(surplus.headline, "Goods to sell")
  T.eq(surplus.rows[1].value, "7 units")
  T.eq(surplus.rows[2].value, "3 units")
end)

T.test("chips: food goes from ok to bad as the larder empties", function()
  local world = newWorld()
  Ledger.add(world, "radish", 100, "test")
  T.eq(ChipStatus.of(world, "food").state, "ok")
  T.eq(ChipStatus.of(world, "food").frac, 1, "a full larder fills the bar")
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id), "test")
    end
  end
  T.eq(ChipStatus.of(world, "food").state, "bad")
  T.eq(ChipStatus.of(world, "food").level, 2)
  T.eq(ChipStatus.of(world, "food").frac, 0)
  T.eq(ChipText.card(world, "food").why, "Harvest, fish or buy canned food.")
end)

T.test("chips: the level is never colour alone, a mark follows the number", function()
  local world = newWorld()
  T.eq(tun.ui.topChips.marks[0], "")
  T.truthy(#tun.ui.topChips.marks[1] > 0 and #tun.ui.topChips.marks[2] > 0, "levels 1 and 2 have marks")
  T.truthy(tun.ui.topChips.marks[1] ~= tun.ui.topChips.marks[2], "the marks differ per level")
  Ledger.add(world, "radish", 1, "test")
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id), "test")
    end
  end
  local checked = 0
  for _, e in ipairs(ChipStrip.entries(world)) do
    if e.level > 0 then
      checked = checked + 1
      T.truthy(e.text:find(tun.ui.topChips.marks[e.level], 1, true), e.id .. " shows its level mark")
    end
  end
  T.truthy(checked > 0, "an empty larder raises a mark")
end)

T.test("chips: the truck chip shows a trend arrow and the weather chip shows the forecast", function()
  local world = newWorld()
  local entries = ChipStrip.entries(world)
  T.eq(entries[1].id, "weather")
  T.truthy(#entries[1].icons >= 1 and #entries[1].icons <= tun.ui.topChips.weatherDays)
  local rows = ChipText.card(world, "weather").rows
  T.eq(rows[1].label, tun.ui.modal.todayLabel)
  T.eq(#rows, #entries[1].icons, "the icons and the modal rows show the same days")
  local truck = Land.truck(world)
  local rates = world.state.power.flow.rates
  T.truthy(rates, "the power flow tracks battery rates")
  rates[truck] = 1
  T.eq(ChipStatus.of(world, "battery").trend, 1)
  rates[truck] = -1
  T.eq(ChipStatus.of(world, "battery").trend, -1)
  rates[truck] = 0
  T.eq(ChipStatus.of(world, "battery").trend, 0)
end)

T.test("chips: the chip shortcut opens Power and the food chip opens the Pantry", function()
  local world = newWorld()
  T.eq(ChipText.card(world, "battery").shortcut.panel, "power")
  T.eq(ChipText.card(world, "food").shortcut.panel, "pantry")
  T.eq(ChipText.card(world, "wood").shortcut.panel, "pantry")
end)

-- Truck numbers (#162) ------------------------------------------------------------------------

T.test("power: hoursToCharge follows the battery's net rate", function()
  local world = newWorld()
  local truck = Land.truck(world)
  Power.drain(world, truck, Power.charge(world, truck))
  T.eq(Power.hoursToCharge(world, truck, tun.economy.tripCost), nil, "no rate recorded: not charging")
  world.state.power.flow.rates[truck] = 2
  T.near(Power.hoursToCharge(world, truck, tun.economy.tripCost), tun.economy.tripCost / 2, 1e-9)
  Power.add(world, truck, tun.economy.tripCost)
  T.eq(Power.hoursToCharge(world, truck, tun.economy.tripCost), 0, "already there")
  Power.drain(world, truck, Power.charge(world, truck))
  T.eq(Power.hoursToCharge(world, truck, Power.capacity(world, truck) + 1), nil, "more than it can hold")
end)

T.test("power: the truck's charge rate is recorded by the tick and is positive when spare power charges it", function()
  local world = newWorld()
  local truck = Land.truck(world)
  Power.drain(world, truck, Power.charge(world, truck))
  -- Put the clock at noon so the starter panel is making power, and tick.
  world.state.calendar.elapsed = (12 / 24 - tun.time.startHour / 24) * tun.time.dayLength
  for _ = 1, math.ceil(2 * RATE) do
    world:tick(1 / RATE)
  end
  local rate = Power.chargeRate(world, truck)
  local hours = Power.hoursToCharge(world, truck, tun.economy.tripCost)
  if rate > 0 then
    T.near(hours, (tun.economy.tripCost - Power.charge(world, truck)) / rate, 1e-6)
  else
    T.eq(hours, nil)
  end
end)

T.test("power: a save from before flow.rates reads as not charging", function()
  local world = newWorld()
  local truck = Land.truck(world)
  world.state.power.flow.rates = nil
  T.eq(Power.chargeRate(world, truck), 0)
  T.eq(Power.hoursToCharge(world, truck, tun.economy.tripCost), nil)
  world:tick(1 / RATE) -- and the next tick brings the table back
  T.truthy(world.state.power.flow.rates)
end)

T.test("market: tripStatus gathers charge, trip cost, time to ready and the load's value", function()
  local world = newWorld()
  local truck = Land.truck(world)
  Power.drain(world, truck, Power.charge(world, truck))
  local s = Market.tripStatus(world)
  T.eq(s.ready, false)
  T.eq(s.cost, tun.economy.tripCost)
  T.eq(s.cargo, tun.economy.cargoCapacity)
  T.eq(s.capacity, Power.capacity(world, truck))
  Power.add(world, truck, tun.economy.tripCost)
  T.eq(Market.tripStatus(world).ready, true)
  T.eq(Market.tripStatus(world).hours, 0)
  -- The load's value matches the quote the town uses.
  Ledger.add(world, "scrap", 9, "test")
  Market.setLoad(world, "scrap", 5)
  local _, total, units = Market.loadQuote(world)
  s = Market.tripStatus(world)
  T.eq(s.value, total)
  T.eq(s.units, units)
  T.eq(units, 5)
  T.eq(s.spare, 4, "spare surplus not loaded yet")
end)

T.test("truck panel text: ready, charging with a time, and not charging", function()
  T.eq(Truck.statusText({ ready = true, charge = 25, cost = 20 }), "Trip ready: drive to town")
  T.truthy(Truck.statusText({ ready = false, charge = 5, cost = 20, hours = 7.2 }):find("about 8 hours", 1, true))
  T.truthy(Truck.statusText({ ready = false, charge = 5, cost = 20, hours = nil }):find("not charging", 1, true))
  T.eq(Truck.duration(0.3), "under an hour")
  T.eq(Truck.duration(1), "about 1 hour")
  T.eq(Truck.duration(30), "about 2 days")
  T.eq(Truck.loadText({ units = 0, cargo = 40, value = 0 }), "Load: empty (0 / 40 cargo)")
  T.eq(Truck.loadText({ units = 7, cargo = 40, value = 34 }), "Load: 7 / 40 cargo, worth $34 in town")
  T.eq(Truck.spareText({ spare = 0 }), "Nothing spare left at home to load")
  T.eq(Truck.spareText({ spare = 12 }), "12 spare units at home not loaded")
end)

-- Labels (#168) -------------------------------------------------------------------------------

T.test("labels: the routine list and starting the routine have different names", function()
  local L = tun.ui.labels
  T.truthy(L.routineList ~= L.startRoutine)
  T.truthy(L.routineList:lower():find("list", 1, true), "the edit list says it is a list")
  T.truthy(L.plan:lower():find("field", 1, true), "Plan says what it plans")
  T.truthy(L.fishGuide:lower():find("guide", 1, true), "Fish says it is the guide")
  T.truthy(L.rod ~= "", "the rod has text")
end)

T.test("labels: toolbar and control labels are all different", function()
  local seen = {}
  for key, label in pairs(tun.ui.labels) do
    if key ~= "speed" and key ~= "tripReady" then
      T.falsy(seen[label], key .. " repeats the label of " .. tostring(seen[label]))
      seen[label] = key
    end
  end
end)

T.test("captions: every tool has a caption that says what the next tap does", function()
  local c = tun.ui.captions
  T.truthy(c.rod:find("water", 1, true))
  T.truthy(c.seed:find("%%s"))
  T.truthy(c.plan and c.planSeed:find("%%s") and c.planClear and c.place:find("%%s"))
  T.truthy(tun.ui.hud.countdownLine:find("%%d"))
end)
