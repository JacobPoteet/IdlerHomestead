-- Settings screen geometry (pure, so tests can check every window size and UI scale; D96).

local M = {}

M.HEADER_H = 30 -- virtual pixels: the "Settings" title strip
M.FOOTER_H = 40 -- virtual pixels: the Done / Defaults buttons
M.PAD = 12 -- virtual pixels: inner padding of the panel
M.GAP = 4 -- virtual pixels between neighbouring buttons

--- Control height: a comfortable 26, never under the touch minimum.
function M.controlH(minTouch)
  return math.max(26, minTouch)
end

--- The panel and the pieces inside it for a view { w, h }.
--- cfg = tuning.settings; returns { box, list = {x,y,w,h}, done = {x,y,w,h}, defaults = {x,y,w,h} }.
function M.panel(view, cfg, minTouch)
  local m = cfg.panelMargin
  local w = math.min(cfg.panelWidth, view.w - 2 * m)
  local h = view.h - 2 * m
  local box = { x = (view.w - w) / 2, y = m, w = w, h = h }
  local bh = M.controlH(minTouch)
  local fy = box.y + box.h - M.FOOTER_H + (M.FOOTER_H - bh) / 2
  local half = (w - 2 * M.PAD - M.GAP) / 2
  return {
    box = box,
    list = { x = box.x, y = box.y + M.HEADER_H, w = box.w, h = box.h - M.HEADER_H - M.FOOTER_H },
    defaults = { x = box.x + M.PAD, y = fy, w = half, h = bh },
    done = { x = box.x + M.PAD + half + M.GAP, y = fy, w = half, h = bh },
  }
end

--- Lay `count` equal segments in rows inside [x, x + w], each at least minSeg wide. Returns the rects
--- (relative to y) and the total height used.
function M.segments(x, y, w, count, h, minSeg)
  local perRow = math.max(1, math.min(count, math.floor((w + M.GAP) / (minSeg + M.GAP))))
  local rows = math.ceil(count / perRow)
  local segW = (w - (perRow - 1) * M.GAP) / perRow
  local rects = {}
  for i = 0, count - 1 do
    local r, c = math.floor(i / perRow), i % perRow
    rects[#rects + 1] = { x = x + c * (segW + M.GAP), y = y + r * (h + M.GAP), w = segW, h = h }
  end
  return rects, rows * h + (rows - 1) * M.GAP
end

return M
