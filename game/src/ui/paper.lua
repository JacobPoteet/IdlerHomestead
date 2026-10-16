-- Paper (GDD §9.4, D142, D143): the surface of the Notebook and the Ledger. A plate lit like the world
-- (src/ui/plate.lua) in a paper colour, with a fibre of light and dark flecks on the UI pixel grid over it.
-- The flecks are made once per page size and kept as an image, so a frame costs one draw. Presentation only.
-- Knobs: tuning.ui.book.

local Icons = require("src.ui.icons")
local Plate = require("src.ui.plate")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Paper = {}

local cache = {} -- "w x h" -> { image }; a handful of sizes at most (the window and the two books)
local cacheCount = 0
local CACHE_MAX = 6

-- A repeatable 0..1 value for a cell and a salt: the same paper every run, with no random state to carry.
local function noise(x, y, salt)
  local v = math.sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
  return v - math.floor(v)
end

--- The fibre for a w x h page as an image: a few short horizontal or vertical flecks, light and dark.
local function fibre(cfg, w, h)
  local data = love.image.newImageData(w, h)
  local len = cfg.fibreLength
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if noise(x, y, 1) < cfg.fibreDensity / len then
        local light = noise(x, y, 2) < 0.5
        local across = noise(x, y, 3) < 0.5
        local alpha = light and cfg.fibreLight or cfg.fibreDark
        local grey = light and 1 or 0
        for k = 0, len - 1 do
          local px, py = x + (across and k or 0), y + (across and 0 or k)
          if px < w and py < h then
            data:setPixel(px, py, grey, grey, grey, alpha)
          end
        end
      end
    end
  end
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  return image
end

local function fibreFor(cfg, w, h)
  local key = w .. "x" .. h
  local entry = cache[key]
  if not entry then
    if cacheCount >= CACHE_MAX then
      cache, cacheCount = {}, 0 -- a resize storm: start over rather than keep every size
    end
    entry = fibre(cfg, w, h)
    cache[key] = entry
    cacheCount = cacheCount + 1
  end
  return entry
end

local BAYER4 = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local pools = {} -- "w x h" -> image, the night light pool for a page that size
local poolCount = 0

--- The pool of lamp light round a w x h page as an image, one pixel per `cell` UI pixels: brightest at the page's
--- edge, thinning out to nothing `spread` UI pixels away, cut into `steps` levels with a 4x4 Bayer dither.
local function pool(cfg, w, h)
  local key = w .. "x" .. h
  local image = pools[key]
  if image then
    return image
  end
  if poolCount >= CACHE_MAX then
    pools, poolCount = {}, 0
  end
  local p = cfg.pool
  local cell, spread, steps = p.cell, p.spread, p.steps
  local gw, gh = math.ceil((w + 2 * spread) / cell), math.ceil((h + 2 * spread) / cell)
  local data = love.image.newImageData(gw, gh)
  local c = p.color
  for gy = 0, gh - 1 do
    for gx = 0, gw - 1 do
      local ux, uy = (gx + 0.5) * cell - spread, (gy + 0.5) * cell - spread
      local dx = math.max(-ux, ux - w, 0)
      local dy = math.max(-uy, uy - h, 0)
      local d = math.min(1, math.sqrt(dx * dx + dy * dy) / spread)
      local level = (1 - d) ^ 1.5
      local t = (BAYER4[gy % 4 + 1][gx % 4 + 1] + 0.5) / 16
      local q = math.floor(level * steps + t) / steps
      data:setPixel(gx, gy, c[1], c[2], c[3], math.min(1, q))
    end
  end
  image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  pools[key] = image
  poolCount = poolCount + 1
  return image
end

--- The lamp's pool of light on the page itself as an image: brightest high up in the middle, thinning to nothing
--- toward the corners, cut into `steps` levels with the same dither.
local function wash(cfg, w, h)
  local key = "lamp" .. w .. "x" .. h
  local image = pools[key]
  if image then
    return image
  end
  if poolCount >= CACHE_MAX then
    pools, poolCount = {}, 0
  end
  local p = cfg.pool
  local cell, steps = p.cell, p.steps
  local gw, gh = math.ceil(w / cell), math.ceil(h / cell)
  local data = love.image.newImageData(gw, gh)
  local c = p.color
  local cx, cy = w * 0.5, h * p.washHeight
  local reach = math.max(w * 0.5, h * 0.7) * p.washReach
  for gy = 0, gh - 1 do
    for gx = 0, gw - 1 do
      local dx, dy = ((gx + 0.5) * cell - cx) * 0.7, (gy + 0.5) * cell - cy
      local d = math.min(1, math.sqrt(dx * dx + dy * dy) / reach)
      local level = (1 - d) ^ 1.3
      local t = (BAYER4[gy % 4 + 1][gx % 4 + 1] + 0.5) / 16
      data:setPixel(gx, gy, c[1], c[2], c[3], math.min(1, math.floor(level * steps + t) / steps))
    end
  end
  image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  pools[key] = image
  poolCount = poolCount + 1
  return image
end

--- The lamp's light on the page at x, y, w, h, `strength` 0..1. Draw it over the paper, under the page's content.
function Paper.drawLamp(cfg, x, y, w, h, strength)
  if strength <= 0 then
    return
  end
  local p = cfg.pool
  love.graphics.setColor(1, 1, 1, p.washAlpha * strength)
  love.graphics.draw(
    wash(cfg, math.floor(w), math.floor(h)),
    math.floor(x + 0.5),
    math.floor(y + 0.5),
    0,
    p.cell,
    p.cell
  )
end

--- A warm pool of lamp light behind the page at x, y, w, h (UI pixels), `strength` 0..1 (0 = none, nothing is
--- drawn). Draw it before the page; the page covers its heart and the glow shows round the edges.
function Paper.drawPool(cfg, x, y, w, h, strength)
  if strength <= 0 then
    return
  end
  w, h = math.floor(w), math.floor(h)
  local p = cfg.pool
  love.graphics.setColor(1, 1, 1, p.alpha * strength)
  love.graphics.draw(pool(cfg, w, h), math.floor(x + 0.5) - p.spread, math.floor(y + 0.5) - p.spread, 0, p.cell, p.cell)
end

--- Draw a page of paper at x, y, w, h (UI pixels, current transform). `cfg` is tuning.ui.book.
--- opts: { base = colour (default cfg.paper), fibre = false for no flecks, ink = outline colour, lit = 0..1 }.
function Paper.draw(cfg, x, y, w, h, opts)
  opts = opts or {}
  local base = opts.base or cfg.paper
  Plate.draw(x, y, w, h, {
    base = base,
    kind = "panel",
    see = 0,
    alpha = 1,
    ink = opts.ink,
    lit = opts.lit,
    weather = false,
  })
  if opts.fibre ~= false then
    local image = fibreFor(cfg, math.floor(w), math.floor(h))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, math.floor(x + 0.5), math.floor(y + 0.5))
  end
end

--- Stamp an icon in one ink with the printing slightly out of register: a dark second pass one pixel off,
--- then the ink on top. `ink` is { r, g, b }; (x, y) is the icon's top-left corner.
function Paper.stamp(cfg, icon, x, y, ink, alpha)
  local shade = cfg.stampShade
  love.graphics.setColor(shade[1], shade[2], shade[3], (shade[4] or 1) * (alpha or 1))
  Icons.drawTinted(icon, x + cfg.stampShift, y + cfg.stampShift)
  love.graphics.setColor(ink[1], ink[2], ink[3], alpha or 1)
  Icons.drawTinted(icon, x, y)
end

--- A tab of a paper book's strip: paper like the page when it is the open one, a darker slip when not; its ink
--- stamp, and the label when there is room (or for the open tab). `b` is the tab's button ({ x, y, w, h, label,
--- icon, selected, enabled, showLabel }), `pressed` whether it is being pressed. `cfg` is tuning.ui.book.
function Paper.drawTab(cfg, b, pressed)
  local colors = theme.colors
  local open = b.selected
  Plate.draw(b.x, b.y, b.w, b.h, {
    base = open and cfg.paper or cfg.tabIdle,
    kind = "button",
    see = 0,
    alpha = 1,
    ink = open and colors.accent or nil,
    lit = (pressed and 0) or (open and 0.3) or nil,
    weather = false,
  })
  local alpha = b.enabled and 1 or 0.4
  local ink = open and cfg.stampInk or cfg.stampIdle
  local iconW = cfg.iconSize
  local tw, th = Text.measure(b.label, "body")
  local total = iconW + (b.showLabel and (cfg.iconGap + tw) or 0)
  local ix = math.floor(b.x + (b.w - total) / 2)
  Paper.stamp(cfg, b.icon, ix, math.floor(b.y + (b.h - cfg.iconSize) / 2), ink, alpha)
  if b.showLabel then
    Text.draw(b.label, ix + iconW + cfg.iconGap, b.y + (b.h - th) / 2, {
      size = "body",
      color = open and colors.text or colors.textDim,
    })
  end
end

return Paper
