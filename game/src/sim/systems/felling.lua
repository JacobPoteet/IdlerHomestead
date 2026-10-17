-- Wood on demand (docs/PLAN_DEPTH.md F4 and C8, issue #362): in a season listed in tuning.wood.fellAllowance the
-- standing trees give only so much wood. Felled trees add the wood they gave to the season's tally; once the tally
-- reaches the allowance the Axe refuses trees (logs, brush and everything else still clear) until the season turns.
-- The check is made when a tree is started, so the last tree may take the tally past the allowance. Gathering
-- elsewhere (logs, brush, buying wood) is not touched, and the limit is not about what land is owned (Q12, D170).
--
-- State: world.state.felling = { key (year and season of the tally), wood (units felled that season) }.

local Calendar = require("src.sim.systems.calendar")

local Felling = {}

function Felling.init(world)
  world.state.felling = world.state.felling or { key = 0, wood = 0 }
end

local function seasonKey(now)
  return now.year * 100 + now.seasonIndex
end

--- Wood the trees give in `season`, or nil when the season has no limit.
function Felling.allowance(world, season)
  return rawget(world.tuning.wood.fellAllowance, season)
end

--- The limit on trees now or ahead: the current season's if it has one, else the next season that has one.
--- Returns nil when no season is limited, else
---   { season, allowance, now (true in that season), used, left (wood still to fell; the allowance when not yet),
---     daysAway (0 in it, else days until it starts) }
function Felling.outlook(world)
  local time = world.tuning.time
  local now = Calendar.now(world)
  local count = #time.seasons
  for step = 0, count - 1 do
    local idx = (now.seasonIndex - 1 + step) % count + 1
    local season = time.seasons[idx]
    local allowance = Felling.allowance(world, season)
    if allowance then
      local used = 0
      if step == 0 then
        local s = world.state.felling
        used = s.key == seasonKey(now) and s.wood or 0
      end
      return {
        season = season,
        allowance = allowance,
        now = step == 0,
        used = used,
        left = math.max(allowance - used, 0),
        daysAway = step == 0 and 0 or (step * time.daysPerSeason - now.dayOfSeason + 1),
      }
    end
  end
  return nil
end

--- Is felling refused for this object right now? True for a tree (an object of kind "tree") while the current season's
--- allowance is used up.
function Felling.limited(world, def)
  if def.kind ~= "tree" then
    return false
  end
  local out = Felling.outlook(world)
  return out ~= nil and out.now and out.left <= 0
end

--- A felled tree gave `wood` units: add them to the season's tally (only seasons with a limit keep one).
function Felling.record(world, def, wood)
  if def.kind ~= "tree" or wood <= 0 then
    return
  end
  local now = Calendar.now(world)
  if Felling.allowance(world, now.season) == nil then
    return
  end
  local s = world.state.felling
  local key = seasonKey(now)
  if s.key ~= key then
    s.key, s.wood = key, 0
  end
  s.wood = s.wood + wood
end

return Felling
