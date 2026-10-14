-- What a top-bar chip says beyond its number (D112, #267): a fill bar, an alert level (shown as a mark
-- after the number as well as a colour) and a trend arrow. One accessor per chip so the bar and the
-- modal (src/ui/chip_text.lua) always agree. Read-only: it only reads the sim. Thresholds come from
-- tuning.alerts (food, wood, health, animals) and tuning.ui.topChips (the rest).

local Alerts = require("src.sim.systems.alerts")
local Animals = require("src.sim.systems.animals")
local Food = require("src.sim.systems.food")
local Land = require("src.sim.systems.land")
local Ledger = require("src.sim.systems.ledger")
local Market = require("src.sim.systems.market")
local Needs = require("src.sim.systems.needs")
local Power = require("src.sim.systems.power")
local Spoilage = require("src.sim.systems.spoilage")
local Threats = require("src.sim.systems.threats")
local Water = require("src.sim.systems.water")
local Weather = require("src.sim.systems.weather")

local ChipStatus = {}

local function clamp01(x)
  return math.max(0, math.min(1, x))
end

local function levelState(level)
  return level >= 2 and "bad" or level == 1 and "low" or "ok"
end

local function sign(x, minimum)
  return x > minimum and 1 or x < -minimum and -1 or 0
end

--- Is the animal group short of feed or water right now?
local function short(info, count)
  return count > 0 and (info.hungryDays > 0 or info.thirstyDays > 0 or info.feedDays < 1)
end

local status = {}

function status.weather(world)
  local cfg = world.tuning.ui.topChips
  local kind = Weather.kind(world)
  local level = 0
  local state = kind
  if world.tuning.weather.kinds[kind].threat >= cfg.stormThreat then
    level = 1
  end
  for _, t in ipairs(Threats.outlook(world)) do
    level = math.max(level, t.active and 2 or 1)
  end
  if Weather.isColdSnap(world) then
    level, state = 2, "cold"
  end
  return { level = level, state = state }
end

function status.money()
  return { level = 0, state = "have" }
end

function status.food(world)
  local cfg = world.tuning.ui.topChips
  local level = Alerts.level(world, "food")
  return { level = level, state = levelState(level), frac = clamp01(Needs.foodDays(world) / cfg.foodFullDays) }
end

function status.condition(world)
  local level = Alerts.level(world, "condition")
  return {
    level = level,
    state = levelState(level),
    frac = clamp01(Needs.condition(world) / world.tuning.needs.conditionMax),
  }
end

function status.battery(world)
  local truck = Land.truck(world)
  local cfg = world.tuning.ui.topChips
  local capacity = Power.capacity(world, truck)
  local trend = sign(Power.chargeRate(world, truck), cfg.trendMinKw)
  local state = trend > 0 and "charging" or trend < 0 and "draining" or "idle"
  if Market.canTrip(world) and not world.state.market.inTown then
    state = "ready"
  end
  return {
    level = 0,
    state = state,
    trend = trend,
    frac = capacity > 0 and clamp01(Power.charge(world, truck) / capacity) or 0,
  }
end

function status.surplus(world)
  local _, spare = Food.surpluses(world)
  return { level = 0, state = spare > 0 and "spare" or "none" }
end

function status.wood(world)
  local cfg = world.tuning.ui.topChips
  local o = Needs.woodOutlook(world)
  local fuel = Needs.fuelId(world)
  local level = Alerts.level(world, "fuel")
  local state = levelState(level)
  local frac
  if o.nights == math.huge then
    state = "none"
    local capacity = Ledger.capacity(world, fuel)
    frac = capacity > 0 and clamp01(o.stock / capacity) or 0
  else
    frac = clamp01(o.nights / cfg.woodFullNights)
    if o.noFire then
      state = "nofire"
    end
  end
  if Ledger.isFull(world, fuel) then
    level, state = 2, "full" -- a full store is red (D59)
  end
  return { level = level, state = state, frac = frac }
end

function status.spoiled(world)
  return { level = 2, state = "rot", units = Spoilage.tonight(world).units }
end

function status.water(world)
  local cfg = world.tuning.ui.topChips
  local frac = Water.fraction(world)
  local level = frac < cfg.waterRed and 2 or frac < cfg.waterAmber and 1 or 0
  local trend = (Weather.isRaining(world) and frac < 1) and 1 or 0
  return { level = level, state = levelState(level), frac = frac, trend = trend }
end

function status.hens(world)
  local flock = Animals.info(world)
  local isShort = short(flock, flock.hens)
  return {
    level = isShort and 2 or 0,
    state = flock.hens == 0 and "none" or isShort and "short" or "ok",
    frac = flock.housing > 0 and clamp01(flock.hens / flock.housing) or 0,
  }
end

function status.eggs(world)
  return { level = 0, state = Animals.info(world).nest > 0 and "some" or "none" }
end

function status.goats(world)
  local herd = Animals.goatInfo(world)
  local isShort = short(herd, herd.goats)
  local level = isShort and 2 or Alerts.level(world, "animals")
  return {
    level = level,
    state = herd.goats == 0 and "none" or isShort and "short" or level >= 1 and "low" or "ok",
    frac = herd.housing > 0 and clamp01(herd.goats / herd.housing) or 0,
  }
end

function status.milk(world)
  return { level = 0, state = Animals.goatInfo(world).pail > 0 and "some" or "none" }
end

--- { level (0 fine, 1 amber, 2 red), state (the key the modal's words are filed under), frac (0..1 for
--- the bar, or nil for no bar), trend (-1, 0, 1, or nil for no arrow) } for a chip id.
function ChipStatus.of(world, id)
  return assert(status[id], "no status for chip " .. id)(world)
end

return ChipStatus
