-- UI scale maths (pure, GDD §10 / D96). The window is divided by a whole-number scale into virtual
-- pixels. "Auto" is the largest scale that still shows display.minVirtualWidth x minVirtualHeight; a
-- player can pick a smaller whole scale (more virtual space, smaller UI) but never a larger one, since
-- layouts are only built for views of at least that size. Whole scales keep text and the art grid crisp.

local M = {}

--- The Auto scale for a window of pixelW x pixelH (never below 1).
function M.auto(pixelW, pixelH, display)
  return math.max(1, math.floor(math.min(pixelW / display.minVirtualWidth, pixelH / display.minVirtualHeight)))
end

--- Fixed scales this window can show: 1 .. min(auto, uiScaleMax).
function M.steps(pixelW, pixelH, display, cfg)
  local top = math.min(M.auto(pixelW, pixelH, display), cfg.uiScaleMax)
  local out = {}
  for s = 1, top do
    out[#out + 1] = s
  end
  return out
end

--- The scale actually used for a stored setting ("auto" or a whole number) and whether it was clamped
--- down because the window is too small for it.
function M.effective(setting, pixelW, pixelH, display, cfg)
  local auto = M.auto(pixelW, pixelH, display)
  if setting == "auto" then
    return auto, false
  end
  local top = math.min(auto, cfg.uiScaleMax)
  local want = math.max(1, math.floor(tonumber(setting) or auto))
  if want > top then
    return top, true
  end
  return want, false
end

--- Screen pixels the smallest tappable element covers at `scale`.
function M.touchPixels(scale, minTouchTarget)
  return minTouchTarget * scale
end

return M
