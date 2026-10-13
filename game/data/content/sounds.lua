-- The sound registry (GDD D100, #48): the single place that lists every sound the game can make.
-- Game code only ever says "play cue X"; what X sounds like is decided here and in assets/audio/.
--
-- Replacing a placeholder needs no code: drop game/assets/audio/<bus>/<cue id>.ogg (or <cue id>_1.ogg,
-- <cue id>_2.ogg ... for variations; .wav .mp3 .flac also work) and the file is used instead of the
-- synthesized placeholder. `files` below lists extra paths if a file lives elsewhere. Full steps and the
-- cue table: docs/AUDIO.md.
--
-- Cue fields:
--   bus        "sfx" | "ambience" | "music"      which volume slider it follows
--   gen, args  placeholder generator (src/audio/synth.lua) and its arguments; used when no file is found
--   files      optional extra file paths tried before the drop-in folder (a random one is picked per play)
--   volume     0..1 loudness of this cue before the bus sliders (the placeholders are mastered quiet)
--   pitch      playback pitch, 1 = as authored
--   pitchVar   random pitch spread, +/- this fraction per play (audio-local RNG, never the sim RNG)
--   cooldown   seconds; the cue is ignored again until this long after it last played
--   loop       true for beds that run continuously; their level is set by src/audio/cues.lua
--   world      true if the cue belongs to game time: it is silent while time is paused or racing
--   where      what triggers it (for the docs and the sound test screen)
--   desc       what the placeholder sounds like
local M = {}

M.buses = { "sfx", "ambience", "music" }

M.cues = {
  -- Chores and farm work ----------------------------------------------------------------------
  clear = { bus = "sfx", gen = "thud", args = { dur = 0.22, freq = 90, lp = 0.28, decay = 0.07, body = 0.6 }, volume = 0.5, pitchVar = 0.1, cooldown = 0.08, world = true, where = "A clearing job finishes (brush, rock, junk; trees and logs use chop_wood)", desc = "soft chop thud" },
  till = { bus = "sfx", gen = "thud", args = { dur = 0.2, freq = 70, lp = 0.12, decay = 0.08, body = 0.3 }, volume = 0.5, pitchVar = 0.12, cooldown = 0.08, world = true, where = "A tile is tilled or untilled", desc = "dull earthy dig" },
  plant = { bus = "sfx", gen = "thud", args = { dur = 0.12, freq = 140, lp = 0.08, decay = 0.04, body = 0.2 }, volume = 0.4, pitchVar = 0.15, cooldown = 0.08, world = true, where = "A seed is planted", desc = "tiny soft pat" },
  harvest = { bus = "sfx", gen = "blip", args = { dur = 0.13, freq = 520, freqEnd = 700, decay = 0.05, harm = 0.2 }, volume = 0.4, pitchVar = 0.12, cooldown = 0.08, world = true, where = "A crop is picked", desc = "short bright pluck" },
  water = { bus = "sfx", gen = "thud", args = { dur = 0.28, freq = 200, lp = 0.5, decay = 0.1, body = 0.15 }, volume = 0.4, pitchVar = 0.1, cooldown = 0.1, world = true, where = "A crop is watered or a bucket is filled", desc = "airy splash" },
  chop_wood = { bus = "sfx", gen = "thud", args = { dur = 0.25, freq = 120, lp = 0.35, decay = 0.06, body = 0.7 }, volume = 0.55, pitchVar = 0.08, cooldown = 0.1, world = true, where = "A tree or log is felled", desc = "woody knock" },
  place = { bus = "sfx", gen = "thud", args = { dur = 0.2, freq = 100, lp = 0.15, decay = 0.07, body = 0.5 }, volume = 0.5, pitchVar = 0.05, cooldown = 0.1, world = true, where = "An object is set down or a machine loaded", desc = "solid set-down thump" },
  stove_lit = { bus = "sfx", gen = "chime", args = { notes = { 330, 440 }, step = 0.07, ring = 0.35, decay = 0.12 }, volume = 0.35, cooldown = 0.5, world = true, where = "A campfire or wood stove is placed", desc = "two warm soft notes" },
  eat = { bus = "sfx", gen = "thud", args = { dur = 0.1, freq = 260, lp = 0.4, decay = 0.03, body = 0.1 }, volume = 0.3, pitchVar = 0.15, cooldown = 0.3, world = true, where = "The homesteader eats", desc = "small munch" },
  animal = { bus = "sfx", gen = "blip", args = { dur = 0.1, freq = 780, freqEnd = 600, decay = 0.04 }, volume = 0.3, pitchVar = 0.2, cooldown = 0.2, world = true, where = "Eggs, milk or a hen is collected", desc = "tiny peep" },
  ping = { bus = "sfx", gen = "blip", args = { dur = 0.3, freq = 880, decay = 0.1, harm = 0.1 }, volume = 0.3, cooldown = 0.3, world = true, where = "A smoker or press batch is done", desc = "soft ding" },

  -- Fishing -----------------------------------------------------------------------------------
  fish_bite = { bus = "sfx", gen = "chime", args = { notes = { 660, 880, 1320 }, step = 0.08, ring = 0.4, decay = 0.14 }, volume = 0.5, cooldown = 0.5, where = "A fish bites (the line pulls)", desc = "bright rising three-note chime" },
  fish_hooked = { bus = "sfx", gen = "thud", args = { dur = 0.18, freq = 160, lp = 0.5, decay = 0.05, body = 0.8 }, volume = 0.5, cooldown = 0.3, where = "The fishing game starts with a fish on the hook", desc = "firm tug" },
  fish_caught = { bus = "sfx", gen = "chime", args = { notes = { 523, 659, 784, 1047 }, step = 0.09, ring = 0.5, decay = 0.2 }, volume = 0.5, cooldown = 0.5, where = "A fish is landed (idle or reeled in)", desc = "happy four-note arpeggio" },
  fish_lost = { bus = "sfx", gen = "blip", args = { dur = 0.35, freq = 420, freqEnd = 220, decay = 0.15 }, volume = 0.35, cooldown = 0.5, where = "A fish gets away", desc = "falling sigh" },

  -- Interface ---------------------------------------------------------------------------------
  ui_tap = { bus = "sfx", gen = "blip", args = { dur = 0.05, freq = 700, decay = 0.02 }, volume = 0.25, pitchVar = 0.03, cooldown = 0.04, where = "Any button is pressed", desc = "tiny soft tick" },
  toast = { bus = "sfx", gen = "blip", args = { dur = 0.14, freq = 600, freqEnd = 760, decay = 0.06 }, volume = 0.25, cooldown = 0.25, where = "A toast message appears", desc = "gentle two-tone blip" },
  alert = { bus = "sfx", gen = "chime", args = { notes = { 440, 349 }, step = 0.12, ring = 0.3, decay = 0.1 }, volume = 0.4, cooldown = 2, world = true, where = "A low food, fuel, animal feed or health alert is raised", desc = "two falling notes" },
  learn = { bus = "sfx", gen = "chime", args = { notes = { 392, 523, 659 }, step = 0.1, ring = 0.45, decay = 0.16 }, volume = 0.35, cooldown = 1, world = true, where = "A journal entry or perk is learned", desc = "soft rising chime" },

  -- Town, trade, threats ----------------------------------------------------------------------
  truck_trip = { bus = "sfx", gen = "thud", args = { dur = 0.6, freq = 55, lp = 0.05, decay = 0.3, body = 1.2, noise = 0.6 }, volume = 0.5, cooldown = 1, where = "The truck leaves for or returns from town", desc = "low engine rumble" },
  delivery = { bus = "sfx", gen = "thud", args = { dur = 0.3, freq = 80, lp = 0.2, decay = 0.1, body = 0.8 }, volume = 0.55, pitchVar = 0.05, cooldown = 0.3, world = true, where = "A delivered item arrives", desc = "heavy box thud" },
  coin = { bus = "sfx", gen = "chime", args = { notes = { 1175, 1568 }, step = 0.05, ring = 0.3, decay = 0.08 }, volume = 0.3, cooldown = 0.2, world = true, where = "Something sells at the stand", desc = "bright coin tink" },
  threat_warn = { bus = "sfx", gen = "chime", args = { notes = { 294, 294, 220 }, step = 0.22, ring = 0.5, decay = 0.2 }, volume = 0.45, cooldown = 3, where = "A threat is forecast", desc = "low warning tolls" },
  threat_strike = { bus = "sfx", gen = "thud", args = { dur = 0.5, freq = 60, lp = 0.1, decay = 0.2, body = 1 }, volume = 0.55, cooldown = 1.5, where = "A threat strikes", desc = "dull heavy hit" },
  brownout = { bus = "sfx", gen = "blip", args = { dur = 0.4, freq = 220, freqEnd = 110, decay = 0.2 }, volume = 0.3, cooldown = 4, world = true, where = "The power network browns out", desc = "power-down slide" },

  -- Weather, day and night, cat ----------------------------------------------------------------
  thunder = { bus = "sfx", gen = "rumble", args = { dur = 3.2, lp = 0.05, roll = 0.9 }, volume = 0.7, pitchVar = 0.1, cooldown = 6, where = "Storm days: a roll every 18 to 55 seconds, and when a storm arrives", desc = "long low rolling rumble" },
  night_fall = { bus = "sfx", gen = "chime", args = { notes = { 392, 330 }, step = 0.25, ring = 0.8, decay = 0.35 }, volume = 0.25, cooldown = 30, where = "Dusk: it turns dark", desc = "two slow falling notes" },
  dawn = { bus = "sfx", gen = "chime", args = { notes = { 330, 392, 494 }, step = 0.22, ring = 0.8, decay = 0.35 }, volume = 0.25, cooldown = 30, where = "Dawn: it turns light", desc = "three slow rising notes" },
  sleep = { bus = "sfx", gen = "blip", args = { dur = 0.6, freq = 300, freqEnd = 200, decay = 0.3 }, volume = 0.2, cooldown = 5, where = "The homesteader lies down to sleep", desc = "soft settling sigh" },
  meow = { bus = "sfx", gen = "blip", args = { dur = 0.35, freq = 700, freqEnd = 520, decay = 0.15, harm = 0.4 }, volume = 0.3, cooldown = 2, world = true, where = "A cat settles in", desc = "small mew" },
  purr = { bus = "sfx", gen = "purr", args = { dur = 2.4, rate = 22, freq = 55 }, volume = 0.5, cooldown = 2.5, world = true, loop = false, where = "The cat is petted", desc = "tiny low purr" },

  -- Ambience beds (levels set by src/audio/cues.lua from the weather, time of day and season) ------
  amb_birds = { bus = "ambience", gen = "chirps", args = { dur = 8, count = 9, freq = 2400, span = 900 }, volume = 0.35, loop = true, where = "Daytime in spring, summer, autumn (not in rain)", desc = "scattered bird chirps" },
  amb_creek = { bus = "ambience", gen = "noise_loop", args = { dur = 6, lp = 0.35, hp = 0.02, mod = 0.4, modRate = 0.8 }, volume = 0.3, loop = true, where = "Always; faint while the creek is frozen", desc = "soft burbling water" },
  amb_wind = { bus = "ambience", gen = "noise_loop", args = { dur = 8, lp = 0.08, mod = 0.6, modRate = 0.25 }, volume = 0.45, loop = true, where = "Windy and storm days (follows Weather.windStrength)", desc = "low breathy gusts" },
  amb_crickets = { bus = "ambience", gen = "crickets", args = { dur = 4, freq = 4200, pulseRate = 28, groupRate = 1.6 }, volume = 0.18, loop = true, where = "Night in spring, summer, autumn (not in rain)", desc = "high chirring pulses" },
  amb_rain = { bus = "ambience", gen = "noise_loop", args = { dur = 6, lp = 0.6, hp = 0.05, mod = 0.15, modRate = 0.3 }, volume = 0.5, loop = true, where = "Rain and storm days, eased like the visual rain", desc = "steady soft hiss" },
  amb_fire = { bus = "ambience", gen = "crackle", args = { dur = 5, density = 14, lp = 0.6 }, volume = 0.4, loop = true, where = "Near a lit campfire or wood stove, louder the closer the view", desc = "quiet crackle with pops" },
  amb_hum = { bus = "ambience", gen = "hum", args = { dur = 2, freq = 60, harmonics = { 1, 0.5, 0.25 } }, volume = 0.12, loop = true, where = "While a powered machine runs off the inverter", desc = "low 60 Hz hum" },
}

-- Event -> cue (src/audio/cues.lua). A string plays that cue. A table picks one by a field of the event
-- payload: { field = "task", map = { clear = "clear" }, default = "cueIfNoMatch" }.
M.events = {
  ["task.completed"] = { field = "task", map = { till = "till", untill = "till", plant = "plant", harvest = "harvest", water_crop = "water", fetch_water = "water", load_station = "place" } },
  ["object.cleared"] = { field = "object", map = { tree = "chop_wood", log = "chop_wood" }, default = "clear" },
  ["object.placed"] = { field = "object", map = { campfire = "stove_lit", wood_stove = "stove_lit" }, default = "place" },
  ["fishing.ready"] = "fish_bite",
  ["fish.caught"] = "fish_caught",
  ["fish.lost"] = "fish_lost",
  ["market.trip"] = "truck_trip",
  ["market.delivered"] = "delivery",
  ["stand.sold"] = "coin",
  ["processing.done"] = "ping",
  ["animals.collected"] = "animal",
  ["animals.milked"] = "animal",
  ["needs.ate"] = "eat",
  ["alert.raised"] = "alert",
  ["journal.learned"] = "learn",
  ["threat.warned"] = "threat_warn",
  ["threat.struck"] = "threat_strike",
  ["power.brownout"] = "brownout",
  ["cat.petted"] = "purr",
  ["cat.arrived"] = "meow",
  ["sleep.started"] = "sleep",
  ["weather.changed"] = { field = "kind", map = { storm = "thunder" } },
}

return M
