-- The goal ladder (D163, #342, docs/PLAN_DEPTH.md §3): which goal presses on the player now, with the figures the HUD
-- line and the Progress panel show. Accessors only (no state): every figure comes from the system that owns it
-- (Readiness.tonight, Footing, Readiness.winter, Weather, Established), so the line cannot disagree with the Tonight
-- card, the chips or the winter readiness.
--
--   Tonight   from run start until Footing, and again while it is slipped, as long as a row of the dusk check is short.
--   Footing   (or regaining it) once nothing is short tonight: the checklist and the nights in a row.
--   Winter    once Footing is held: days to the freeze, the wood and food reserve target, the Great Winter's status.

local Calendar = require("src.sim.systems.calendar")
local Footing = require("src.sim.systems.footing")
local Ledger = require("src.sim.systems.ledger")
local Needs = require("src.sim.systems.needs")
local Readiness = require("src.sim.systems.readiness")
local Weather = require("src.sim.systems.weather")

local Goal = {}

-- Short names of the Tonight rows, for the line ("Tonight: wood, water").
local ROW_NAMES = { warmth = "wood", food = "food", water = "water" }

-- The Tonight rows that are short: { { id, name, level } } in card order.
local function gapRows(look)
  local rows = {}
  for _, id in ipairs({ "warmth", "food", "water" }) do
    local row = look[id]
    if row.level > 0 then
      rows[#rows + 1] = { id = id, name = ROW_NAMES[id], level = row.level }
    end
  end
  return rows
end

--- The Footing part: { held, slipped, checks, okCount, total, streak, streakNights, good, regainNights, gainedDay }.
local function footingPart(world)
  local st = Footing.status(world)
  local checks = Footing.checks(world)
  local ok = 0
  for _, c in ipairs(checks) do
    if c.ok then
      ok = ok + 1
    end
  end
  st.checks, st.okCount, st.total = checks, ok, #checks
  return st
end

--- The winter part: { frozen, daysAway (math.huge when no season freezes), never (no season ever freezes),
---   wood = { have, need } or nil, food = { have, need } or nil (only once the readiness is due, since the winter's
---   nights are only known then), verdict ("ready" | "fuel" | "food" | "both" | nil), covered, nights }.
local function winterPart(world)
  local frozen = Weather.isFrozen(world)
  local days = Weather.daysToFreeze(world)
  local out = { frozen = frozen, daysAway = days, never = not frozen and days == math.huge }
  local ready = Readiness.winter(world)
  if ready then
    if ready.fuel.woodNeed > 0 then
      out.wood = { have = ready.fuel.wood, need = ready.fuel.woodNeed }
    end
    out.food = { have = ready.food.days, need = ready.food.need }
    out.verdict, out.covered, out.nights = ready.verdict, ready.fuel.covered, ready.fuel.nights
  elseif not out.never then
    local perWood, ahead = Needs.warmthPerWood(world), Readiness.warmthAhead(world)
    if perWood > 0 and ahead > 0 then
      out.wood = { have = Ledger.get(world, Needs.fuelId(world)), need = math.ceil(ahead / perWood - 1e-9) }
    end
  end
  return out
end

--- The Great Winter part: { year (the winter's year), state ("ahead" | "now" | "survived"), yearsAway, slotEstablished }.
--- "survived" is this run's: the year counter is past the Great Winter's year, so its thaw has come (Established).
local function greatPart(world)
  local year = world.tuning.progress.greatWinterYear
  local now = Calendar.now(world)
  local state = "ahead"
  if now.year > year then
    state = "survived"
  elseif now.year == year and Weather.isFrozen(world) then
    state = "now"
  end
  return {
    year = year,
    state = state,
    yearsAway = math.max(0, year - now.year),
    slotEstablished = world.meta.established ~= nil,
  }
end

--- The goal now, from the dusk check's look (`look`, Readiness.tonight; read afresh when nil):
---   { kind = "tonight" | "footing" | "regain" | "winter",
---     level (0 fine, 1 amber, 2 red: the worst short row for "tonight", else 0),
---     gaps = { { id, name, level } } (the short Tonight rows),
---     slipped (Footing is held but slipped),
---     footing = footingPart, winter = winterPart, great = greatPart,
---     season = { year, season, day, daysPerSeason } }
function Goal.current(world, look)
  look = look or Readiness.tonight(world)
  local footing = footingPart(world)
  local gaps = gapRows(look)
  local kind, level = "winter", 0
  if Footing.tonightLeads(world) then
    if #gaps > 0 then
      kind = "tonight"
      for _, g in ipairs(gaps) do
        level = math.max(level, g.level)
      end
    else
      kind = footing.held and "regain" or "footing"
    end
  end
  local now = Calendar.now(world)
  return {
    kind = kind,
    level = level,
    gaps = gaps,
    slipped = footing.slipped,
    footing = footing,
    winter = winterPart(world),
    great = greatPart(world),
    season = {
      year = now.year,
      season = now.season,
      day = now.dayOfSeason,
      daysPerSeason = world.tuning.time.daysPerSeason,
    },
  }
end

--- The gates that open at Footing, for the Progress panel: { open (Footing is held), items = { { id, name } } }.
--- Every catalog definition carrying the content flag `requiresFooting` (the gate framework, D164, #343), then the
--- surfaces named in tuning.progress.surfaces: things Footing opens that are gated in code, not by a content flag (the
--- contracts board, D197). A later Footing-gated thing either flags its content or adds its name to that list.
function Goal.gates(world)
  local items = {}
  for _, def in ipairs(world.registry:all("catalog")) do
    if Footing.gated(def) then
      items[#items + 1] = { id = def.id, name = def.name }
    end
  end
  for i, name in ipairs(world.tuning.progress.surfaces) do
    items[#items + 1] = { id = "surface" .. i, name = name }
  end
  return { open = Footing.held(world), items = items }
end

return Goal
