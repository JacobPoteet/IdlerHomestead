-- Audio service (GDD D100, #48, #104). Lives outside the sim: it listens to world events on the event
-- bus, reads the world through src/audio/sampler.lua, and plays cues from data/content/sounds.lua.
-- It owns no game state and never touches the sim RNG (variation comes from its own seeded stream).
--
--   one-shots   Audio:play(cueId)             UI sounds play always; cues with `world = true` are silent
--                                              while game time is paused or racing (sleep, skip-night)
--   beds        looping ambience, level eased toward the target from src/audio/cues.lua
--   pause       beds duck to tuning.audio.pausedDuck while time is paused; they never hard-stop
--   volumes     master / music / ambience / effects sliders from the settings store, applied live

local Backend = require("src.audio.backend")
local Cues = require("src.audio.cues")
local Library = require("src.audio.library")
local Mixer = require("src.audio.mixer")
local Rng = require("src.core.rng")

local Audio = {}
Audio.__index = Audio

local SLIDER = { master = "volumeMaster", music = "volumeMusic", ambience = "volumeAmbience", sfx = "volumeEffects" }
Audio.SLIDER = SLIDER

--- opts: tuning (the loaded tuning root), settings (store with :get), backend (default: LÖVE or silent),
--- fs (default love.filesystem), sounds (default data.content.sounds).
function Audio.new(opts)
  local sounds = opts.sounds or require("data.content.sounds")
  local backend = opts.backend or Backend.love()
  local cfg = opts.tuning.audio
  local self = setmetatable({
    cfg = cfg,
    settings = opts.settings,
    backend = backend,
    sounds = sounds,
    library = Library.new({ backend = backend, fs = opts.fs or love.filesystem, sounds = sounds, cfg = cfg }),
    rng = Rng.new(cfg.seed),
    time = 0, -- real seconds since start
    last = {}, -- cue id -> time it last played
    voices = {}, -- one-shot sources currently playing
    beds = {}, -- cue id -> { level, source, playing }
    duck = 1, -- 0..1, ambience ducking while paused
    focusGain = 1,
    focused = true,
    paused = false,
    speed = 1,
    snap = nil,
    sampleIn = 0,
    night = nil,
    music = nil,
    thunderIn = nil,
  }, Audio)
  return self
end

-- Volumes ---------------------------------------------------------------------------------------

function Audio:volumes()
  local v = {}
  for bus, id in pairs(SLIDER) do
    v[bus] = self.settings:get(id)
  end
  return v
end

--- Gain 0..1 of a bus from the sliders (before ducking and focus).
function Audio:busGain(bus)
  return Mixer.busGain(self:volumes(), bus, self.cfg)
end

-- One-shots -------------------------------------------------------------------------------------

local function pruneVoices(voices)
  local keep = {}
  for _, v in ipairs(voices) do
    if v:isPlaying() then
      keep[#keep + 1] = v
    end
  end
  return keep
end

--- Play a cue once. Returns true if it started. `opts.force` skips the paused/fast check (the sound
--- test); `opts.volume` scales the cue.
function Audio:play(id, opts)
  local def = self.sounds.cues[id]
  if not def or def.loop then
    return false
  end
  opts = opts or {}
  if def.world and not opts.force and (self.paused or self.speed > self.cfg.maxEventSpeed) then
    return false
  end
  if not opts.force and not Mixer.ready(self.last[id], self.time, def.cooldown) then
    return false
  end
  local gain = self:busGain(def.bus) * def.volume * (opts.volume or 1) * self.focusGain
  if gain <= 0 then
    return false
  end
  local source = self.library:pick(id, self.rng:float())
  if not source then
    return false
  end
  self.voices = pruneVoices(self.voices)
  if #self.voices >= self.cfg.maxVoices then
    return false
  end
  local voice = source
  local ok, copy = pcall(source.clone, source)
  if ok and copy then
    voice = copy
  else
    source:stop()
  end
  voice:setVolume(gain)
  voice:setPitch(Mixer.pitch(def.pitch, def.pitchVar, self.rng:float() * 2 - 1))
  voice:play()
  self.voices[#self.voices + 1] = voice
  self.last[id] = self.time
  return true
end

--- A short sound at the new level after a volume slider moved.
function Audio:preview()
  self:play(self.cfg.previewCue, { force = true })
end

-- Events ----------------------------------------------------------------------------------------

--- Start listening to a world's event bus and read it for the beds. `sampler()` returns the snapshot
--- (src/audio/sampler.lua) or nil.
function Audio:attach(world, sampler)
  self:detach()
  self.sampler = sampler
  self.unsub = world.events:onAny(function(name, payload)
    local cue = Cues.forEvent(self.sounds.events, name, payload)
    if cue then
      self:play(cue)
    end
  end)
  self.sampleIn = 0
  self.night = nil
end

function Audio:detach()
  if self.unsub then
    self.unsub()
    self.unsub = nil
  end
  self.sampler = nil
  self.snap = nil
  self.paused = false
  self.speed = 1
  self.thunderIn = nil
end

-- Beds ------------------------------------------------------------------------------------------

--- Name the music loop to play (a loop cue on the music bus), or nil for silence. No tracks exist yet.
function Audio:setMusic(id)
  self.music = id
end

--- Window focus changed (Mute when unfocused).
function Audio:setFocus(focused)
  self.focused = focused
end

local function targetsFor(self)
  local t = self.snap and Cues.beds(self.snap, self.cfg) or {}
  if self.music then
    t[self.music] = 1
  end
  if self.audition then
    t[self.audition] = 1
  end
  return t
end

local function updateBed(self, id, target, dt)
  local def = self.sounds.cues[id]
  if not def or not def.loop then
    return
  end
  local bed = self.beds[id]
  if not bed then
    bed = { level = 0 }
    self.beds[id] = bed
  end
  bed.level = Mixer.approach(bed.level, target, dt, self.cfg.bedFadeSeconds)
  if bed.level <= self.cfg.minBedLevel and target <= 0 then
    if bed.playing then
      bed.source:stop()
      bed.playing = false
    end
    bed.level = 0
    return
  end
  if not bed.source then
    bed.source = self.library:pick(id, 0)
    if not bed.source then
      return -- no sound for this bed: silent
    end
  end
  local duck = (def.bus == "sfx" or id == self.audition) and 1 or self.duck
  bed.source:setVolume(bed.level * def.volume * self:busGain(def.bus) * duck * self.focusGain)
  if not bed.playing then
    bed.source:setLooping(true)
    bed.source:play()
    bed.playing = true
  end
end

--- Advance fades and the world read. dt = real seconds.
function Audio:update(dt)
  self.time = self.time + dt
  local cfg = self.cfg
  local muted = self.focused == false and self.settings:get("muteUnfocused")
  self.focusGain = Mixer.approach(self.focusGain, muted and 0 or 1, dt, cfg.muteFadeSeconds)

  self.sampleIn = self.sampleIn - dt
  if self.sampler and self.sampleIn <= 0 then
    self.sampleIn = cfg.sampleSeconds
    self.snap = self.sampler()
  end
  local snap = self.snap
  self.paused = snap == nil or snap.speed == 0
  self.speed = snap and snap.speed or 1
  self.duck = Mixer.approach(self.duck, Mixer.duckTarget(self.paused, cfg), dt, cfg.duckSeconds)

  local targets = targetsFor(self)
  for id, def in pairs(self.sounds.cues) do
    if def.loop and (targets[id] or self.beds[id]) then
      updateBed(self, id, targets[id] or 0, dt)
    end
  end

  if snap then
    -- Dusk and dawn (a cue only on the change, never on the first read).
    if self.night ~= nil and snap.night ~= self.night then
      self:play(snap.night and "night_fall" or "dawn")
    end
    self.night = snap.night
    -- Thunder rolls on a storm day, on a render-local timer that stands still while paused.
    if snap.kind == "storm" and not self.paused then
      self.thunderIn = (self.thunderIn or self:thunderGap()) - dt
      if self.thunderIn <= 0 then
        self:play("thunder")
        self.thunderIn = self:thunderGap()
      end
    elseif snap.kind ~= "storm" then
      self.thunderIn = nil
    end
  end
end

function Audio:thunderGap()
  local gap = self.cfg.thunderGap
  return gap[1] + self.rng:float() * (gap[2] - gap[1])
end

-- Loops, for the sound test screen -----------------------------------------------------------

--- Is a loop cue sounding (a bed or an audition)?
function Audio:isLooping(id)
  local bed = self.beds[id]
  return bed ~= nil and bed.playing == true
end

--- Audition a loop (one at a time): start it at full level, ignoring the pause duck, or stop it.
--- Returns whether it is now playing.
function Audio:toggleLoop(id)
  local def = self.sounds.cues[id]
  if not def or not def.loop then
    return false
  end
  self.audition = self.audition ~= id and id or nil
  return self.audition == id
end

return Audio
