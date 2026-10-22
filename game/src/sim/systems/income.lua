-- Sales income per game year (GDD D117, #275): the late-game number to beat. Money earned from sales
-- counts (the truck trip, the roadside stand and the contracts board, D197); spending, refunds, starting money and anything else
-- that moves the money chip do not. It listens to the sale events, so the markets never know it exists.
--
-- State: world.state.income = { year = game year `current` belongs to, current = sales income so far
--   in that year, best = the most any single year of this run has earned, bestYear = which year, total =
--   sales income of the whole run }.
-- A year that is still running counts toward `best` as it fills, so the number only ever rises.

local Calendar = require("src.sim.systems.calendar")

local Income = {}

local function state(world)
  return world.state.income
end

local function add(world, amount)
  local st = state(world)
  if not amount or amount <= 0 then
    return
  end
  local year = Calendar.now(world).year
  if st.year ~= year then
    st.year, st.current = year, 0
  end
  st.current = st.current + amount
  st.total = st.total + amount
  if st.current > st.best then
    st.best, st.bestYear = st.current, year
  end
end

function Income.init(world)
  world.state.income = world.state.income or { year = 1, current = 0, best = 0, bestYear = 0, total = 0 }
  world.events:on("market.sold", function(e)
    add(world, e.earnings)
  end)
  world.events:on("stand.sold", function(e)
    add(world, e.earned)
  end)
  world.events:on("contract.done", function(e)
    add(world, e.reward)
  end)
end

--- Sales income of the game year now running.
function Income.thisYear(world)
  local st = state(world)
  return st.year == Calendar.now(world).year and st.current or 0
end

--- The best single year of this run so far: income, and the year it happened in (0 when nothing sold).
function Income.best(world)
  local st = state(world)
  return st.best, st.bestYear
end

--- Sales income of the whole run.
function Income.total(world)
  return state(world).total
end

return Income
