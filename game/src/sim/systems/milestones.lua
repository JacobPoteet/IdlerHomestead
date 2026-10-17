-- Run milestones (D163, #342, #276, GDD §4.4, D117 item 4): the short per-run checklist behind the Progress panel.
-- Each one in data/content/milestones.lua is reached by a world event (with an optional match and count), like a
-- Field Journal note; the systems that emit those events never know this one exists. Run state, so a new run starts
-- with none ticked, and no reward.
--
-- State: world.state.milestones = { done = { [id] = { day, season, year } } (when it was reached),
--   counts = { [id] = n } (matching events so far, for count milestones) }.
-- Emits "milestone.reached" { id } when one ticks.

local Calendar = require("src.sim.systems.calendar")

local Milestones = {}

local function state(world)
  return world.state.milestones
end

-- Does the event satisfy the rule? A value may be an exact value, a list of values (any one), or { min, max }.
local function matches(rule, e)
  for field, want in pairs(rule or {}) do
    local value = e[field]
    if type(want) == "table" and (want.min ~= nil or want.max ~= nil) then
      if type(value) ~= "number" then
        return false
      end
      if (want.min and value < want.min) or (want.max and value > want.max) then
        return false
      end
    elseif type(want) == "table" then
      local found = false
      for _, option in ipairs(want) do
        if option == value then
          found = true
          break
        end
      end
      if not found then
        return false
      end
    elseif value ~= want then
      return false
    end
  end
  return true
end

local function reach(world, def)
  local st, now = state(world), Calendar.now(world)
  st.done[def.id] = { day = now.dayOfSeason, season = now.season, year = now.year }
  st.counts[def.id] = nil
  world.events:emit("milestone.reached", { id = def.id })
end

--- Has the run reached the milestone?
function Milestones.done(world, id)
  return state(world).done[id] ~= nil
end

--- The checklist in content order: { { id, name, hint, done (bool), day, season, year (when done), have, need
--- (matching events so far and wanted, for a count milestone; need is 1 otherwise) } }.
function Milestones.list(world)
  local st, out = state(world), {}
  for _, def in ipairs(world.registry:all("milestones")) do
    local when = st.done[def.id]
    out[#out + 1] = {
      id = def.id,
      name = def.name,
      hint = def.hint,
      done = when ~= nil,
      day = when and when.day,
      season = when and when.season,
      year = when and when.year,
      have = when and (def.count or 1) or st.counts[def.id] or 0,
      need = def.count or 1,
    }
  end
  return out
end

--- How many are reached, and how many there are: done, total.
function Milestones.tally(world)
  local done, total = 0, 0
  for _, m in ipairs(Milestones.list(world)) do
    total = total + 1
    if m.done then
      done = done + 1
    end
  end
  return done, total
end

function Milestones.init(world)
  local st = world.state.milestones or {}
  world.state.milestones = st
  st.done = st.done or {}
  st.counts = st.counts or {}
  local byEvent, order = {}, {}
  for _, def in ipairs(world.registry:all("milestones")) do
    if not byEvent[def.event] then
      byEvent[def.event] = {}
      order[#order + 1] = def.event
    end
    local list = byEvent[def.event]
    list[#list + 1] = def
  end
  for _, name in ipairs(order) do
    local defs = byEvent[name]
    world.events:on(name, function(e)
      local s = state(world)
      for _, def in ipairs(defs) do
        if not s.done[def.id] and matches(def.match, e or {}) then
          local count = (s.counts[def.id] or 0) + 1
          if count >= (def.count or 1) then
            reach(world, def)
          else
            s.counts[def.id] = count
          end
        end
      end
    end)
  end
end

return Milestones
