-- The ranked notice queue (PLAN_DEPTH principle 8, D168, D172). Pure: no drawing, no sim writes.
--
-- Cards that arrive on their own (the Tonight card, an event card, later contract and levy notices) share the free band
-- of the screen, so they never stack: at most one is up, the rest wait. The order lives in one place, tuning.ui.notices.rank.
-- Of the notices waiting the first in rank is up, except that a card already up keeps its place until it is answered or
-- put away (a card never opens over another, and never pushes another out). Cards the player opens (a status card, the
-- Progress panel, a book) are not notices: they cover the world and every notice waits behind them.

local Notices = {}

--- Which notice is up. `rank` is the list of notice ids in order; `waiting` maps an id to true when it has something to show;
--- `current` is the id up now (or nil). Returns an id, or nil when nothing waits.
function Notices.pick(rank, waiting, current)
  if current and waiting[current] then
    return current
  end
  for _, id in ipairs(rank) do
    if waiting[id] then
      return id
    end
  end
  return nil
end

return Notices
