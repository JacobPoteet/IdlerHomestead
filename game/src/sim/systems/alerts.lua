-- Survival warnings (D70, #157): food days, nights of fuel and condition against the thresholds in
-- tuning.alerts. The HUD colours its chips from Alerts.level (always live); this system also notices
-- the moment a level gets worse and says so once, as an "alert.raised" event the scene turns into a toast.
--
-- A level is 0 (fine), 1 (amber) or 2 (red). A worse level raises the alert at most once per
-- calendar day per kind and level, so a stock hovering around a threshold cannot nag; the level is
-- remembered, so recovering re-arms it for the next time. A world with no saved state (a new run, or
-- a save from before D70) starts from the levels it has now and raises nothing at load.
--
-- State: world.state.alerts = { level = { [kind] = 0..2 }, shown = { ["kind:level"] = day },
--                               next = game seconds until the next look,
--                               dawn = { last, prior = condition at the last two dawns, day = day of the last } }
-- Condition also counts as amber while it is tuning.alerts.conditionFallDrop below its level at the dawn
-- before the last midnight (D90, #176): a full heart losing 20 a night warns before it is low. It rides
-- the same level and once-per-day rule as every other alert, so it adds no toasts of its own.
-- "animals" (D71) is the days of hay or chicken feed the animals have left.
-- Emits "alert.raised" { kind = "food" | "fuel" | "condition" | "animals", level, value, noFire? }.

local Calendar = require("src.sim.systems.calendar")
local Animals = require("src.sim.systems.animals")
local Needs = require("src.sim.systems.needs")

local Alerts = {}

Alerts.KINDS = { "food", "fuel", "condition", "animals" }

--- The value a kind is judged on: days of food, nights of fuel, or condition.
function Alerts.value(world, kind)
  if kind == "food" then
    return Needs.foodDays(world)
  elseif kind == "fuel" then
    return Needs.fuelNights(world)
  elseif kind == "animals" then
    return Animals.feedDaysLeft(world) -- D71: math.huge when no animals are kept
  end
  return Needs.condition(world)
end

local function state(world)
  return world.state.alerts
end

--- How far condition has fallen over the last night (D90, #176): the reference is the condition at the
--- dawn before the last midnight (the night's loss lands at midnight), so from midnight until the next
--- dawn that is the last dawn, and after it the dawn before. 0 when it has not fallen or nothing is
--- remembered yet.
function Alerts.conditionDrop(world)
  local dawn = state(world) and state(world).dawn
  if not dawn then
    return 0
  end
  local sunrise = Calendar.daylight(world)
  local reference = Calendar.now(world).hour < sunrise and dawn.last or dawn.prior
  return math.max(0, reference - Needs.condition(world))
end

--- 0 (fine), 1 (amber) or 2 (red) for "food", "fuel" or "condition", and the value it was judged on.
--- Condition is at least amber while it is `conditionFallDrop` or more below its level a night ago.
function Alerts.level(world, kind)
  local cfg = world.tuning.alerts
  local value = Alerts.value(world, kind)
  local amber, red
  if kind == "food" then
    amber, red = cfg.foodAmberDays, cfg.foodRedDays
  elseif kind == "fuel" then
    amber, red = cfg.fuelAmberNights, cfg.fuelRedNights
  elseif kind == "animals" then
    amber, red = cfg.animalsAmberDays, cfg.animalsRedDays
  else
    amber, red = cfg.conditionAmber, cfg.conditionRed
  end
  if value < red then
    return 2, value
  elseif value < amber then
    return 1, value
  end
  if kind == "condition" and Alerts.conditionDrop(world) >= cfg.conditionFallDrop then
    return 1, value
  end
  return 0, value
end

--- Remember the condition at each dawn (the first look after sunrise on a new day).
local function noteDawn(world, st, now, first)
  local sunrise = Calendar.daylight(world)
  local condition = Needs.condition(world)
  if first then
    st.dawn = { last = condition, prior = condition, day = now.hour >= sunrise and now.day or now.day - 1 }
  elseif now.hour >= sunrise and st.dawn.day ~= now.day then
    st.dawn = { last = condition, prior = st.dawn.last, day = now.day }
  end
end

local function look(world, quiet)
  local st = state(world)
  local now = Calendar.now(world)
  local day = now.day
  noteDawn(world, st, now, st.dawn == nil)
  for _, kind in ipairs(Alerts.KINDS) do
    local level, value = Alerts.level(world, kind)
    local before = st.level[kind] or 0
    if level > before and not quiet then
      local key = kind .. ":" .. level
      if st.shown[key] ~= day then
        st.shown[key] = day
        world.events:emit("alert.raised", {
          kind = kind,
          level = level,
          value = value,
          noFire = kind == "fuel" and Needs.heatEfficiency(world) == 0 or nil,
        })
      end
    end
    st.level[kind] = level
  end
end

function Alerts.init(world)
  local st = world.state.alerts or {}
  st.level, st.shown, st.next = st.level or {}, st.shown or {}, st.next or 0
  world.state.alerts = st
  look(world, true) -- start from where things stand: no toast for a state the player did not just reach
end

function Alerts.tick(world, dt)
  local st = state(world)
  st.next = st.next - dt
  if st.next <= 0 then
    st.next = world.tuning.alerts.checkInterval
    look(world, false)
  end
end

return Alerts
