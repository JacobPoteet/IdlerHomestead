-- The explanation card behind a top-bar chip (D72, #158). What a chip is, its unit and what moves it
-- come from data/content/chips.lua; the headline says the current value in plain words, built from the
-- same accessors the chip reads. No balance numbers live here: every figure is read from the sim.

local Alerts = require("src.sim.systems.alerts")
local Animals = require("src.sim.systems.animals")
local Food = require("src.sim.systems.food")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Spoilage = require("src.sim.systems.spoilage")
local Water = require("src.sim.systems.water")

local ChipText = {}

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

local function level(world, kind)
  return Alerts.level(world, kind)
end

local headlines = {}

function headlines.money(world)
  return string.format("You have $%d.", Ledger.get(world, "money"))
end

function headlines.food(world)
  local days = Needs.foodDays(world)
  local text = string.format("About %.1f days of food, at %d calories a day.", days, world.tuning.needs.dailyCalories)
  if level(world, "food") >= 2 then
    text = text .. " Almost out: harvest, fish or buy canned food."
  elseif level(world, "food") == 1 then
    text = text .. " Getting low."
  end
  return text
end

function headlines.condition(world)
  local hp = math.floor(Needs.condition(world) + 0.5)
  local text = string.format("Health %d of %d.", hp, world.tuning.needs.conditionMax)
  if level(world, "condition") >= 2 then
    text = text .. " Dangerously low: eat and keep warm."
  elseif level(world, "condition") == 1 then
    text = text .. " Falling: eat and keep warm."
  end
  return text
end

function headlines.battery(world)
  local truck = world.state.land.truck
  local charge, cap = Power.charge(world, truck), Power.capacity(world, truck)
  local cost = world.tuning.economy.tripCost
  local text = string.format("%.1f of %d kWh stored. A trip to town needs %d.", charge, cap, cost)
  if Market.canTrip(world) then
    text = text .. " Enough for a trip now."
  end
  return text
end

function headlines.surplus(world)
  local _, spare = Food.surpluses(world)
  local _, value, loaded = Market.loadQuote(world)
  local text = spare == 0 and "Nothing spare: everything in stock is kept." or (plural(spare, "unit") .. " above what you keep.")
  if loaded > 0 then
    text = text .. string.format(" %d loaded on the truck, worth $%d in town.", loaded, value)
  else
    text = text .. " The truck is empty."
  end
  return text
end

function headlines.wood(world)
  return string.format("You have %s of wood.", plural(Ledger.get(world, "wood"), "log"))
end

function headlines.firewood(world)
  local warmth, need = Needs.warmthInStock(world), Needs.warmthNeeded(world)
  if need <= 0 then
    return "No fire is needed right now."
  end
  local text = string.format("Enough for about %.1f nights at this season's need.", warmth / need)
  if Needs.heatEfficiency(world) <= 0 then
    text = text .. " No fire is placed to burn it in: place a campfire or stove."
  end
  return text
end

function headlines.spoiled(world)
  local tonight = Spoilage.tonight(world)
  local one = tonight.units == 1
  return string.format(
    "%d %s of food at the end of %s shelf life will rot tonight.",
    tonight.units,
    one and "unit" or "units",
    one and "its" or "their"
  )
end

function headlines.water(world)
  return string.format("The cistern is %d%% full.", math.floor(Water.fraction(world) * 100 + 0.5))
end

function headlines.hens(world)
  local flock = Animals.info(world)
  local text = string.format("%s kept; the coop holds %d.", plural(flock.hens, "hen"), flock.housing)
  if flock.hens > 0 and (flock.hungryDays > 0 or flock.thirstyDays > 0 or flock.feedDays < 1) then
    text = text .. " They are short of feed or water."
  end
  return text
end

function headlines.eggs(world)
  return string.format("%s waiting in the nest box.", plural(Animals.info(world).nest, "egg"))
end

function headlines.goats(world)
  local herd = Animals.goatInfo(world)
  local text = string.format("%s kept; the pen holds %d.", plural(herd.goats, "goat"), herd.housing)
  if herd.goats > 0 and (herd.hungryDays > 0 or herd.thirstyDays > 0 or herd.feedDays < 1) then
    text = text .. " They are short of hay or water."
  end
  return text
end

function headlines.milk(world)
  return string.format("%d units of milk in the pail.", Animals.goatInfo(world).pail)
end

--- The card for a chip id: { title, headline, message, shortcut = { panel, label } or nil }. Errors on an
--- id that has no content entry (a chip added without text).
function ChipText.card(world, id)
  local def = world.registry:get("chips", id)
  local headline = assert(headlines[id], "no headline for chip " .. id)(world)
  local message = table.concat({
    def.about,
    "Counts: " .. def.unit .. ".",
    "Goes up: " .. def.raises,
    "Goes down: " .. def.lowers,
  }, "\n")
  local shortcut
  if def.panel then
    shortcut = { panel = def.panel, label = def.panelLabel }
  end
  return { title = def.name, headline = headline, message = message, shortcut = shortcut }
end

--- Every chip id that has an explanation, in the order of the content file.
function ChipText.ids(world)
  local ids = {}
  for _, def in ipairs(world.registry:all("chips")) do
    ids[#ids + 1] = def.id
  end
  return ids
end

return ChipText
