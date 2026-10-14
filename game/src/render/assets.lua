-- Sprite lookup built from assets/manifest.lua (GDD §9.2).
-- Placeholder sprites are painted into one atlas canvas; file sprites are image regions.
-- Game code only ever asks for sprites by id.

local Rng = require("src.core.rng")
local placeholders = require("src.render.placeholders")

local Assets = {}

local sprites = {}
local images = {}
local atlasSize = { 1, 1 } -- the placeholder atlas in pixels (the rim shader steps one texel at a time)

-- Pixel-drawing helper handed to placeholder painters.
local Painter = {}
Painter.__index = Painter

-- Pixels painted with a mostly opaque colour are remembered, so `outline` can ring the sprite.
local SOLID_ALPHA = 0.6 -- a colour at least this opaque counts as part of the shape (shadows do not)

function Painter:mark(x, y, c)
  if (c[4] or 1) >= SOLID_ALPHA then
    self.mask = self.mask or {}
    self.mask[y * self.w + x] = true
  end
end

function Painter:px(x, y, c)
  if x >= 0 and y >= 0 and x < self.w and y < self.h then
    love.graphics.setColor(c)
    love.graphics.rectangle("fill", self.ox + x, self.oy + y, 1, 1)
    self:mark(x, y, c)
  end
end

function Painter:rect(x, y, w, h, c)
  love.graphics.setColor(c)
  love.graphics.rectangle("fill", self.ox + x, self.oy + y, w, h)
  for yy = math.max(0, y), math.min(self.h, y + h) - 1 do
    for xx = math.max(0, x), math.min(self.w, x + w) - 1 do
      self:mark(xx, yy, c)
    end
  end
end

--- A 1-pixel ring of `c` round everything painted so far (4-neighbours), so a small sprite keeps a
--- silhouette on any ground, snow and night included (#20, D102). Call it last.
function Painter:outline(c)
  local m = self.mask
  if not m then
    return
  end
  local w, h = self.w, self.h
  local function has(x, y)
    return x >= 0 and y >= 0 and x < w and y < h and m[y * w + x]
  end
  local ring = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if not has(x, y) and (has(x - 1, y) or has(x + 1, y) or has(x, y - 1) or has(x, y + 1)) then
        ring[#ring + 1] = { x, y }
      end
    end
  end
  for _, t in ipairs(ring) do
    self:px(t[1], t[2], c)
  end
end

function Painter:ellipse(cx, cy, rx, ry, c)
  for y = -ry, ry do
    for x = -rx, rx do
      if (x * x) / (rx * rx + 0.5) + (y * y) / (ry * ry + 0.5) <= 1 then
        self:px(cx + x, cy + y, c)
      end
    end
  end
end

function Painter:circle(cx, cy, r, c)
  self:ellipse(cx, cy, r, r, c)
end

local function expand(manifest)
  local list = {}
  local ids = {}
  for id in pairs(manifest.sprites) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local entry = manifest.sprites[id]
    if entry.variants then
      for v = 1, entry.variants do
        list[#list + 1] = { id = id .. "_" .. v, entry = entry, variant = v }
      end
    else
      list[#list + 1] = { id = id, entry = entry, variant = 1 }
    end
  end
  return list
end

--- Build every sprite in the manifest. Call once after the window exists.
function Assets.load(manifest)
  sprites = {}
  local list = expand(manifest or require("assets.manifest"))

  -- Shelf-pack placeholders into an atlas, tallest first.
  local pending = {}
  for _, item in ipairs(list) do
    if item.entry.placeholder then
      pending[#pending + 1] = item
    end
  end
  table.sort(pending, function(a, b)
    if a.entry.h ~= b.entry.h then
      return a.entry.h > b.entry.h
    end
    return a.id < b.id
  end)
  local atlasW, pad = 256, 1
  local x, y, rowH = 0, 0, 0
  for _, item in ipairs(pending) do
    local e = item.entry
    if x + e.w > atlasW then
      x, y, rowH = 0, y + rowH + pad, 0
    end
    item.ax, item.ay = x, y
    x = x + e.w + pad
    rowH = math.max(rowH, e.h)
  end
  local atlasH = y + rowH
  atlasSize = { atlasW, math.max(1, atlasH) }
  if #pending > 0 then
    local canvas = love.graphics.newCanvas(atlasW, math.max(1, atlasH))
    canvas:setFilter("nearest", "nearest")
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    for _, item in ipairs(pending) do
      local e = item.entry
      local painter = placeholders[e.placeholder]
      assert(painter, "No placeholder painter '" .. tostring(e.placeholder) .. "'")
      local p = setmetatable({
        ox = item.ax,
        oy = item.ay,
        w = e.w,
        h = e.h,
        rng = Rng.new(Rng.hash(item.id)),
      }, Painter)
      painter(p, e.w, e.h, item.variant, item.id)
    end
    love.graphics.pop()
    for _, item in ipairs(pending) do
      local e = item.entry
      sprites[item.id] = {
        image = canvas,
        quad = love.graphics.newQuad(item.ax, item.ay, e.w, e.h, atlasW, atlasH),
        w = e.w,
        h = e.h,
      }
    end
  end

  for _, item in ipairs(list) do
    local e = item.entry
    if e.file then
      local image = images[e.file]
      if not image then
        image = love.graphics.newImage(e.file)
        image:setFilter("nearest", "nearest")
        images[e.file] = image
      end
      local iw, ih = image:getDimensions()
      sprites[item.id] = {
        image = image,
        quad = love.graphics.newQuad((e.x or 0) + (item.variant - 1) * e.w, e.y or 0, e.w, e.h, iw, ih),
        w = e.w,
        h = e.h,
      }
    end
  end
end

--- Sprite record { image, quad, w, h }. Errors on unknown ids.
function Assets.sprite(id)
  local s = sprites[id]
  if not s then
    error("Unknown sprite '" .. tostring(id) .. "'", 2)
  end
  return s
end

--- Size of the placeholder atlas every placeholder sprite is cut from, in pixels.
function Assets.atlasWidth()
  return atlasSize[1]
end

function Assets.atlasHeight()
  return atlasSize[2]
end

function Assets.has(id)
  return sprites[id] ~= nil
end

--- Draw a sprite with its top-left at (x, y).
function Assets.draw(id, x, y, sx, sy)
  local s = Assets.sprite(id)
  love.graphics.draw(s.image, s.quad, x, y, 0, sx or 1, sy or sx or 1)
end

return Assets
