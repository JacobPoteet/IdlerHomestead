-- The Tonight card's state and place (GDD §4.2, D161, #340, docs/PLAN_DEPTH.md §3.1). Pure (no drawing, no sim
-- writes), so the open, dismiss and re-open rules and the geometry are tested headless.
--
-- The card opens by itself once each day when the evening is due (Readiness.tonightDue) and tonight leads; the
-- player can close it (it then stays closed that day) and bring it back from the Tonight stamp or the T key at
-- any hour. A card that opened by itself puts itself away at bedtime; one the player opened stays until closed.
-- It never blocks input: it is a panel in the free band beside or above the world, and only a tap on the card
-- itself is the card's.

local Tonight = {}
Tonight.__index = Tonight

function Tonight.new()
  return setmetatable({ open = false, manual = false, autoDay = nil }, Tonight)
end

--- Call every frame with whether the evening is due, whether tonight leads, the calendar day and whether the
--- homesteader is asleep. Opens the card on the first due frame of a day, puts an automatic one away when the
--- evening ends.
function Tonight:sync(due, leads, day, asleep)
  if due and leads and self.autoDay ~= day and not asleep then
    self.autoDay = day
    if not self.open then
      self.open, self.manual = true, false
    end
  elseif self.open and not self.manual and (not due or not leads or asleep) then
    self.open = false
  end
end

--- The player closed the card. In the evening (`due`) it stays closed for the rest of the day; a card closed
--- earlier comes up by itself at dusk as usual.
function Tonight:dismiss(day, due)
  self.open, self.manual = false, false
  if due then
    self.autoDay = day
  end
end

--- The stamp or the T key: open when closed (and to stay open), close when open. Returns true when it is now open.
function Tonight:toggle(day, due)
  if self.open then
    self:dismiss(day, due)
    return false
  end
  self.open, self.manual = true, true
  return true
end

--- Should the Tonight stamp show (the card is closed and there is something to look at)?
function Tonight:stampDue(due, leads, gaps)
  return not self.open and leads and (due or gaps > 0)
end

--- Where the card goes and how tall its body may be. `view` = { w, h }, `bounds` = { top, bottom } (the free band
--- between the HUD's plates), `contentH` the height its rows want (without the strip), `cfg` = tuning.ui.tonight.
--- Returns { rect = { x, y, w, h }, layout = "side" | "sheet", strip }. A wide view gets a card at the right edge
--- under the top plates; a tall view a sheet over the bottom plates.
function Tonight.place(cfg, view, bounds, contentH, touch)
  local margin = cfg.margin
  local strip = math.max(cfg.stripH, touch)
  local top, bottom = bounds.top + margin, bounds.bottom - margin
  local avail = bottom - top
  local want = strip + cfg.pad + contentH + cfg.pad
  local layout, x, y, w, h
  if view.w > view.h then
    layout = "side"
    w = math.min(cfg.sideWidth, view.w - 2 * margin)
    x = view.w - margin - w
    h = math.min(want, avail)
    y = top
  else
    layout = "sheet"
    w = math.min(view.w - 2 * margin, cfg.sheetMaxWidth)
    x = math.floor((view.w - w) / 2)
    h = math.min(want, math.floor(avail * cfg.sheetShare))
    y = bottom - h
  end
  return { rect = { x = x, y = y, w = w, h = h }, layout = layout, strip = strip }
end

return Tonight
