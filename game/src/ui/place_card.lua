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

return PlaceCard
