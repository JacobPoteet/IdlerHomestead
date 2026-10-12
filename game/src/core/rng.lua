-- Seeded, serializable random number generator (mulberry32).
-- All gameplay randomness goes through this so runs are reproducible from a seed.
--
-- A generator keeps its state inside a plain table (`store.s`), which can live directly in
-- save data: attach() to a table from a loaded save and the stream continues where it left off.

local bit = require("bit")
local tobit, bxor, rshift, bor = bit.tobit, bit.bxor, bit.rshift, bit.bor

local TWO32 = 4294967296

-- 32-bit integer multiply (like JS Math.imul) without losing precision in doubles.
local function imul(a, b)
  a, b = a % TWO32, b % TWO32
  local ah, al = math.floor(a / 65536), a % 65536
  local bh, bl = math.floor(b / 65536), b % 65536
  return tobit(((ah * bl + al * bh) % 65536) * 65536 + al * bl)
end

local Rng = {}
Rng.__index = Rng

--- FNV-1a hash of a string to a 32-bit integer. Used to derive named streams from a seed.
function Rng.hash(str)
  local h = tobit(2166136261)
  for i = 1, #str do
    h = imul(bxor(h, str:byte(i)), 16777619)
  end
  return h
end

--- Create a generator with its own state table.
function Rng.new(seed)
  return Rng.attach({ s = tobit(seed or 0) })
end

--- Wrap an existing state table ({ s = number }), e.g. one loaded from a save.
function Rng.attach(store)
  assert(type(store) == "table" and type(store.s) == "number", "Rng.attach expects { s = number }")
  return setmetatable({ store = store }, Rng)
end

--- Seed for an independent named stream ("land", "weather", ...) derived from a run seed.
function Rng.deriveSeed(seed, name)
  return bxor(tobit(seed), Rng.hash(name))
end

--- A fresh, non-deterministic seed for starting a new run. Not for use inside the sim.
function Rng.freshSeed()
  return tobit(Rng.hash(tostring(os.time()) .. ":" .. tostring(os.clock()) .. ":" .. tostring({})))
end

--- Uniform float in [0, 1).
function Rng:float()
  local store = self.store
  store.s = tobit(store.s + 0x6D2B79F5)
  local a = store.s
  local t = imul(bxor(a, rshift(a, 15)), bor(a, 1))
  t = bxor(tobit(t + imul(bxor(t, rshift(t, 7)), bor(t, 61))), t)
  return (bxor(t, rshift(t, 14)) % TWO32) / TWO32
end

--- Uniform integer in [lo, hi] inclusive.
function Rng:int(lo, hi)
  assert(hi >= lo, "Rng:int requires hi >= lo")
  return lo + math.floor(self:float() * (hi - lo + 1))
end

--- Uniform float in [lo, hi).
function Rng:range(lo, hi)
  return lo + self:float() * (hi - lo)
end

--- True with probability p.
function Rng:chance(p)
  return self:float() < p
end

--- Random element of a non-empty array.
function Rng:pick(list)
  assert(#list > 0, "Rng:pick on empty list")
  return list[self:int(1, #list)]
end

--- Shuffle an array in place (Fisher-Yates) and return it.
function Rng:shuffle(list)
  for i = #list, 2, -1 do
    local j = self:int(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

--- Pick from an array using weightFn(item) -> non-negative number.
function Rng:weighted(list, weightFn)
  local total = 0
  for i = 1, #list do
    total = total + weightFn(list[i])
  end
  assert(total > 0, "Rng:weighted requires a positive total weight")
  local roll = self:float() * total
  for i = 1, #list do
    roll = roll - weightFn(list[i])
    if roll < 0 then
      return list[i]
    end
  end
  return list[#list]
end

return Rng
