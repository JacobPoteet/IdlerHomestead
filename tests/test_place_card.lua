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

T.test("place card: the glide eases monotonically from start to end in the set time (D120)", function()
  T.eq(PlaceCard.ease(0), 0)
  T.eq(PlaceCard.ease(1), 1)
  T.eq(PlaceCard.ease(2), 1)
  local last = 0
  for i = 1, 10 do
    local e = PlaceCard.ease(i / 10)
    T.truthy(e >= last, "monotonic")
    last = e
  end
  T.eq(PlaceCard.glide(5, 5, 5, 5), nil)
  local g = PlaceCard.glide(100, 100, 100, 200)
  local x, y, done = PlaceCard.glideStep(g, 0.1, 0.4)
  T.eq(x, 100)
  T.truthy(y > 100 and y < 150 and not done, "mid glide is between the ends, slower than linear at the start")
  x, y, done = PlaceCard.glideStep(g, 0.5, 0.4)
  T.eq(y, 200)
  T.truthy(done)
  local z = PlaceCard.glide(0, 0, 10, 0)
  local _, _, instant = PlaceCard.glideStep(z, 0, 0)
  T.truthy(instant, "a zero duration arrives at once")
end)

T.test("place card: a held pointer pauses the re-fit and letting go starts the count (D120)", function()
  T.eq(PlaceCard.refitStep(nil, 1, false), nil)
  local timer, due = PlaceCard.refitStep(0.6, 1, true)
  T.eq(timer, 0.6)
  T.falsy(due)
  timer, due = PlaceCard.refitStep(0.6, 0.4, false)
  T.truthy(timer > 0 and not due)
  timer, due = PlaceCard.refitStep(timer, 0.4, false)
  T.eq(timer, nil)
  T.truthy(due)
end)

T.test("place card: a target behind the toolbar or top bar is pulled back into the free band (D120)", function()
  T.eq(PlaceCard.panIntoBand({ x = 0, y = 100, w = 16, h = 16 }, 50, 300, 10), 0)
  T.eq(PlaceCard.panIntoBand({ x = 0, y = 290, w = 16, h = 16 }, 50, 300, 10), -16)
  T.eq(PlaceCard.panIntoBand({ x = 0, y = 40, w = 16, h = 16 }, 50, 300, 10), 20)
  T.eq(PlaceCard.panIntoBand({ x = 0, y = 0, w = 16, h = 400 }, 50, 300, 10), 0)
end)
