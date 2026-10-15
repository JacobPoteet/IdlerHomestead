-- Blue noise by void-and-cluster (Ulichney): a size x size tile where every pixel has a distinct rank
-- 0..n-1 and ranks that are close in value are far apart in space, so thresholding it at any level gives
-- an even stipple with no grid. Built once in code from a fixed seed (no image file); about 0.2 s for 64x64.
-- Pure Lua: no love.* calls, so it is tested headless.

local Rng = require("src.core.rng")

local BlueNoise = {}

local SEED = 20261014 -- fixed: the pattern must not change between runs
local SIGMA = 1.5 -- texels, width of the gaussian that spreads each point's influence
local START = 0.1 -- share of texels set in the first random pattern

--- Ranks (a 1-based array of size*size integers, each of 0..n-1 exactly once), row by row.
function BlueNoise.ranks(size)
  local n = size * size
  local rng = Rng.new(SEED)
  local reach = math.ceil(SIGMA * 3)
  local offsets = {} -- the gaussian window: { dx, dy, weight }
  for dy = -reach, reach do
    for dx = -reach, reach do
      offsets[#offsets + 1] = { dx, dy, math.exp(-(dx * dx + dy * dy) / (2 * SIGMA * SIGMA)) }
    end
  end
  local on, energy = {}, {}
  for i = 1, n do
    on[i], energy[i] = false, 0
  end
  local function toggle(i, sign)
    local x, y = (i - 1) % size, math.floor((i - 1) / size)
    for _, o in ipairs(offsets) do
      local j = ((y + o[2]) % size) * size + (x + o[1]) % size + 1
      energy[j] = energy[j] + sign * o[3]
    end
    on[i] = sign > 0
  end
  -- The tightest cluster is the set pixel with the most energy; the largest void the unset one with the least.
  local function tightest()
    local best, at = -1, nil
    for i = 1, n do
      if on[i] and energy[i] > best then
        best, at = energy[i], i
      end
    end
    return at
  end
  local function largestVoid()
    local best, at = math.huge, nil
    for i = 1, n do
      if not on[i] and energy[i] < best then
        best, at = energy[i], i
      end
    end
    return at
  end

  local start = math.max(1, math.floor(n * START))
  local order = {}
  for i = 1, n do
    order[i] = i
  end
  rng:shuffle(order)
  for k = 1, start do
    toggle(order[k], 1)
  end
  -- Relax: move the tightest cluster into the largest void until it would only move back.
  for _ = 1, n do
    local cluster = tightest()
    toggle(cluster, -1)
    local void = largestVoid()
    toggle(void, 1)
    if void == cluster then
      break
    end
  end

  local ranks = {}
  local settled, setCount = {}, start
  for i = 1, n do
    settled[i] = on[i]
  end
  -- Phase 1: take the set pixels away, tightest first; the last one removed gets rank 0.
  for r = start - 1, 0, -1 do
    local cluster = tightest()
    toggle(cluster, -1)
    ranks[cluster] = r
  end
  -- Phase 2: put the first pattern back, then fill the largest voids in turn.
  for i = 1, n do
    if settled[i] then
      toggle(i, 1)
    end
  end
  for r = setCount, n - 1 do
    local void = largestVoid()
    toggle(void, 1)
    ranks[void] = r
  end
  return ranks
end

return BlueNoise
