-- Audio foundation (GDD D100, #48, #104, #239): event -> cue mapping, bus volume maths, cooldowns,
-- missing-asset safety, drop-in replacement, pause ducking, settings sliders, determinism. Everything
-- runs on the silent backend: no audio device is needed.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Save = require("src.core.save")
local Settings = require("src.core.settings")
local Events = require("src.core.events")
local Audio = require("src.audio.service")
local Backend = require("src.audio.backend")
local Cues = require("src.audio.cues")
local Mixer = require("src.audio.mixer")
local Synth = require("src.audio.synth")
local sounds = require("data.content.sounds")

local tun = tuningLoader.load()
local cfg = tun.audio

local function newAudio(opts)
  opts = opts or {}
  local settings = Settings.new(Save.memoryBackend(), tun)
  local backend = opts.backend or Backend.null()
  local fs = opts.fs or { getInfo = function() return nil end }
  local audio = Audio.new({ tuning = tun, settings = settings, backend = backend, fs = fs, sounds = opts.sounds })
  return audio, backend, settings
end

local calm = { speed = 1, night = false, season = "summer", kind = "clear", wind = 1, rain = 0, frozen = false, fire = nil, hum = false }

T.test("audio: events map to cues by name, by payload field, and by default", function()
  local ev = sounds.events
  T.eq(Cues.forEvent(ev, "fish.caught", {}), "fish_caught")
  T.eq(Cues.forEvent(ev, "object.cleared", { object = "tree" }), "chop_wood")
  T.eq(Cues.forEvent(ev, "object.cleared", { object = "brush" }), "clear")
  T.eq(Cues.forEvent(ev, "task.completed", { task = "move" }), nil)
  T.eq(Cues.forEvent(ev, "object.placed", { object = "wood_stove" }), "stove_lit")
  T.eq(Cues.forEvent(ev, "object.placed", { object = "chest" }), "place")
  T.eq(Cues.forEvent(ev, "weather.changed", { kind = "storm" }), "thunder")
  T.eq(Cues.forEvent(ev, "weather.changed", { kind = "rain" }), nil)
  T.eq(Cues.forEvent(ev, "no.such.event", {}), nil)
end)

T.test("audio: the sounds data is consistent", function()
  local buses = {}
  for _, b in ipairs(sounds.buses) do
    buses[b] = true
  end
  for id, def in pairs(sounds.cues) do
    T.truthy(buses[def.bus], id .. " has an unknown bus")
    T.truthy(def.volume > 0 and def.volume <= 1, id .. " volume")
    T.truthy(def.where and def.desc, id .. " needs where and desc")
    T.truthy(def.gen and Synth.has(def.gen), id .. " needs a known placeholder generator")
    T.truthy(def.loop == nil or def.loop == (def.bus == "ambience" or def.bus == "music"), id .. " loop flag")
  end
  local function check(rule, name)
    local cues = type(rule) == "string" and { rule } or {}
    if type(rule) == "table" then
      for _, c in pairs(rule.map) do
        cues[#cues + 1] = c
      end
      cues[#cues + 1] = rule.default
    end
    for _, c in ipairs(cues) do
      T.truthy(sounds.cues[c], name .. " -> unknown cue " .. tostring(c))
    end
  end
  for name, rule in pairs(sounds.events) do
    check(rule, name)
  end
  for id in pairs(Cues.beds(calm, cfg)) do
    T.truthy(sounds.cues[id] and sounds.cues[id].loop, "bed " .. id .. " needs a loop cue")
  end
end)

T.test("audio: every placeholder renders finite, quiet, repeatable samples", function()
  for id, def in pairs(sounds.cues) do
    local a = Synth.render(def.gen, def.args, { rate = cfg.rate, seed = Synth.seedOf(id) })
    local b = Synth.render(def.gen, def.args, { rate = cfg.rate, seed = Synth.seedOf(id) })
    T.truthy(a and #a.samples > 100, id .. " is empty")
    T.eq(#a.samples, #b.samples, id)
    if def.loop then
      T.truthy(a.loop, id .. " must render a loop")
    end
    local peak = 0
    for i = 1, #a.samples do
      local s = a.samples[i]
      T.truthy(s == s and math.abs(s) <= 1, id .. " sample out of range")
      T.eq(s, b.samples[i], id .. " not repeatable")
      peak = math.max(peak, math.abs(s))
    end
    T.truthy(peak > 0.1, id .. " is silent")
    T.truthy(#a.samples / cfg.rate < 10, id .. " is long")
  end
end)

T.test("audio: bus volume maths", function()
  T.eq(Mixer.curve(0.5, 2), 0.25)
  T.eq(Mixer.curve(2, 2), 1)
  T.eq(Mixer.curve(-1, 2), 0)
  local v = { master = 1, music = 0.5, ambience = 1, sfx = 0 }
  T.eq(Mixer.busGain(v, "sfx", cfg), 0)
  T.eq(Mixer.busGain(v, "ambience", cfg), 1)
  v.master = 0.5
  T.eq(Mixer.busGain(v, "ambience", cfg), 0.25)
  T.eq(Mixer.approach(0, 1, 0.5, 2), 0.25)
  T.eq(Mixer.approach(1, 0, 10, 2), 0)
  T.eq(Mixer.duckTarget(true, cfg), cfg.pausedDuck)
  T.eq(Mixer.duckTarget(false, cfg), 1)
  T.eq(Mixer.pitch(1, 0.1, -1), 0.9)
  T.truthy(Mixer.ready(nil, 0, 1))
  T.falsy(Mixer.ready(0, 0.5, 1))
  T.truthy(Mixer.ready(0, 1, 1))
end)

T.test("audio: ambience beds follow weather, time of day and season", function()
  local function beds(over)
    local snap = {}
    for k, v in pairs(calm) do
      snap[k] = v
    end
    for k, v in pairs(over) do
      snap[k] = v
    end
    return Cues.beds(snap, cfg)
  end
  local day = beds({})
  T.eq(day.amb_birds, 1)
  T.eq(day.amb_crickets, 0)
  T.eq(day.amb_creek, 1)
  T.eq(day.amb_wind, 0)
  T.eq(beds({ night = true }).amb_crickets, 1)
  T.eq(beds({ night = true }).amb_birds, 0)
  T.eq(beds({ season = "winter" }).amb_birds, 0)
  T.eq(beds({ frozen = true }).amb_creek, cfg.frozenCreek)
  T.eq(beds({ wind = cfg.windFull }).amb_wind, 1)
  T.eq(beds({ rain = 1 }).amb_rain, 1)
  T.eq(beds({ rain = 1 }).amb_birds, 0)
  T.eq(beds({ fire = 0 }).amb_fire, 1)
  T.eq(beds({ fire = cfg.fireRange }).amb_fire, 0)
  T.eq(beds({ fire = nil }).amb_fire, 0)
  T.eq(beds({ hum = true }).amb_hum, 1)
end)

T.test("audio: cooldown, pause, speed and zero volume", function()
  local audio, backend, settings = newAudio()
  T.truthy(audio:play("ui_tap"))
  T.falsy(audio:play("ui_tap"), "cooldown")
  audio:update(1)
  T.truthy(audio:play("ui_tap"))
  T.eq(#backend.log, 2)
  -- A world cue is silent while time is paused, a UI cue is not.
  audio.paused = true
  T.falsy(audio:play("clear"))
  T.truthy(audio:play("toast"))
  T.truthy(audio:play("clear", { force = true }))
  -- ... and while time races past (sleep).
  audio.paused, audio.speed = false, cfg.maxEventSpeed + 1
  T.falsy(audio:play("harvest"))
  audio.speed = 1
  T.truthy(audio:play("harvest"))
  -- Volume at zero is silent.
  settings:set("volumeEffects", 0)
  T.falsy(audio:play("till"))
  -- Unknown and loop cues never play as one-shots and never raise.
  T.falsy(audio:play("no_such_cue"))
  T.falsy(audio:play("amb_rain"))
end)

T.test("audio: events on the bus play their cue", function()
  local audio, backend = newAudio()
  local world = { events = Events.new() }
  audio:attach(world, function() return calm end)
  world.events:emit("fish.caught", { fish = "trout" })
  world.events:emit("ledger.changed", {})
  T.eq(#backend.log, 1)
  audio:detach()
  audio:update(1)
  world.events:emit("fish.lost", {})
  T.eq(#backend.log, 1, "detached")
end)

T.test("audio: a missing or broken file never crashes and falls back to the placeholder", function()
  -- No files at all: the synthesized placeholder plays.
  local audio, backend = newAudio()
  T.eq(audio.library:describe("clear"), "synth")
  T.truthy(audio:play("clear"))
  T.truthy(backend.log[1].what:find("^synth:"))
  -- A file that exists but will not load is skipped.
  local bad = Backend.null()
  local realNew = bad.newSource
  bad.newSource = function(x, mode)
    if type(x) == "string" then
      error("cannot decode")
    end
    return realNew(x, mode)
  end
  local a2 = newAudio({ backend = bad, fs = { getInfo = function() return { type = "file", size = 10 } end } })
  T.eq(a2.library:describe("clear"), "synth")
  T.truthy(a2:play("clear"))
  -- A filesystem that raises is survived.
  local a3 = newAudio({ fs = { getInfo = function() error("no fs") end } })
  T.truthy(a3:play("clear"))
  -- A cue with no generator and no file is silent, not an error.
  local ghost = { buses = sounds.buses, events = {}, cues = { ghost = { bus = "sfx", volume = 1, where = "x", desc = "x" } } }
  local a4 = newAudio({ sounds = ghost })
  T.eq(a4.library:describe("ghost"), "silent")
  T.falsy(a4:play("ghost"))
end)

T.test("audio: a file dropped in the bus folder replaces the placeholder, numbered files vary", function()
  local present = {
    ["assets/audio/sfx/clear_1.ogg"] = true,
    ["assets/audio/sfx/clear_2.ogg"] = true,
    ["assets/audio/sfx/fish_caught.wav"] = true,
  }
  local fs = {
    getInfo = function(path)
      return present[path] and { type = "file", size = 100 } or nil
    end,
  }
  local audio, backend = newAudio({ fs = fs })
  T.eq(audio.library:describe("clear"), "files x2")
  T.eq(audio.library:describe("fish_caught"), "file")
  T.eq(audio.library:describe("till"), "synth")
  local seen = {}
  audio:attach({ events = Events.new() }, function() return calm end)
  for _ = 1, 40 do
    audio:update(1)
    audio:play("clear")
  end
  for _, e in ipairs(backend.log) do
    seen[e.what] = true
  end
  T.truthy(seen["assets/audio/sfx/clear_1.ogg"] and seen["assets/audio/sfx/clear_2.ogg"], "both variations are picked")
  audio:play("fish_caught")
  T.eq(backend.log[#backend.log].what, "assets/audio/sfx/fish_caught.wav")
end)

T.test("audio: beds fade in, duck when paused and never hard-stop", function()
  local audio, backend = newAudio()
  local snap = {}
  for k, v in pairs(calm) do
    snap[k] = v
  end
  audio:attach({ events = Events.new() }, function() return snap end)
  for _ = 1, 10 do
    audio:update(1)
  end
  local bed = audio.beds.amb_creek
  T.truthy(bed and bed.playing)
  local full = bed.source.volume
  T.truthy(full > 0)
  snap.speed = 0 -- paused
  for _ = 1, 10 do
    audio:update(1)
  end
  T.truthy(bed.playing, "still playing while paused")
  T.near(bed.source.volume, full * cfg.pausedDuck, 1e-6)
  snap.speed = 1
  for _ = 1, 10 do
    audio:update(1)
  end
  T.near(bed.source.volume, full, 1e-6)
  -- Night: birds fade out and stop, crickets come in.
  snap.night = true
  for _ = 1, 10 do
    audio:update(1)
  end
  T.falsy(audio.beds.amb_birds.playing)
  T.truthy(audio.beds.amb_crickets.playing)
  -- Muted while unfocused.
  audio:setFocus(false)
  for _ = 1, 3 do
    audio:update(1)
  end
  T.eq(audio.beds.amb_crickets.source.volume, 0)
  audio:setFocus(true)
  for _ = 1, 3 do
    audio:update(1)
  end
  T.truthy(audio.beds.amb_crickets.source.volume > 0)
  T.truthy(#backend.log > 0)
end)

T.test("audio: dusk and dawn play once on the change, thunder only on storm days", function()
  local audio, backend = newAudio()
  local snap = {}
  for k, v in pairs(calm) do
    snap[k] = v
  end
  audio:attach({ events = Events.new() }, function() return snap end)
  local function oneShots()
    local n = 0
    for _, e in ipairs(backend.log) do
      if not e.loop then
        n = n + 1
      end
    end
    return n
  end
  audio:update(1)
  T.eq(oneShots(), 0, "nothing on the first read")
  snap.night = true
  audio:update(1)
  T.eq(oneShots(), 1)
  audio:update(1)
  T.eq(oneShots(), 1)
  snap.kind = "storm"
  for _ = 1, 60 do
    audio:update(1)
  end
  T.truthy(oneShots() >= 2, "thunder rolled")
  local before = oneShots()
  snap.speed = 0
  for _ = 1, 100 do
    audio:update(1)
  end
  T.eq(oneShots(), before, "no thunder while paused")
end)

T.test("audio: variation is deterministic per seed and never the sim RNG", function()
  local function run()
    local audio, backend = newAudio()
    audio:attach({ events = Events.new() }, function() return calm end)
    for _ = 1, 8 do
      audio:update(1)
      audio:play("chop_wood")
    end
    local out = {}
    for _, e in ipairs(backend.log) do
      if not e.loop then
        out[#out + 1] = e.pitch
      end
    end
    return out
  end
  local a, b = run(), run()
  T.eq(#a, 8)
  for i = 1, #a do
    T.eq(a[i], b[i])
    T.truthy(math.abs(a[i] - 1) <= sounds.cues.chop_wood.pitchVar + 1e-9)
  end
  T.truthy(a[1] ~= a[2] or a[2] ~= a[3], "pitch varies")
end)

T.test("audio: volume sliders are settings that round trip", function()
  local backend = Save.memoryBackend()
  local s = Settings.new(backend, tun)
  T.eq(s:get("volumeMaster"), cfg and tun.settings.defaults.volumeMaster)
  T.truthy(s:set("volumeMaster", 0.3))
  T.truthy(s:set("volumeMusic", 0))
  T.truthy(s:set("volumeAmbience", 5), "clamped, not rejected")
  T.eq(s:get("volumeAmbience"), 1)
  T.falsy(s:set("volumeEffects", "loud"))
  T.eq(s:get("volumeMaster"), 0.3)
  s:save()
  local again = Settings.new(backend, tun)
  again:load()
  T.eq(again:get("volumeMaster"), 0.3)
  T.eq(again:get("volumeMusic"), 0)
  T.eq(again:get("volumeAmbience"), 1)
  -- The service reads the sliders live.
  local audio = Audio.new({ tuning = tun, settings = again, backend = Backend.null(), fs = { getInfo = function() end } })
  T.near(audio:busGain("sfx"), Mixer.curve(0.3, cfg.volumeCurve) * Mixer.curve(again:get("volumeEffects"), cfg.volumeCurve), 1e-9)
  T.eq(audio:busGain("music"), 0)
end)
