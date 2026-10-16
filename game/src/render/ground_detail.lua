-- Ground variety, painted once into the static ground canvas over the grass tiles: broad soft patches
-- of lighter and darker grass (world-anchored value noise, cut into a couple of flat steps so it stays
-- pixel art). Deterministic from the position, never the sim RNG. Settings in tuning.visuals.groundDetail.

local Grid = require("src.sim.grid")
local bit = require("bit")

local GroundDetail = {}

-- a * k modulo 2^32, exact in doubles: the multiply is done in two 16-bit halves.
local function mul32(a, k)
  local lo, hi = bit.band(a, 0xffff), bit.rshift(a, 16)
  return bit.tobit(lo * k + bit.lshift(bit.tobit(hi * k), 16))
end

-- A well-mixed 0..1 value for integer (x, y, salt): the inputs are spread by primes, then run through
-- murmur3's finaliser (multiplies and xor-shifts), so neighbouring cells get unrelated
-- values (no rows, columns or repeated layouts in the scatter).
local function hash(x, y, salt)
  local h = bit.bxor(bit.tobit(x * 73856093), bit.tobit(y * 19349663), bit.tobit(salt * 83492791))
  h = bit.bxor(h, bit.rshift(h, 16))
  h = mul32(h, 0x85ebca6b)
  h = bit.bxor(h, bit.rshift(h, 13))
  h = mul32(h, 0xc2b2ae35)
  h = bit.bxor(h, bit.rshift(h, 16))
  return bit.rshift(h, 16) / 65536
end

--- Smooth value noise in 0..1 at (x, y) (any real numbers), with lattice `salt`.
function GroundDetail.noise(x, y, salt)
  local ix, iy = math.floor(x), math.floor(y)
  local fx, fy = x - ix, y - iy
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local a, b = hash(ix, iy, salt), hash(ix + 1, iy, salt)
  local c, d = hash(ix, iy + 1, salt), hash(ix + 1, iy + 1, salt)
  return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
end

--- The patch step at world art pixel (px, py): -2..2 (negative = darker grass, positive = lighter).
function GroundDetail.patch(cfg, px, py)
  local n = GroundDetail.noise(px * cfg.patchScale, py * cfg.patchScale, 1) * 0.7
    + GroundDetail.noise(px * cfg.patchScale * 2.3, py * cfg.patchScale * 2.3, 2) * 0.3
  if n > cfg.lightCut + cfg.step then
    return 2
  elseif n > cfg.lightCut then
    return 1
  elseif n < cfg.darkCut - cfg.step then
    return -2
  elseif n < cfg.darkCut then
    return -1
  end
  return 0
end

--- Paint the variety over the grass of `grid` into the current canvas (art pixels, origin at the map's
--- top-left). `tile` is the tile size in art pixels.
function GroundDetail.paint(grid, tile, cfg)
  if not cfg.enabled then
    return
  end
  local block = cfg.block
  local bw, bh = math.ceil(grid.w * tile / block), math.ceil(grid.h * tile / block)
  local data = love.image.newImageData(bw, bh)
  local levels = { [-2] = cfg.dark2, [-1] = cfg.dark1, [1] = cfg.light1, [2] = cfg.light2 }
  for by = 0, bh - 1 do
    local ty = math.floor(by * block / tile) + 1
    for bx = 0, bw - 1 do
      local tx = math.floor(bx * block / tile) + 1
      if grid.terrain[Grid.index(grid, tx, ty)] == "grass" then
        local c = levels[GroundDetail.patch(cfg, bx * block, by * block)]
        if c then
          data:setPixel(bx, by, c[1], c[2], c[3], c[4])
        end
      end
    end
  end
  local overlay = love.graphics.newImage(data)
  overlay:setFilter("nearest", "nearest")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(overlay, 0, 0, 0, block, block)
  overlay:release()
end

return GroundDetail
