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
local ChipText = require("src.ui.chip_text")
local Toolbar = require("src.ui.toolbar")
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

-- Chip cards (#158) ---------------------------------------------------------------------------

local CHIP_IDS = { "money", "food", "condition", "battery", "crate", "wood", "firewood", "spoiled", "water", "hens", "eggs", "goats", "milk" }

T.test("chips: every top-bar chip has a card with a unit, a value in words and what moves it", function()
  local world = newWorld()
  for _, id in ipairs(CHIP_IDS) do
    local card = ChipText.card(world, id)
    T.truthy(card.title and #card.title > 0, id .. " title")
    T.truthy(card.headline and #card.headline > 0, id .. " headline")
    T.truthy(card.message:find("Counts:", 1, true), id .. " names its unit")
    T.truthy(card.message:find("Goes up:", 1, true), id .. " says what raises it")
    T.truthy(card.message:find("Goes down:", 1, true), id .. " says what lowers it")
    if card.shortcut then
      T.truthy(({ pantry = 1, power = 1, catalog = 1, truck = 1, journal = 1 })[card.shortcut.panel], id .. " shortcut panel")
      T.truthy(#card.shortcut.label > 0, id .. " shortcut label")
    end
  end
  T.eq(#ChipText.ids(world), #CHIP_IDS, "every chip with content is covered by this test")
end)

T.test("chips: the headline reads the same accessors as the chip", function()
  local world = newWorld()
  Ledger.add(world, "money", 37, "test")
  T.truthy(ChipText.card(world, "money").headline:find("$" .. Ledger.get(world, "money"), 1, true))
  local food = ChipText.card(world, "food").headline
  T.truthy(food:find(tostring(tun.needs.dailyCalories), 1, true), "food names the daily need: " .. food)
  local truck = Land.truck(world)
  Power.add(world, truck, tun.economy.tripCost + 5)
  local battery = ChipText.card(world, "battery").headline
  T.truthy(battery:find("Enough for a trip", 1, true), battery)
  T.truthy(ChipText.card(world, "crate").headline:find("empty", 1, true))
end)

T.test("chips: the truck chip shortcut opens Power and the food chip opens the Pantry", function()
  local world = newWorld()
  T.eq(ChipText.card(world, "battery").shortcut.panel, "power")
  T.eq(ChipText.card(world, "food").shortcut.panel, "pantry")
  T.eq(ChipText.card(world, "wood").shortcut, nil)
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

T.test("market: tripStatus gathers charge, trip cost, time to ready and the crate's value", function()
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
  -- The crate's value matches the quote the town uses.
  local _, total, units = Market.crateQuote(world)
  T.eq(s.value, total)
  T.eq(s.units, units)
end)

T.test("truck panel text: ready, charging with a time, and not charging", function()
  T.eq(Truck.statusText({ ready = true, charge = 25, cost = 20 }), "Trip ready: drive to town")
  T.truthy(Truck.statusText({ ready = false, charge = 5, cost = 20, hours = 7.2 }):find("about 8 hours", 1, true))
  T.truthy(Truck.statusText({ ready = false, charge = 5, cost = 20, hours = nil }):find("not charging", 1, true))
  T.eq(Truck.duration(0.3), "under an hour")
  T.eq(Truck.duration(1), "about 1 hour")
  T.eq(Truck.duration(30), "about 2 days")
  T.eq(Truck.crateText({ units = 0, cargo = 40, value = 0 }), "Sell crate: empty")
  T.eq(Truck.crateText({ units = 7, cargo = 40, value = 34 }), "Sell crate: 7 / 40 cargo, worth $34 in town")
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
  T.truthy(tun.ui.badges.countdown:find("%%d"))
end)

-- Toolbar palette (#17) -----------------------------------------------------------------------

local SIZES = {
  { name = "desktop", w = 1280, h = 720 },
  { name = "phone", w = 390, h = 844 },
  { name = "landscape", w = 844, h = 390 },
  { name = "widget", w = 640, h = 360 },
  { name = "narrow", w = 340, h = 600 },
}

-- Widths as the scene measures them (text widths are close to these in the shipped font).
local function buttons(withPlace, activeId)
  local bw = tun.ui.buttonWidths
  local function b(id, w, extra)
    local t = { id = id, w = w }
    for k, v in pairs(extra or {}) do
      t[k] = v
    end
    return t
  end
  local hand = b("hand", bw.hand)
  local tools = { b("seed:radish", bw.seed), b("seed:potato", bw.seed), b("rod", 62) }
  if withPlace then
    tools[#tools + 1] = b("place", 104, { gapBefore = tun.ui.groupGap })
  end
  tools[#tools + 1] = b("plan", 74, { gapBefore = not withPlace and tun.ui.groupGap or nil })
  local routine, pantry, catalog = b("routineList", 92), b("pantry", bw.pantry), b("catalog", bw.catalog)
  local fish, journal = b("fish", 90), b("journal", bw.journal)
  local left = { hand }
  for _, t in ipairs(tools) do
    left[#left + 1] = t
  end
  left[#left + 1] = routine
  local active
  for _, t in ipairs(tools) do
    if t.id == activeId then
      active = b("active", math.max(bw.activeMin, 70))
    end
  end
  return {
    left = left,
    right = { pantry, catalog, fish, journal },
    fixedLeft = { hand },
    toolsButton = b("tools", bw.tools),
    active = active,
    fixedRight = { pantry, journal },
    moreButton = b("more", bw.more),
    tools = tools,
    more = { routine, catalog, fish },
  }
end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function cfgFor(view)
  local compact = view.w < tun.ui.compactWidth
  return {
    pad = tun.ui.barPadding,
    gap = tun.ui.buttonGap,
    h = compact and tun.ui.compactButtonHeight or tun.ui.buttonHeight,
    margin = tun.ui.barMargin,
    paletteGap = tun.ui.paletteGap,
  }
end

local function inside(r, view)
  return r.x >= 0 and r.y >= 0 and r.x + r.w <= view.w and r.y + r.h <= view.h
end

T.test("toolbar: wide views keep the full bar, narrow ones use the palette", function()
  local desktop = Toolbar.arrange(buttons(true), SIZES[1], cfgFor(SIZES[1]))
  T.eq(desktop.palette, false)
  T.eq(desktop.rows, 1)
  local phone = Toolbar.arrange(buttons(true), SIZES[2], cfgFor(SIZES[2]))
  T.eq(phone.palette, true)
  T.truthy(phone.popups.tools and phone.popups.more)
  local widget = Toolbar.arrange(buttons(true), SIZES[4], cfgFor(SIZES[4]))
  T.eq(widget.palette, true, "640 wide no longer wraps into extra rows")
  T.eq(widget.rows, 1)
end)

T.test("toolbar: at every size nothing overlaps, sits in view, and every button is reachable", function()
  for _, view in ipairs(SIZES) do
    for _, withPlace in ipairs({ false, true }) do
      for _, activeId in ipairs({ "none", "rod", "plan", "place" }) do
        local spec = buttons(withPlace, activeId)
        local cfg = cfgFor(view)
        local out = Toolbar.arrange(spec, view, cfg)
        local where = string.format("%s place=%s active=%s", view.name, tostring(withPlace), activeId)
        -- The bar: inside the view, at least the touch size, no two overlapping.
        for i, a in ipairs(out.bar) do
          T.truthy(inside(a, view), where .. ": " .. a.id .. " is off screen")
          T.truthy(a.h >= tun.input.minTouchTarget and a.w >= tun.input.minTouchTarget, where .. ": " .. a.id .. " is too small")
          T.truthy(a.y >= view.h - out.bottomH, where .. ": " .. a.id .. " is above the bar")
          for j = i + 1, #out.bar do
            T.falsy(overlaps(a, out.bar[j]), where .. ": " .. a.id .. " overlaps " .. out.bar[j].id)
          end
        end
        -- Every tool and book is on the bar or in a palette.
        local reachable = {}
        for _, b in ipairs(out.bar) do
          reachable[b.id] = true
        end
        for _, list in ipairs({ spec.tools, spec.more }) do
          for _, b in ipairs(list) do
            if out.palette then
              local home
              for _, popup in pairs(out.popups) do
                for _, item in ipairs(popup.items) do
                  home = home or item == b
                end
              end
              T.truthy(home or reachable[b.id], where .. ": " .. b.id .. " is in no palette")
            else
              T.truthy(reachable[b.id], where .. ": " .. b.id .. " is not on the bar")
            end
          end
        end
        for _, id in ipairs({ "hand", "pantry", "journal" }) do
          T.truthy(reachable[id], where .. ": " .. id .. " must always be on the bar")
        end
        -- Palettes: inside the view, above the bar, their buttons inside them and clear of each other.
        for name, popup in pairs(out.popups or {}) do
          T.truthy(inside(popup, view), where .. ": the " .. name .. " palette is off screen")
          T.truthy(popup.y + popup.h <= view.h - out.bottomH, where .. ": the " .. name .. " palette covers the bar")
          for i, a in ipairs(popup.items) do
            T.truthy(a.x >= popup.x and a.x + a.w <= popup.x + popup.w and a.y >= popup.y and a.y + a.h <= popup.y + popup.h, where .. ": " .. a.id .. " leaves its palette")
            for j = i + 1, #popup.items do
              T.falsy(overlaps(a, popup.items[j]), where .. ": palette " .. a.id .. " overlaps " .. popup.items[j].id)
            end
          end
        end
      end
    end
  end
end)

T.test("toolbar: the palettes stay clear of the speed, routine and power column", function()
  for _, view in ipairs(SIZES) do
    local cfg = cfgFor(view)
    local out = Toolbar.arrange(buttons(true, "rod"), view, cfg)
    if out.popups then
      -- Three control buttons stacked under the top bar at the right edge.
      local topH = cfg.h + (view.w < tun.ui.compactWidth and tun.ui.statRowHeight + 8 or 0)
      local column = { x = view.w - tun.ui.buttonGap - 120, y = topH + tun.ui.buttonGap, w = 120, h = 3 * (cfg.h + tun.ui.buttonGap) }
      for name, popup in pairs(out.popups) do
        T.falsy(overlaps(popup, column), view.name .. ": the " .. name .. " palette covers the control column")
      end
    end
  end
end)

T.test("toolbar: the tool in hand stays on the bar in palette mode", function()
  local view = SIZES[2]
  local out = Toolbar.arrange(buttons(true, "place"), view, cfgFor(view))
  local found
  for _, b in ipairs(out.bar) do
    found = found or b.id == "active"
  end
  T.truthy(found, "the active tool shortcut is on the bar")
  local none = Toolbar.arrange(buttons(true, "none"), view, cfgFor(view))
  for _, b in ipairs(none.bar) do
    T.falsy(b.id == "active", "no shortcut for the empty hand")
  end
end)
