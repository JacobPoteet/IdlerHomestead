-- Placeholder sound generators (GDD D100, #48). Pure Lua: every generator returns a plain array of
-- samples in -1..1, so it can be tested without an audio device. The library turns them into
-- SoundData. A cue in data/content/sounds.lua names one generator and its arguments; a file dropped in
-- game/assets/audio/<bus>/<cue>.ogg replaces it with no code change (docs/AUDIO.md).
--
-- Everything here is deterministic: the noise comes from a small generator seeded by the cue id.

local Synth = {}

local TAU = math.pi * 2

--- A repeatable noise source in -1..1 for a seed.
local function noiseFrom(seed)
  local s = math.floor(seed) % 2147483647
  if s <= 0 then
    s = s + 2147483646
  end
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647 * 2 - 1
  end
end

--- Seed for a cue id (stable across runs and platforms).
function Synth.seedOf(id)
  local h = 5381
  for i = 1, #id do
    h = (h * 33 + id:byte(i)) % 2147483647
  end
  return h
end

local function blank(n)
  local buf = {}
  for i = 1, n do
    buf[i] = 0
  end
  return buf
end

--- Scale so the loudest sample is `peak`.
local function normalise(buf, peak)
  local top = 0
  for i = 1, #buf do
    local a = math.abs(buf[i])
    if a > top then
      top = a
    end
  end
  if top > 0 then
    local k = peak / top
    for i = 1, #buf do
      buf[i] = buf[i] * k
    end
  end
  return buf
end

--- Blend the tail into the head so a loop has no click at its seam.
local function loopify(buf, fade)
  local n = #buf
  fade = math.min(fade, math.floor(n / 4))
  for i = 1, fade do
    local k = i / fade -- 0 at the seam's start, 1 once the head is back to itself
    local tail = n - fade + i
    buf[i] = buf[i] * k + buf[tail] * (1 - k)
  end
  for i = 1, fade do
    buf[n - fade + i] = nil
  end
  return buf
end

local function lowpass(buf, a)
  local y = 0
  for i = 1, #buf do
    y = y + a * (buf[i] - y)
    buf[i] = y
  end
  return buf
end

local function highpass(buf, a)
  local y = 0
  for i = 1, #buf do
    y = y + a * (buf[i] - y)
    buf[i] = buf[i] - y
  end
  return buf
end

local function whiteNoise(n, noise)
  local buf = {}
  for i = 1, n do
    buf[i] = noise()
  end
  return buf
end

-- Generators ---------------------------------------------------------------------------------
-- Each takes (args, rate, noise) and returns { samples, loop = bool }.

local G = {}

--- A soft impact: filtered noise plus a falling thump. Chop, dig, pick, splash, thunk.
function G.thud(a, rate, noise)
  local n = math.floor(a.dur * rate)
  local hiss = lowpass(whiteNoise(n, noise), a.lp or 0.2)
  local buf = blank(n)
  local phase = 0
  for i = 1, n do
    local t = (i - 1) / rate
    local env = math.min(1, t / 0.004) * math.exp(-t / a.decay)
    local f = (a.freq or 110) * (0.6 + 0.4 * math.exp(-t * 14))
    phase = phase + TAU * f / rate
    buf[i] = (hiss[i] * (a.noise or 1) + math.sin(phase) * (a.body or 0.5)) * env
  end
  return { samples = buf }
end

--- A short sine tone, optionally gliding. UI taps, toasts, alerts.
function G.blip(a, rate)
  local n = math.floor(a.dur * rate)
  local buf = blank(n)
  local phase = 0
  for i = 1, n do
    local t = (i - 1) / rate
    local u = (i - 1) / n
    local f = a.freq + ((a.freqEnd or a.freq) - a.freq) * u
    phase = phase + TAU * f / rate
    local env = math.min(1, t / 0.003) * math.exp(-t / a.decay)
    buf[i] = (math.sin(phase) + (a.harm or 0) * math.sin(phase * 2)) * env
  end
  return { samples = buf }
end

--- A run of soft notes, each ringing out. Chimes: fish on, fish caught, learned something.
function G.chime(a, rate)
  local step = math.floor(a.step * rate)
  local ring = math.floor(a.ring * rate)
  local n = step * (#a.notes - 1) + ring
  local buf = blank(n)
  for k, f in ipairs(a.notes) do
    local start = (k - 1) * step
    for i = 1, ring do
      local t = (i - 1) / rate
      local env = math.min(1, t / 0.004) * math.exp(-t / a.decay)
      buf[start + i] = buf[start + i] + (math.sin(TAU * f * t) + 0.3 * math.sin(TAU * f * 2.01 * t)) * env
    end
  end
  return { samples = buf }
end

--- Filtered noise that loops: creek, wind, rain. `mod` is a slow swell (0..1) at `modRate` Hz;
--- `lp` and `hp` are one-pole coefficients (higher = more treble kept / more bass removed).
function G.noise_loop(a, rate, noise)
  local n = math.floor(a.dur * rate)
  local buf = lowpass(whiteNoise(n, noise), a.lp)
  if a.hp then
    highpass(buf, a.hp)
  end
  if a.mod and a.mod > 0 then
    for i = 1, n do
      local t = (i - 1) / rate
      buf[i] = buf[i] * (1 - a.mod + a.mod * (0.5 + 0.5 * math.sin(TAU * a.modRate * t)))
    end
  end
  return { samples = loopify(buf, math.floor(0.25 * rate)), loop = true }
end

--- A low steady hum with harmonics (the inverter). `dur` x `freq` should be a whole number so it loops cleanly.
function G.hum(a, rate)
  local n = math.floor(a.dur * rate)
  local buf = blank(n)
  for i = 1, n do
    local t = (i - 1) / rate
    local s = 0
    for h, w in ipairs(a.harmonics) do
      s = s + w * math.sin(TAU * a.freq * h * t)
    end
    buf[i] = s
  end
  return { samples = buf, loop = true }
end

--- Sparse crackling pops over a faint bed (stove, campfire).
function G.crackle(a, rate, noise)
  local n = math.floor(a.dur * rate)
  local buf = lowpass(whiteNoise(n, noise), 0.05)
  for i = 1, n do
    buf[i] = buf[i] * 0.25
  end
  local pops = math.floor(a.density * a.dur)
  for _ = 1, pops do
    local at = math.floor((noise() * 0.5 + 0.5) * (n - 400)) + 1
    local amp = 0.3 + 0.7 * (noise() * 0.5 + 0.5)
    local len = 60 + math.floor((noise() * 0.5 + 0.5) * 240)
    for j = 0, len - 1 do
      buf[at + j] = buf[at + j] + noise() * amp * math.exp(-j / (len * 0.25))
    end
  end
  return { samples = loopify(lowpass(buf, a.lp or 0.6), math.floor(0.2 * rate)), loop = true }
end

--- A tiny purr: low tone chopped at a purring rate.
function G.purr(a, rate, noise)
  local n = math.floor(a.dur * rate)
  local hiss = lowpass(whiteNoise(n, noise), 0.04)
  local buf = blank(n)
  for i = 1, n do
    local t = (i - 1) / rate
    local pulse = 0.5 + 0.5 * math.sin(TAU * a.rate * t)
    buf[i] = (math.sin(TAU * a.freq * t) * 0.6 + hiss[i] * 3) * (0.35 + 0.65 * pulse * pulse)
  end
  return { samples = loopify(buf, math.floor(0.15 * rate)), loop = true }
end

--- Scattered bird chirps (rising glides) in a quiet bed.
function G.chirps(a, rate, noise)
  local n = math.floor(a.dur * rate)
  local buf = blank(n)
  for _ = 1, a.count do
    local start = math.floor((noise() * 0.5 + 0.5) * (n - rate * 0.5)) + 1
    local f0 = a.freq * (0.8 + 0.4 * (noise() * 0.5 + 0.5))
    local reps = 1 + math.floor((noise() * 0.5 + 0.5) * 3)
    local at = start
    for _ = 1, reps do
      local len = math.floor(0.09 * rate)
      local phase = 0
      for j = 1, len do
        local u = (j - 1) / len
        phase = phase + TAU * (f0 + a.span * u) / rate
        local env = math.sin(math.pi * u)
        if buf[at + j] then
          buf[at + j] = buf[at + j] + math.sin(phase) * env * env
        end
      end
      at = at + math.floor(0.13 * rate)
    end
  end
  return { samples = loopify(buf, math.floor(0.1 * rate)), loop = true }
end

--- Crickets: a high tone chopped into fast pulse groups.
function G.crickets(a, rate)
  local n = math.floor(a.dur * rate)
  local buf = blank(n)
  for i = 1, n do
    local t = (i - 1) / rate
    local group = (t * a.groupRate) % 1
    local gate = group < 0.5 and (0.5 + 0.5 * math.sin(TAU * a.pulseRate * t)) or 0
    buf[i] = math.sin(TAU * a.freq * t) * gate * gate
  end
  return { samples = loopify(buf, math.floor(0.1 * rate)), loop = true }
end

--- Low rolling rumble that swells and fades once (thunder).
function G.rumble(a, rate, noise)
  local n = math.floor(a.dur * rate)
  local buf = lowpass(lowpass(whiteNoise(n, noise), a.lp), a.lp * 1.5)
  for i = 1, n do
    local u = (i - 1) / n
    local roll = 0.6 + 0.4 * math.sin(TAU * a.roll * u * a.dur)
    buf[i] = buf[i] * math.sin(math.pi * u ^ 0.5) * (1 - u) * roll
  end
  return { samples = buf }
end

--- Names of the available generators (the sounds data file and the tests check against this).
function Synth.has(id)
  return G[id] ~= nil
end

--- Render a generator to samples. Returns { samples = array, loop = bool } or nil for an unknown generator.
--- `opts.rate` Hz, `opts.seed` any number (the cue id's hash), `opts.peak` loudest sample (default 0.8).
function Synth.render(gen, args, opts)
  local fn = G[gen]
  if not fn then
    return nil
  end
  local out = fn(args or {}, opts.rate, noiseFrom(opts.seed or 1))
  normalise(out.samples, opts.peak or 0.8)
  out.rate = opts.rate
  return out
end

return Synth
