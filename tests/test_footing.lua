-- Footing (D162, #341): earned after streakNights good nights in a row, slipped when the reserves fall under a night
-- of fuel or a day of food, regained after regainNights good nights; judged once a day at sunset; run state only;
-- the Tonight card leads only while it is not held or is slipped; the one-time card text.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Calendar = require("src.sim.systems.calendar")
local Footing = require("src.sim.systems.footing")
local FootingText = require("src.ui.footing_text")
local Grid = require("src.sim.grid")
local Inventory = require("src.sim.systems.inventory")
local Journal = require("src.sim.systems.journal")
local Ledger = require("src.sim.systems.ledger")
local Readiness = require("src.sim.systems.readiness")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")

local tun = tuningLoader.load()
local reg = Registry.new():loadAll()
local cfg = tun.night.footing

local function newWorld(seed, meta)
  return World.new({ registry = reg, tuning = tun, meta = meta }, World.newState(seed or 1))
end

local function setTime(world, day, hour)
  local t = world.tuning.time
  world.state.calendar.elapsed = ((day - 1 + hour / 24) - t.startHour / 24) * t.dayLength
  world.state.calendar.day = day
end

--- A world in autumn (so a fire is needed and fuel is counted in nights) with a fire placed.
local function winterWorld(seed, meta)
  local world = newWorld(seed, meta)
  local day = 2 * tun.time.daysPerSeason + 2 -- autumn: a fire is needed and 60 wood (the cap without a shed) carries more than three nights
  setTime(world, day, 12)
  Inventory.addObject(world, "campfire")
  local truck = world.state.land.truck
  for i = 1, #world.state.grid.terrain do
    if Grid.distance(world.state.grid, truck, i) >= 1 and Inventory.canPlace(world, "campfire", i) then
      T.truthy(Inventory.place(world, "campfire", i))
      break
    end
  end
  return world, day
end

local function foodStock(world, days)
  for _, res in ipairs(reg:all("resources")) do
    if res.calories then
      Ledger.remove(world, res.id, Ledger.get(world, res.id))
    end
  end
  Ledger.add(world, "canned_food", days * tun.needs.dailyCalories / reg:get("resources", "canned_food").calories)
end

--- Stock the larder, woodpile and water so tonight is `good` (every test met) or short on `lack`.
local function stockFor(world, good, lack)
  Ledger.remove(world, "wood", Ledger.get(world, "wood"))
  Ledger.add(world, "wood", lack == "fuel" and 0 or good and 150 or 5) -- plenty for several winter nights, or a few logs
  foodStock(world, lack == "food" and 0 or cfg.foodDays + 1)
  world.state.needs.canteen = lack == "water" and 0 or tun.needs.canteenCapacity
  Ledger.remove(world, "water", Ledger.get(world, "water"))
end

local function events(world, name)
  local seen = {}
  world.events:on(name, function(e)
    seen[#seen + 1] = e
  end)
  return seen
end

local function night(world, kind)
  stockFor(world, kind ~= "bad", kind == "bad" and "food" or nil)
  Footing.evaluate(world)
end

-- Earned ------------------------------------------------------------------------------------------------------------

T.test("footing: a new run starts without it, and the knobs are the owner's numbers", function()
  local world = newWorld(1)
  T.falsy(Footing.held(world))
  T.falsy(Footing.slipped(world))
  T.falsy(Footing.paused(world))
  T.truthy(Footing.tonightLeads(world))
  T.eq(cfg.fuelNights, 3)
  T.eq(cfg.foodDays, 3)
  T.eq(cfg.streakNights, 5)
  T.eq(cfg.slipFuelNights, 1)
  T.eq(cfg.slipFoodDays, 1)
  T.eq(cfg.regainNights, 2)
end)

T.test("footing: earned after streakNights good nights in a row, with the event once", function()
  local world = winterWorld(1)
  local gained = events(world, "footing.gained")
  for n = 1, cfg.streakNights - 1 do
    night(world, "good")
    T.falsy(Footing.held(world), "not yet after " .. n .. " nights")
    T.eq(Footing.status(world).streak, n)
  end
  night(world, "good")
  T.truthy(Footing.held(world))
  T.falsy(Footing.slipped(world))
  T.eq(#gained, 1)
  T.eq(Footing.status(world).streak, 0, "the streak is spent")
  T.truthy(Footing.cardDue(world))
  night(world, "good")
  T.eq(#gained, 1, "never gained twice")
end)

T.test("footing: each of the four tests alone keeps a night from counting", function()
  for _, lack in ipairs({ "fuel", "food", "water" }) do
    local world = winterWorld(2)
    stockFor(world, true, lack)
    T.falsy(Footing.goodNight(world), lack .. " short")
  end
  local world = winterWorld(2)
  stockFor(world, true)
  T.truthy(Footing.goodNight(world), "all four met")
  for anchor, obj in pairs(world.state.grid.objects) do
    if reg:get("objects", obj.id).heatSource then
      Grid.removeObject(world, anchor)
    end
  end
  stockFor(world, true)
  T.falsy(Footing.goodNight(world), "no heat source")
  local checks = Footing.checks(world)
  T.eq(checks[1].id, "shelter")
  T.falsy(checks[1].ok)
end)

T.test("footing: a bad night resets the streak", function()
  local world = winterWorld(3)
  for _ = 1, cfg.streakNights - 1 do
    night(world, "good")
  end
  night(world, "bad")
  T.eq(Footing.status(world).streak, 0)
  for _ = 1, cfg.streakNights - 1 do
    night(world, "good")
  end
  T.falsy(Footing.held(world), "the full count starts again")
  night(world, "good")
  T.truthy(Footing.held(world))
end)

-- Slipped and regained ----------------------------------------------------------------------------------------------

local function held(seed)
  local world, day = winterWorld(seed)
  for _ = 1, cfg.streakNights do
    night(world, "good")
  end
  T.truthy(Footing.held(world))
  return world, day
end

T.test("footing: slips when the reserves fall under a night of fuel or a day of food, not before", function()
  local world = held(1)
  local slipped = events(world, "footing.slipped")
  -- Under the earning line but over the slip line: still held.
  foodStock(world, (cfg.foodDays + cfg.slipFoodDays) / 2)
  Footing.evaluate(world)
  T.falsy(Footing.slipped(world), "a thin larder is not a slip")
  night(world, "bad") -- no food at all
  T.truthy(Footing.slipped(world))
  T.truthy(Footing.paused(world), "the longer goals pause")
  T.truthy(Footing.tonightLeads(world))
  T.eq(#slipped, 1)
  T.truthy(Footing.held(world), "slipped is still held: nothing is lost")

  local fuel = held(2)
  Ledger.remove(fuel, "wood", Ledger.get(fuel, "wood"))
  foodStock(fuel, cfg.foodDays + 1)
  Footing.evaluate(fuel)
  T.truthy(Footing.slipped(fuel), "no wood in winter slips it")
end)

T.test("footing: regained after regainNights good nights; a bad night in between starts the count again", function()
  local world = held(1)
  local regained = events(world, "footing.regained")
  night(world, "bad")
  T.truthy(Footing.slipped(world))
  night(world, "good")
  T.eq(Footing.status(world).good, 1)
  night(world, "bad")
  T.eq(Footing.status(world).good, 0)
  night(world, "good")
  T.truthy(Footing.slipped(world), "one good night is not enough")
  night(world, "good")
  T.falsy(Footing.slipped(world))
  T.falsy(Footing.paused(world))
  T.truthy(Footing.held(world))
  T.falsy(Footing.tonightLeads(world))
  T.eq(#regained, 1)
end)

-- The Tonight card's lead -------------------------------------------------------------------------------------------

T.test("footing: the Tonight card leads until Footing is gained, stops, and returns on a slip", function()
  local world, day = winterWorld(4)
  setTime(world, day, 17)
  local due, leads = Readiness.tonightDue(world)
  T.truthy(due and leads, "before Footing it leads")
  for _ = 1, cfg.streakNights do
    night(world, "good")
  end
  due, leads = Readiness.tonightDue(world)
  T.truthy(due, "it is still the evening")
  T.falsy(leads, "after Footing is gained the card does not lead")
  T.falsy(Readiness.tonight(world).leads)
  night(world, "bad")
  due, leads = Readiness.tonightDue(world)
  T.truthy(due and leads, "a slip brings it back")
  night(world, "good")
  night(world, "good")
  T.falsy(select(2, Readiness.tonightDue(world)), "and regaining puts it away again")
end)

-- Judged at dusk ----------------------------------------------------------------------------------------------------

T.test("footing: judged once a day, at the first tick at or after sunset", function()
  local world, day = winterWorld(5)
  stockFor(world, true)
  local _, sunset = Calendar.daylight(world)
  setTime(world, day, sunset - 0.5)
  world:tick(1 / tun.time.tickRate)
  T.eq(world.state.footing.last, 0, "not before sunset")
  setTime(world, day, sunset + 0.1)
  world:tick(1 / tun.time.tickRate)
  T.eq(world.state.footing.last, day)
  T.eq(Footing.status(world).streak, 1)
  world:tick(1 / tun.time.tickRate)
  T.eq(Footing.status(world).streak, 1, "once a day")
  setTime(world, day + 1, sunset + 0.1)
  stockFor(world, true)
  world:tick(1 / tun.time.tickRate)
  T.eq(Footing.status(world).streak, 2, "the next dusk is the next night")
end)

-- Run state only, determinism -----------------------------------------------------------------------------------------

T.test("footing: run state, saved with the run and not the slot's meta; a new run starts without it", function()
  local data = Save.newSlotData("Footing")
  local world = World.new({ registry = reg, tuning = tun, meta = data.meta }, World.newState(1))
  data.run = world.state
  T.truthy(world.state.footing)
  T.eq(data.meta.footing, nil, "nothing in the meta")
  local again = serialize.decode(serialize.encode(Save.forDisk(data)))
  T.eq(again.run.footing.held, false)
  local fresh = World.new({ registry = reg, tuning = tun, meta = data.meta }, World.newState(2))
  T.falsy(Footing.held(fresh))
end)

T.test("footing: the same seed and the same nights give the same state", function()
  local function run()
    local world = winterWorld(9)
    local log = {}
    for _, kind in ipairs({ "good", "good", "bad", "good", "good", "good", "good", "good", "bad", "good", "good" }) do
      night(world, kind)
      local s = Footing.status(world)
      log[#log + 1] = table.concat({ tostring(s.held), tostring(s.slipped), s.streak, s.good }, ":")
    end
    return table.concat(log, ",")
  end
  T.eq(run(), run())
end)

-- The first note and the card ---------------------------------------------------------------------------------------

T.test("footing: the first gain writes the Field Journal note", function()
  local meta = {}
  local world = winterWorld(6, meta)
  T.falsy(Journal.hasNote(world, "found_footing"))
  for _ = 1, cfg.streakNights do
    night(world, "good")
  end
  T.truthy(Journal.hasNote(world, "found_footing"))
end)

T.test("footing: the card text says what was held and what slips it, from the tuning", function()
  local world = winterWorld(7)
  stockFor(world, true)
  local model = FootingText.build(Footing.checks(world), cfg)
  T.eq(#model.rows, 4)
  for _, row in ipairs(model.rows) do
    T.eq(row.level, 0)
    T.eq(row.word, "Held")
    T.truthy(#row.text > 0 and #row.label > 0)
  end
  local notes = model.notes[1].text .. " " .. model.notes[2].text
  T.truthy(notes:find("5 nights", 1, true))
  T.truthy(notes:find("slips", 1, true))
  T.eq(model.title, "Footing")
  Footing.cardShown(world)
  T.falsy(Footing.cardDue(world))
end)
