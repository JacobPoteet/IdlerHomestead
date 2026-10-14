-- Audio (GDD D100, #48). Presentation only: the audio service reads the sim through events and accessors.
-- Per-cue loudness, pitch and cooldown live with the cue in data/content/sounds.lua; these are the global knobs.
return {
  rate = 22050, -- Hz; sample rate of the synthesized placeholder sounds
  seed = 1701, -- seed of the audio-local RNG (pitch and file variation, thunder timing); never the sim RNG
  volumeCurve = 2, -- exponent applied to a 0..1 volume slider (1 = linear; 2 gives finer control near quiet)
  musicGain = 1, -- 0..1; extra gain on the music bus on top of the slider (music is silent until tracks exist)
  maxVoices = 24, -- one-shots playing at once; further ones are dropped
  maxVariants = 8, -- how many numbered files (<cue>_1 .. <cue>_N) the library looks for per cue
  streamBytes = 1048576, -- bytes; a file at least this big is streamed instead of loaded whole (loops and music)
  extensions = { "ogg", "wav", "mp3", "flac" }, -- file types looked for in assets/audio/<bus>/, in this order
  dir = "assets/audio", -- folder (inside game/) holding drop-in replacement sounds, one subfolder per bus
  sampleSeconds = 0.25, -- seconds between reads of the world for the ambience beds (the fades still run every frame)
  bedFadeSeconds = 2.5, -- seconds; ambience beds ease to a new level over this long
  pausedDuck = 0.35, -- 0..1; ambience level while game time is paused (player pause, tip card, town); it never hard-stops
  duckSeconds = 0.6, -- seconds; how fast ambience eases to or from the paused level
  muteFadeSeconds = 0.4, -- seconds; fade when the window loses or regains focus (Mute when unfocused)
  maxEventSpeed = 4, -- game speed multiplier above which world one-shots stop (sleep would be a din)
  minBedLevel = 0.01, -- 0..1; a bed below this and heading for silence is stopped to free its voice
  birdSeasons = { spring = 1, summer = 1, autumn = 0.4, winter = 0 }, -- season -> 0..1 level of the daytime bird bed
  cricketSeasons = { spring = 0.6, summer = 1, autumn = 0.5, winter = 0 }, -- season -> 0..1 level of the night cricket bed
  windFloor = 1, -- Weather.windStrength at or below which the wind bed is silent (1 = ordinary day)
  windFull = 1.7, -- Weather.windStrength at which the wind bed is full (a storm)
  frozenCreek = 0.15, -- 0..1; creek bed level while the creek is frozen
  rainQuiet = 0.3, -- 0..1; rain level above which birds and crickets stop
  fireRange = 10, -- tiles from the view centre within which a lit campfire or stove is heard
  thunderGap = { 18, 55 }, -- seconds (min, max) between thunder rolls on a storm day
  previewCue = "ui_tap", -- cue played when a volume slider changes, so the new level can be heard
}
