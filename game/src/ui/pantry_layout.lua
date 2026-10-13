-- Pantry row geometry (pure, no love.*): row pitch and the button rectangles of one row (D93, #174).
-- Every row is at least a touch target tall (plus a gap), and its buttons never exceed the row, so
-- neighbouring rows' buttons cannot overlap however Buttons.add raises them to the touch target.
-- Buttons are placed from the right edge inward, each as wide as its touch target needs, so a larger
-- touch target pushes the row left instead of overlapping.

local M = {}

M.BASE_ROW = 26 -- virtual pixels; the row pitch when the touch target is small
M.ROW_GAP = 2 -- virtual pixels left between a row's buttons and the next row's
M.NOTE_H = 10 -- extra height under a perishable's row for its spoilage line
M.EDGE = 12 -- virtual pixels between the rightmost button and the panel edge
-- Text columns measured from the panel's right edge (the Keep and Spare numbers).
M.COL = { stand = 66, plus = 96, minus = 122, auto = 160, keep = 196, spare = 228 }
-- Natural button widths and the gap left of each (virtual pixels), right to left.
local ORDER = {
  { "stand", 54, 0 },
  { "plus", 24, 6 },
  { "minus", 24, 2 },
  { "auto", 34, 4 },
}

--- Pitch of a row without a note: at least the touch target plus a gap.
function M.rowHeight(minTouch)
  return math.max(M.BASE_ROW, minTouch + M.ROW_GAP)
end

--- Rectangles { name = {x,y,w,h} } of a row's buttons for a row starting at y. The Stand/Truck
--- slot is kept (empty) when `stand` is false so the other columns line up between rows.
function M.buttons(right, y, minTouch, stand)
  local h = math.max(M.BASE_ROW - 4, minTouch)
  local out, left = {}, right - M.EDGE
  for _, c in ipairs(ORDER) do
    local name, w, gap = c[1], math.max(c[2], minTouch), c[3]
    local x = left - gap - w
    if name ~= "stand" or stand then
      out[name] = { x = x, y = y + 1, w = w, h = h }
    end
    left = x
  end
  return out
end

return M
