-- Smooth value noise over a coarse random lattice, seeded from an Rng. Returns values in 0..1.

local Noise = {}

--- w, h: area in tiles; scale: tiles per lattice cell. Returns sample(x, y).
function Noise.value(rng, w, h, scale)
  local cols = math.ceil(w / scale) + 2
  local rows = math.ceil(h / scale) + 2
  local lattice = {}
  for i = 1, cols * rows do
    lattice[i] = rng:float()
  end
  local function at(cx, cy)
    return lattice[cy * cols + cx + 1]
  end
  local function smooth(t)
    return t * t * (3 - 2 * t)
  end
  return function(x, y)
    local fx, fy = x / scale, y / scale
    local cx, cy = math.floor(fx), math.floor(fy)
    local tx, ty = smooth(fx - cx), smooth(fy - cy)
    local top = at(cx, cy) + (at(cx + 1, cy) - at(cx, cy)) * tx
    local bottom = at(cx, cy + 1) + (at(cx + 1, cy + 1) - at(cx, cy + 1)) * tx
    return top + (bottom - top) * ty
  end
end

return Noise
