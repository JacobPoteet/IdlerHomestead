-- The thin layer between the audio service and LÖVE (GDD D100). The service only ever calls these
-- functions, so tests and the screenshot driver hand it a silent stand-in that records what would
-- have played. A real device is never required.
--
-- A backend is { newSoundData(samples, rate), newSource(dataOrPath, mode) }. A source understands
-- the LÖVE Source methods the service uses: play, stop, isPlaying, setVolume, setPitch, setLooping, clone.

local Backend = {}

local NullSource = {}
NullSource.__index = NullSource

function NullSource:play()
  self.playing = true
  self.plays = self.plays + 1
  if self.log then
    self.log[#self.log + 1] = { what = self.what, volume = self.volume, pitch = self.pitch, loop = self.looping }
  end
  return true
end
function NullSource:stop()
  self.playing = false
end
function NullSource:isPlaying()
  return self.playing and self.looping -- a one-shot "finishes" at once, so voices never pile up in tests
end
function NullSource:setVolume(v)
  self.volume = v
end
function NullSource:setPitch(p)
  self.pitch = p
end
function NullSource:setLooping(l)
  self.looping = l
end
function NullSource:clone()
  local c = setmetatable({ volume = 1, pitch = 1, looping = false, playing = false, plays = 0, what = self.what, log = self.log }, NullSource)
  return c
end

--- A silent backend. `backend.log` collects { what, volume, pitch, loop } for every play, `what` being
--- the file path or "synth:<n samples>".
function Backend.null()
  local log = {}
  local self = { log = log, silent = true }
  function self.newSoundData(samples, rate)
    return { samples = samples, rate = rate }
  end
  function self.newSource(x)
    local what = type(x) == "string" and x or ("synth:" .. #x.samples)
    return setmetatable({ volume = 1, pitch = 1, looping = false, playing = false, plays = 0, what = what, log = log }, NullSource)
  end
  return self
end

--- The real thing, or the silent backend when LÖVE has no audio or sound module (the tests) or no
--- device could be opened.
function Backend.love()
  if not (love and love.audio and love.sound) then
    return Backend.null()
  end
  local ok = pcall(love.audio.getVolume)
  if not ok then
    return Backend.null()
  end
  local self = { silent = false }
  function self.newSoundData(samples, rate)
    local data = love.sound.newSoundData(#samples, rate, 16, 1)
    for i = 1, #samples do
      data:setSample(i - 1, samples[i])
    end
    return data
  end
  function self.newSource(x, mode)
    return love.audio.newSource(x, mode or "static")
  end
  return self
end

return Backend
