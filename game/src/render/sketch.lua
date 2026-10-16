-- Plans drawn in pencil on the land (GDD §9.4, D142, #292): whatever is planned but not real yet. Planned,
-- untilled tiles get a diagonal hatch; the outer edge of each planned area gets a pencil line that runs past
-- its corners, with a faint second stroke; planned crops and buildings being placed or queued are drawn as
-- sketches through shaders/sketch.glsl. At night the scene draws the same lines again over the graded world
-- in pale chalk. Presentation only: it reads the sim's plan, crops and tilled soil and never changes them.
--
-- Area marks (D147) share the pass: the Axe's marks use the diagonal hatch in graphite, the Pail's a wavy hatch
-- (a run of little waves, like water) in blue pencil, so the two read apart in daylight and in chalk at night.
--
-- The hatch and the edge strokes are cut from one small white atlas built from tuning.visuals.sketch, so a
-- field of any size is a run of same-texture draws that LÖVE batches.

local Grid = require("src.sim.grid")
local Shaders = require("src.render.shaders")

local Sketch = {}

local atlas -- { image, key, quads = { hatch, h = { [a][b] }, v = { [a][b] } }, ov }

local function hash(x, y)
  local h = (x * 374761393 + y * 668265263) % 2147483647
  h = (h * (h % 1013 + 1)) % 1000003
  return (h % 1000) / 1000
end

-- Build (or reuse) the atlas for this tile size and these tuning values.
local function build(cfg, tile)
  local ov = cfg.overshoot
  local parts = {
    tile,
    ov,
    cfg.hatchAlpha,
    cfg.hatchEvery,
    cfg.grain,
    cfg.edgeAlpha,
    cfg.secondStroke,
    cfg.waveEvery,
    cfg.waveAmp,
    cfg.waveCycles,
  }
  local key = table.concat(parts, ":")
  if atlas and atlas.key == key then
    return atlas
  end
  local long = tile + 2 * ov
  local size = math.max(tile, long) + 4
  local data = love.image.newImageData(size, size)
  -- The hatch: one tile, the pattern anchored so neighbouring tiles join into one shaded area.
  for y = 0, tile - 1 do
    for x = 0, tile - 1 do
      if (x + y) % cfg.hatchEvery == 0 and hash(x, y) >= cfg.grain then
        data:setPixel(x, y, 1, 1, 1, cfg.hatchAlpha)
      end
    end
  end
  -- The strokes: row (or column) 0 is the line, 1 the faint second stroke on its inner side. The first and
  -- last `ov` pixels are the overshoot past a corner, a little lighter.
  local hy, vx = tile + 1, tile + 1
  for k = 0, long - 1 do
    local over = k < ov or k >= ov + tile
    local a = cfg.edgeAlpha * (over and 0.65 or 1) * (hash(k * 3 + 1, 7) < 0.08 and 0.5 or 1)
    data:setPixel(k, hy, 1, 1, 1, a)
    data:setPixel(vx, k, 1, 1, 1, a)
    if not over and hash(k, 11) < cfg.secondStroke then
      data:setPixel(k, hy + 1, 1, 1, 1, cfg.edgeAlpha * 0.4)
    end
    if not over and hash(k, 13) < cfg.secondStroke then
      data:setPixel(vx + 1, k, 1, 1, 1, cfg.edgeAlpha * 0.4)
    end
  end
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  -- The wavy hatch: rows of little waves, `waveCycles` to a tile so neighbouring tiles join up.
  local waves = love.image.newImageData(tile, tile)
  for row = 1, tile - 1, cfg.waveEvery do
    for x = 0, tile - 1 do
      local y = row + math.floor(math.sin(2 * math.pi * cfg.waveCycles * x / tile) * cfg.waveAmp + 0.5)
      if y >= 0 and y < tile and hash(x, y + 99) >= cfg.grain then
        waves:setPixel(x, y, 1, 1, 1, cfg.hatchAlpha)
      end
    end
  end
  local waveImage = love.graphics.newImage(waves)
  waveImage:setFilter("nearest", "nearest")
  local function q(x, y, w, h)
    return love.graphics.newQuad(x, y, w, h, size, size)
  end
  local quads =
    { hatch = q(0, 0, tile, tile), wave = love.graphics.newQuad(0, 0, tile, tile, tile, tile), h = {}, v = {} }
  for a = 0, 1 do
    quads.h[a], quads.v[a] = {}, {}
    for b = 0, 1 do
      local from, len = (1 - a) * ov, tile + (a + b) * ov
      quads.h[a][b] = q(from, hy, len, 2)
      quads.v[a][b] = q(vx, from, 2, len)
    end
  end
  atlas = { image = image, waveImage = waveImage, key = key, quads = quads, ov = ov }
  return atlas
end

--- Hatch and outline an area. `planned(i)` says whether tile i belongs to it, `visible` is { x1, y1, x2, y2 }
--- in tiles, `inkFor(i)` gives a tile's ink colour, and `alpha` scales it. The tiles looked at are the keys
--- of the plan, or `list` (an array of tile indexes) when given. `style` (optional) is { wave, always }: `wave`
--- shades with the wavy hatch (the Pail's marks), `always` shades tilled tiles too (a marked crop).
function Sketch.drawPlans(world, tile, planned, visible, inkFor, alpha, list, style)
  local cfg = world.tuning.visuals.sketch
  local A = build(cfg, tile)
  local grid, tilled = world.state.grid, world.state.fields.tilled
  local quads, ov = A.quads, A.ov
  local function at(x, y)
    return x >= 1 and y >= 1 and x <= grid.w and y <= grid.h and planned(Grid.index(grid, x, y))
  end
  local function each(i)
    local x, y = Grid.coords(grid, i)
    if x >= visible[1] and x <= visible[3] and y >= visible[2] and y <= visible[4] and planned(i) then
      local ink = inkFor(i)
      love.graphics.setColor(ink[1], ink[2], ink[3], alpha)
      local left, top = (x - 1) * tile, (y - 1) * tile
      if style and style.wave then
        love.graphics.draw(A.waveImage, quads.wave, left, top)
      elseif not tilled[i] or style and style.always then
        love.graphics.draw(A.image, quads.hatch, left, top)
      end
      -- Overshoot at the ends of a run: where the area does not go on along the edge.
      local l, r = at(x - 1, y) and 0 or 1, at(x + 1, y) and 0 or 1
      local u, d = at(x, y - 1) and 0 or 1, at(x, y + 1) and 0 or 1
      if u == 1 then
        love.graphics.draw(A.image, quads.h[l][r], left - l * ov, top + 1)
      end
      if d == 1 then
        love.graphics.draw(A.image, quads.h[l][r], left - l * ov, top + tile - 1, 0, 1, -1)
      end
      if l == 1 then
        love.graphics.draw(A.image, quads.v[u][d], left + 1, top - u * ov)
      end
      if r == 1 then
        love.graphics.draw(A.image, quads.v[u][d], left + tile - 1, top - u * ov, 0, -1, 1)
      end
    end
  end
  if list then
    for _, i in ipairs(list) do
      each(i)
    end
  else
    for i in pairs(world.state.fields.plan) do
      each(i)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw `sprite` at x, y as a pencil sketch in `color` (rgb). opts: { hatch, wash, alpha } (0..1).
function Sketch.sprite(sprite, x, y, color, opts)
  local shader = Shaders.get("sketch")
  if not shader then
    love.graphics.setColor(color[1], color[2], color[3], 0.5)
    love.graphics.draw(sprite.image, sprite.quad, x, y)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local cell = sprite.sketchCell
  if not cell then
    local iw, ih = sprite.image:getDimensions()
    local qx, qy, qw, qh = sprite.quad:getViewport()
    cell = { { qx / iw, qy / ih, (qx + qw) / iw, (qy + qh) / ih }, { 1 / iw, 1 / ih } }
    sprite.sketchCell = cell
  end
  Shaders.send(shader, { bounds = cell[1], texel = cell[2], hatch = opts.hatch, wash = opts.wash })
  love.graphics.setShader(shader)
  love.graphics.setColor(color[1], color[2], color[3], rawget(opts, "alpha") or 1) -- opts may be a strict tuning table
  love.graphics.draw(sprite.image, sprite.quad, x, y)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
end

return Sketch
