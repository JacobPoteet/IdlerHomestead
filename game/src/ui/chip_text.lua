-- The short modal behind a top-bar chip (D72, D112): one headline status, a few labelled numbers, an
-- optional one-line why and at most one action. The words live in data/content/chips.lua; the state
-- comes from ChipStatus (the same accessors the chip's bar reads) and the numbers from the sim.
-- No balance numbers live here.

local Animals = require("src.sim.systems.animals")
local Food = require("src.sim.systems.food")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Land = require("src.sim.systems.land")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")
local ChipStatus = require("src.ui.chip_status")
local Forecast = require("src.ui.forecast")

local ChipText = {}

--- Row values by chip: key -> list of format arguments (nil or absent = no row).
local values = {}

function values.money(world)
  local _, total = Market.loadQuote(world)
  return { cash = { Ledger.get(world, "money") }, load = total > 0 and { total } or nil }
end

function values.food(world)
  return { days = { Needs.foodDays(world) }, perDay = { world.tuning.needs.dailyCalories } }
end

function values.condition(world)
  return { hp = { math.floor(Needs.condition(world) + 0.5), world.tuning.needs.conditionMax } }
end

function values.battery(world)
  local truck = Land.truck(world)
  return {
    charge = { Power.charge(world, truck), Power.capacity(world, truck) },
    cost = { world.tuning.economy.tripCost },
    rate = { Power.chargeRate(world, truck) },
  }
end

function values.surplus(world)
  local _, spare = Food.surpluses(world)
  local _, worth, loaded = Market.loadQuote(world)
  return { spare = { spare }, loaded = { loaded }, worth = loaded > 0 and { worth } or nil }
end

function values.wood(world)
  local o = Needs.woodOutlook(world)
  local fuel = Needs.fuelId(world)
  local out = { stock = { o.stock, Ledger.capacity(world, fuel) } }
  if o.nights ~= math.huge then
    out.perNight = { o.perNight }
    out.nights = { o.nights }
  end
  return out
end

function values.spoiled(world)
  return { units = { ChipStatus.of(world, "spoiled").units } }
end

function values.water(world)
  local units, capacity = Water.stored(world)
  return { stored = { math.floor(units + 0.5), capacity } }
end

local function feed(days)
  return days ~= math.huge and { days } or nil
end

function values.hens(world)
  local flock = Animals.info(world)
  return { count = { flock.hens, flock.housing }, feedDays = flock.hens > 0 and feed(flock.feedDays) or nil }
end

function values.eggs(world)
  return { nest = { Animals.info(world).nest } }
end

function values.goats(world)
  local herd = Animals.goatInfo(world)
  return { count = { herd.goats, herd.housing }, feedDays = herd.goats > 0 and feed(herd.feedDays) or nil }
end

function values.milk(world)
  return { pail = { Animals.goatInfo(world).pail } }
end

function values.weather()
  return {}
end

--- The weather modal's rows: one per day the forecast shows, "Today: Clear".
local function weatherRows(world)
  local ui = world.tuning.ui
  local rows = {}
  for n, day in ipairs(Weather.outlook(world)) do
    if n > ui.topChips.weatherDays then
      break
    end
    local label = n == 1 and ui.modal.todayLabel
      or n == 2 and ui.modal.tomorrowLabel
      or string.format(ui.modal.inDaysLabel, day.offset)
    rows[#rows + 1] = { label = label, value = world.tuning.weather.kinds[day.kind].label }
  end
  return rows
end

--- The card for a chip id: { title, headline, rows = { { label, value } }, why = string or nil,
--- shortcut = { panel, label } or nil }. Errors on an id that has no content entry or no words for its state.
function ChipText.card(world, id)
  local def = world.registry:get("chips", id)
  local status = ChipStatus.of(world, id)
  local state = status.state
  local headline = assert(def.status[state], "chip " .. id .. " has no words for state " .. state)
  local rows
  if id == "weather" then
    rows = weatherRows(world)
  else
    rows = {}
    local have = assert(values[id], "no values for chip " .. id)(world)
    for _, row in ipairs(def.rows) do
      local args = have[row.key]
      if args then
        rows[#rows + 1] = { label = row.label, value = string.format(row.fmt, unpack(args)) }
      end
    end
  end
  local why = def.why and def.why[state]
  if id == "weather" then
    local threats = Forecast.threats(world)
    why = threats[1] and threats[1][1] or why
  end
  local shortcut
  if def.panel then
    shortcut = { panel = def.panel, label = def.panelLabel }
  end
  return { title = def.name, headline = headline, level = status.level, rows = rows, why = why, shortcut = shortcut }
end

--- Every chip id that has a modal, in the order of the content file.
function ChipText.ids(world)
  local ids = {}
  for _, def in ipairs(world.registry:all("chips")) do
    ids[#ids + 1] = def.id
  end
  return ids
end

return ChipText
