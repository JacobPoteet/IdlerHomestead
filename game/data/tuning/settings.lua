-- Player settings (GDD D96, #50): the defaults a fresh install starts with and the knobs the Settings
-- screen offers. Option declarations (labels, kinds, apply hooks) live in src/core/settings_options.lua.
return {
  file = "settings.lua", -- file name in the save directory; separate from the save slots
  defaults = { -- option id -> value on a fresh install (the window options match conf.lua's first-boot window)
    uiScale = "auto", -- "auto" (largest whole scale that keeps display.minVirtualWidth x Height visible) or a whole number
    fullscreen = false, -- borderless desktop fullscreen (conf.lua: fullscreen = false)
    vsync = true, -- sync to the monitor refresh (conf.lua: vsync = 1)
    rememberWindow = true, -- reopen at the last window size and position
    idleDelay = 1, -- multiplier on the idle takeover delay (idle.takeoverDelay), 1 = as designed
    reduceMotion = false, -- stills heat shimmer and wind sway
    filmGrain = true, -- film grain over the world
    gradeStrength = 1, -- 0..1 share of the colour grade (tint, saturation, vignette) applied
    ambientFx = true, -- fireflies, dust motes, mist, cloud shadows and rain streaks
    volumeMaster = 0.8, -- 0..1 slider; scales every sound (the sound is mastered quiet, so 0.8 is a comfortable start)
    volumeMusic = 0.6, -- 0..1 slider; music bus (no tracks yet)
    volumeAmbience = 0.7, -- 0..1 slider; nature beds, weather and fire crackle
    volumeEffects = 0.8, -- 0..1 slider; chores, fishing, interface and event sounds
    muteUnfocused = true, -- silence the game while its window is in the background
  },
  volume = { min = 0, max = 1, step = 0.1 }, -- slider range and step of the four volume sliders
  uiScaleMax = 4, -- largest fixed whole UI scale offered (the window can clamp it lower)
  comfortTouchPixels = 36, -- screen pixels; on a touch device a fixed scale that makes the smallest button smaller than this gets a warning
  idleDelayChoices = { 0.5, 1, 2, 4 }, -- multipliers offered for the idle takeover delay
  gradeStrength = { min = 0, max = 1, step = 0.25 }, -- slider range and step of the colour-grade strength
  minWindow = { 640, 360 }, -- pixels; smallest remembered window (matches conf.lua minwidth and minheight)
  minSegment = 44, -- virtual pixels; narrowest a choice button gets before the choices wrap onto another row
  panelWidth = 300, -- virtual pixels; widest the Settings panel gets
  panelMargin = 8, -- virtual pixels kept between the panel and the screen edge
}
