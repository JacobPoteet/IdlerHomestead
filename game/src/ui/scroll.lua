-- Pixel scrolling for a vertical list inside a panel (D70, #170): the maths only, so panels share one
-- behaviour and tests can check it without a window. A panel keeps an `offset` (pixels scrolled down,
-- 0 at the top), feeds drags and wheel notches through Scroll.byDrag / Scroll.byWheel, and draws the thumb.
--
-- Drag follows the finger (dragging up shows later rows) and the wheel follows the usual direction
-- (wheel down shows later rows). `zoom` actions carry steps > 0 for wheel up.

local Scroll = {}

--- The most the list can scroll: content that does not fit, else 0.
function Scroll.max(contentH, viewH)
  return math.max(0, contentH - viewH)
end

--- Keep an offset inside the list.
function Scroll.clamp(offset, contentH, viewH)
  return math.max(0, math.min(offset, Scroll.max(contentH, viewH)))
end

--- New offset after a drag of `dy` virtual pixels (down is positive).
function Scroll.byDrag(offset, dy, contentH, viewH)
  return Scroll.clamp(offset - dy, contentH, viewH)
end

--- New offset after `steps` wheel notches (positive = wheel up = towards the top), `step` pixels each.
function Scroll.byWheel(offset, steps, step, contentH, viewH)
  return Scroll.clamp(offset - steps * step, contentH, viewH)
end

--- Does the list overflow its view?
function Scroll.overflows(contentH, viewH)
  return contentH > viewH
end

--- Pixels of content hidden above and below the view: above, below.
function Scroll.hidden(offset, contentH, viewH)
  local above = math.max(0, offset)
  local below = math.max(0, contentH - viewH - offset)
  return above, below
end

--- The thumb inside a track of `trackH` pixels: its offset from the track top and its height, or nil
--- when nothing overflows. The thumb is at least `minH` tall.
function Scroll.thumb(offset, contentH, viewH, trackH, minH)
  if not Scroll.overflows(contentH, viewH) then
    return nil
  end
  local h = math.min(trackH, math.max(minH or 0, trackH * viewH / contentH))
  local range = Scroll.max(contentH, viewH)
  local at = range > 0 and (offset / range) * (trackH - h) or 0
  return at, h
end

return Scroll
