-- Paper (GDD §9.4, D142, D143): the surface of the Notebook and the Ledger. A plate lit like the world
-- (src/ui/plate.lua) in a paper colour, with a fibre of light and dark flecks on the UI pixel grid over it.
-- The flecks are made once per page size and kept as an image, so a frame costs one draw. Presentation only.
-- Knobs: tuning.ui.book.

local Icons = require("src.ui.icons")
local Plate = require("src.ui.plate")

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

return Paper
