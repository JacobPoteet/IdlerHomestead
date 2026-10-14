-- Where the placement card may sit so it never covers the tile it describes (D86, #206). Pure geometry in
-- view pixels: rects are { x, y, w, h }; the card is a full-width band, so only vertical overlap matters.
-- The scene pans the camera by `panFor` when the footprint would sit under the card, and falls back to the
-- top slot (`topY`) when the camera cannot move far enough (map edge).

local PlaceCard = {}

--- Does a card at y with height h (plus `gap` all round) cover any of the rect?
function PlaceCard.overlaps(rect, y, h, gap)
  return rect.y < y + h + gap and rect.y + rect.h > y - gap
end

--- How far to move the content vertically (view pixels, negative = up) so the rect sits fully above a card
--- at cardY, or nil when it cannot fit between `topLimit` and the card.
function PlaceCard.panFor(rect, cardY, gap, topLimit)
  local dy = (cardY - gap) - (rect.y + rect.h)
  if dy >= 0 then
    return 0
  end
  if rect.y + dy < topLimit + gap then
    return nil
  end
  return dy
end

--- How far to move the content vertically so the rect sits inside the free band [topLimit + gap, bottomLimit - gap]
--- (view pixels; 0 when it already does, or when it is taller than the band). A target dragged behind the top
--- bar or the toolbar is pulled back into view (D120).
function PlaceCard.panIntoBand(rect, topLimit, bottomLimit, gap)
  local lo, hi = topLimit + gap, bottomLimit - gap
  if rect.h > hi - lo then
    return 0
  elseif rect.y < lo then
    return lo - rect.y
  elseif rect.y + rect.h > hi then
    return hi - (rect.y + rect.h)
  end
  return 0
end

--- The y of a card hung under the top bar instead: below topLimit with a gap.
function PlaceCard.topY(topLimit, gap)
  return topLimit + gap
end

--- The bounding rect in view pixels of tiles [{tx, ty}] given a function tileRect(tx, ty) -> x, y, w, h.
function PlaceCard.bounds(tiles, tileRect)
  local x1, y1, x2, y2
  for _, t in ipairs(tiles) do
    local x, y, w, h = tileRect(t.x, t.y)
    x1 = x1 and math.min(x1, x) or x
    y1 = y1 and math.min(y1, y) or y
    x2 = x2 and math.max(x2, x + w) or x + w
    y2 = y2 and math.max(y2, y + h) or y + h
  end
  if not x1 then
    return nil
  end
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

--- Smoothstep easing: 0 at t<=0, 1 at t>=1, flat at both ends and increasing between (D120).
function PlaceCard.ease(t)
  if t <= 0 then
    return 0
  elseif t >= 1 then
    return 1
  end
  return t * t * (3 - 2 * t)
end

--- A camera glide from (fromX, fromY) to (toX, toY) in world pixels, or nil when they are the same spot.
function PlaceCard.glide(fromX, fromY, toX, toY)
  if fromX == toX and fromY == toY then
    return nil
  end
  return { fromX = fromX, fromY = fromY, toX = toX, toY = toY, t = 0 }
end

--- Advance a glide by dt real seconds over `duration`; returns the camera position (x, y) and whether it
--- has arrived. A zero duration arrives at once.
function PlaceCard.glideStep(g, dt, duration)
  g.t = g.t + dt
  local k = duration > 0 and PlaceCard.ease(g.t / duration) or 1
  return g.fromX + (g.toX - g.fromX) * k, g.fromY + (g.toY - g.fromY) * k, k >= 1
end

--- Count down the re-fit timer after the player moved the map: it only runs while no pointer is held (so a
--- finger resting mid-drag is not fought). Returns the new timer (nil when idle) and whether the re-fit is due.
function PlaceCard.refitStep(timer, dt, held)
  if not timer then
    return nil, false
  end
  if held then
    return timer, false
  end
  timer = timer - dt
  if timer <= 0 then
    return nil, true
  end
  return timer, false
end

return PlaceCard
