-- Where everything on the Wardrobe sits (docs/PLAN_WARDROBE_MENU.md §2): pure rectangles in UI pixels for a view,
-- no love.graphics. Wide views (desktop, a phone on its side) put the figure and the meters in a left column and
-- the garments in a right one; narrow views (a phone upright) stack them: the figure with its meters beside it,
-- then the garments, then the action bar at the bottom in thumb reach. Knobs: tuning.ui.wardrobe and the book
-- tuning for the paper and its tab strip.

local Character = require("src.render.character")

local WardrobeLayout = {}

local floor, max, min = math.floor, math.max, math.min

-- Rows of art in the figure's inset: the figure down to its boots' last row, then the ground.
local function artRows(cfg)
  return Character.H - 2 + cfg.groundRows
end

--- The largest whole scale the figure may be drawn at inside an inset `availW` x `availH`, between the
--- tuned minimum and the wide or the stacked maximum.
function WardrobeLayout.previewScale(cfg, availW, availH, stacked)
  local top = stacked and cfg.previewMaxScaleTall or cfg.previewMaxScale
  local fit =
    min(floor((availW - 2 * cfg.previewPad) / Character.W), floor((availH - 2 * cfg.previewPad) / artRows(cfg)))
  return max(cfg.previewMinScale, min(top, fit))
end

--- How many tiles fit side by side in a grid `gridW` wide (at least one).
function WardrobeLayout.columns(cfg, gridW)
  return max(1, floor((gridW + cfg.tileGap) / (cfg.tileW + cfg.tileGap)))
end

--- The tiles' rectangles in a grid window `grid` ({x, y, w, h}), in content space: x is on screen, y counts from
--- the window's top (add the list's origin). The tiles keep `focusGap` clear all round so a focus ring is never
--- clipped. Returns the list, the content height and the column count.
function WardrobeLayout.tiles(cfg, grid, count)
  local inner = grid.w - 2 * cfg.focusGap
  local columns = WardrobeLayout.columns(cfg, inner)
  local list = {}
  for n = 0, count - 1 do
    list[n + 1] = {
      x = grid.x + cfg.focusGap + (n % columns) * (cfg.tileW + cfg.tileGap),
      y = cfg.focusGap + floor(n / columns) * (cfg.tileH + cfg.tileGap),
      w = cfg.tileW,
      h = cfg.tileH,
    }
  end
  local rows = math.ceil(count / columns)
  local contentH = rows > 0 and (rows * (cfg.tileH + cfg.tileGap) - cfg.tileGap + 2 * cfg.focusGap) or 0
  return list, contentH, columns
end

-- The two meters in a column starting at (x, y), `w` wide. Wide views put label, bar and number on one row;
-- stacked views put the label over the bar and its number.
local function meters(cfg, x, y, w, stacked)
  local out = {}
  local rowH = stacked and cfg.meterStackRowH or cfg.meterRowH
  for n, key in ipairs({ "work", "heat" }) do
    local top = y + (n - 1) * (rowH + cfg.meterRowGap)
    local m = { x = x, y = top, w = w, h = rowH }
    if stacked then
      local barRow = top + cfg.lineH + 1
      m.label = { x = x, y = top, w = w, h = cfg.lineH }
      m.bar = { x = x, y = barRow + floor((cfg.lineH - cfg.meterH) / 2), w = cfg.meterW, h = cfg.meterH }
      m.num = { x = x + cfg.meterW + cfg.meterGap, y = barRow, w = cfg.meterNumW, h = cfg.lineH }
    else
      m.label = { x = x, y = top, w = cfg.meterLabelW, h = rowH }
      m.bar = {
        x = x + cfg.meterLabelW + cfg.meterGap,
        y = top + floor((rowH - cfg.meterH) / 2),
        w = cfg.meterW,
        h = cfg.meterH,
      }
      m.num = { x = m.bar.x + cfg.meterW + cfg.meterGap, y = top, w = cfg.meterNumW, h = rowH }
    end
    out[key] = m
  end
  return out, 2 * rowH + cfg.meterRowGap
end

-- The preset chips (Warm, Cold, Auto) in a row at (x, y), and the row's height.
local function presetRow(cfg, x, y, minTouch)
  local h = max(cfg.presetH, minTouch)
  local chips = {}
  for n = 1, 3 do
    chips[n] = { x = x + (n - 1) * (cfg.presetW + cfg.blockGap), y = y, w = max(cfg.presetW, minTouch), h = h }
  end
  return chips, h
end

--- Every rectangle of the screen for `view` ({ w, h }): { paper, strip, body, wide, title, state, preview, figure,
--- ground, meters = { work, heat }, presets, chips, heading, grid, detail, tag, reset, wear, save, columns }.
--- `cfg` is tuning.ui.wardrobe, `bookCfg` tuning.ui.book (the paper and its tab strip are the Ledger's),
--- `tileCount` the garments in the slot shown. `opts`: { maxTiles = the garments of the longest slot (wide views keep
--- the detail line right under the room that many need), presets = bool (reserve the preset chips under the
--- meters), save = bool (reserve a Save button beside Reset) }. Tile rectangles come from WardrobeLayout.tiles
--- once the scene has fitted its scroll window to `grid`.
function WardrobeLayout.rects(cfg, bookCfg, view, minTouch, tileCount, opts)
  opts = opts or {}
  local w = min(cfg.width, view.w - 2 * bookCfg.margin)
  local h = view.h - 2 * bookCfg.margin
  local paper = { x = floor((view.w - w) / 2), y = floor((view.h - h) / 2), w = w, h = h }
  local tabH = max(bookCfg.tabHeight, minTouch)
  local strip = { x = paper.x, y = paper.y, w = paper.w, h = tabH }
  local top = paper.y + tabH + bookCfg.bodyGap
  local pad = cfg.pad
  local body = { x = paper.x + pad, y = top + pad, w = paper.w - 2 * pad, h = paper.y + paper.h - top - 2 * pad }
  local wide = view.w >= cfg.wideMin
  local L = { paper = paper, strip = strip, body = body, wide = wide }
  local actionH = max(cfg.actionH, minTouch)
  local gap, line = cfg.blockGap, cfg.lineH

  local lower -- the column holding the garments: { x, y, w, h }
  if wide then
    local left = { x = body.x, y = body.y, w = cfg.leftW, h = body.h }
    lower = { x = left.x + left.w + cfg.colGap, y = body.y, w = body.w - cfg.leftW - cfg.colGap, h = body.h }
    L.title = { x = left.x, y = left.y, w = left.w, h = line }
    L.state = { x = left.x, y = L.title.y + line + 2, w = left.w, h = line }
    local y = L.state.y + line + cfg.stackGap
    local _, metersH = meters(cfg, left.x, 0, left.w, false)
    local presetsH = opts.presets and (max(cfg.presetH, minTouch) + gap) or 0
    local availH = left.y + left.h - y - metersH - cfg.stackGap - presetsH
    local scale = WardrobeLayout.previewScale(cfg, left.w, availH, false)
    L.preview = { x = left.x, y = y, w = left.w, h = 2 * cfg.previewPad + artRows(cfg) * scale, scale = scale }
    local my = L.preview.y + L.preview.h + cfg.stackGap
    L.meters = meters(cfg, left.x, my, left.w, false)
    local py = my + metersH + gap
    if opts.presets then
      L.chips = presetRow(cfg, left.x, py, minTouch)
      L.presets = { x = left.x, y = py, w = left.w, h = L.chips[1].h }
    else
      L.presets = { x = left.x, y = py, w = left.w, h = 0 }
      L.chips = {}
    end
  else
    L.title = { x = body.x, y = body.y, w = body.w, h = line }
    local y = L.title.y + line + gap
    local availW = body.w - cfg.stackSideMin - cfg.stackGap
    local availH = floor(body.h * cfg.stackPreviewShare)
    local scale = WardrobeLayout.previewScale(cfg, availW, availH, true)
    local boxW = 2 * cfg.previewPad + Character.W * scale
    L.preview = { x = body.x, y = y, w = boxW, h = 2 * cfg.previewPad + artRows(cfg) * scale, scale = scale }
    local side = { x = body.x + boxW + cfg.stackGap, y = y, w = body.x + body.w - (body.x + boxW + cfg.stackGap) }
    L.state = { x = side.x, y = side.y, w = side.w, h = line }
    local my = L.state.y + line + cfg.stackGap
    local _, metersH = meters(cfg, side.x, 0, side.w, true)
    L.meters = meters(cfg, side.x, my, side.w, true)
    local py = my + metersH + cfg.stackGap
    if opts.presets then
      L.chips = presetRow(cfg, side.x, py, minTouch)
      L.presets = { x = side.x, y = py, w = side.w, h = L.chips[1].h }
    else
      L.presets = { x = side.x, y = py, w = side.w, h = 0 }
      L.chips = {}
    end
    local bottom = max(L.preview.y + L.preview.h, L.presets.y + L.presets.h)
    lower = { x = body.x, y = bottom + cfg.stackGap, w = body.w, h = body.y + body.h - bottom - cfg.stackGap }
  end
  L.figure = {
    x = L.preview.x + floor((L.preview.w - Character.W * L.preview.scale) / 2),
    y = L.preview.y + cfg.previewPad,
    scale = L.preview.scale,
  }
  local scale = L.preview.scale
  local groundW = floor((L.preview.w - 2 * cfg.previewPad) / scale) * scale -- whole art pixels, centred
  L.ground = {
    x = L.preview.x + floor((L.preview.w - groundW) / 2),
    y = L.figure.y + (Character.H - 2) * scale,
    w = groundW,
    h = cfg.groundRows * scale,
  }

  -- The lower block: heading, grid, detail, then the action row (and the tag, which is beside it when wide).
  local actionsY = lower.y + lower.h - actionH
  L.heading = { x = lower.x, y = lower.y, w = lower.w, h = cfg.headingH }
  if wide then
    local wear = { x = 0, y = actionsY, w = max(cfg.wearW, minTouch), h = actionH }
    wear.x = lower.x + lower.w - wear.w
    local reset = { x = 0, y = actionsY, w = max(cfg.resetW, minTouch), h = actionH }
    reset.x = wear.x - gap - reset.w
    local leftmost = reset.x
    if opts.save then
      L.save = { x = 0, y = actionsY, w = max(cfg.saveW, minTouch), h = actionH }
      L.save.x = reset.x - gap - L.save.w
      leftmost = L.save.x
    end
    L.wear, L.reset = wear, reset
    L.tag = { x = lower.x, y = actionsY + floor((actionH - cfg.tagH) / 2), w = leftmost - gap - lower.x, h = cfg.tagH }
    L.detail = { x = lower.x, y = actionsY - gap - cfg.detailH, w = lower.w, h = cfg.detailH }
  else
    local third = floor((lower.w - gap) / 4)
    local resetW = max(third, minTouch)
    local saveW = opts.save and (resetW + gap) or 0
    local wearW = lower.w - resetW - gap - saveW
    L.reset = { x = lower.x, y = actionsY, w = resetW, h = actionH }
    if opts.save then
      L.save = { x = lower.x + resetW + gap, y = actionsY, w = resetW, h = actionH }
    end
    L.wear = { x = lower.x + lower.w - wearW, y = actionsY, w = wearW, h = actionH }
    L.tag = { x = lower.x, y = actionsY - gap - cfg.tagH, w = lower.w, h = cfg.tagH }
    L.detail = { x = lower.x, y = L.tag.y - gap - cfg.detailH, w = lower.w, h = cfg.detailH }
  end
  local gridY = L.heading.y + L.heading.h
  L.columns = WardrobeLayout.columns(cfg, lower.w - 2 * cfg.focusGap)
  if wide and opts.maxTiles then
    -- The detail line sits right under the room the longest slot needs, not at the bottom of a mostly empty column.
    local _, reservedH = WardrobeLayout.tiles(cfg, { x = lower.x, w = lower.w }, opts.maxTiles)
    L.detail.y = min(L.detail.y, gridY + reservedH + cfg.stackGap)
  end
  L.grid = { x = lower.x, y = gridY, w = lower.w, h = max(0, L.detail.y - gap - gridY) }
  L.tileCount = tileCount
  return L
end

return WardrobeLayout
