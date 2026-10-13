-- Placement card geometry (D86, #206): the card must never cover the target footprint. Pure code.
local T = require("harness")
local PlaceCard = require("src.ui.place_card")

T.test("place card: a footprint above the card needs no move", function()
  local rect = { x = 100, y = 100, w = 32, h = 32 }
  T.falsy(PlaceCard.overlaps(rect, 500, 150, 10))
  T.eq(PlaceCard.panFor(rect, 500, 10, 50), 0)
end)

T.test("place card: a footprint under the card is panned up above it", function()
  local rect = { x = 100, y = 560, w = 32, h = 32 }
  T.truthy(PlaceCard.overlaps(rect, 500, 150, 10))
  local dy = PlaceCard.panFor(rect, 500, 10, 50)
  T.truthy(dy < 0)
  local moved = { x = rect.x, y = rect.y + dy, w = rect.w, h = rect.h }
  T.falsy(PlaceCard.overlaps(moved, 500, 150, 0), "clear of the card")
  T.truthy(moved.y >= 50 + 10, "and below the top bar")
end)

T.test("place card: a footprint that cannot fit above the card gives no pan", function()
  local rect = { x = 0, y = 100, w = 300, h = 400 }
  T.eq(PlaceCard.panFor(rect, 400, 10, 50), nil)
end)

T.test("place card: the top slot sits under the top bar, and bounds spans the tiles", function()
  T.eq(PlaceCard.topY(50, 10), 60)
  local b = PlaceCard.bounds({ { x = 1, y = 1 }, { x = 2, y = 1 } }, function(tx, ty)
    return tx * 16, ty * 16, 16, 16
  end)
  T.eq(b.x, 16)
  T.eq(b.w, 32)
  T.eq(b.h, 16)
  T.eq(PlaceCard.bounds({}, function() end), nil)
end)
