-- Look & feel: shader parameters and lighting. Reloaded live with F6.
-- Colors are { r, g, b } in 0..1.
return {
  -- Water shader (shaders/water.glsl)
  waterShallow = { 0.30, 0.58, 0.62 }, -- color near the banks
  waterDeep = { 0.13, 0.32, 0.45 }, -- color in the middle of the creek
  waterFoam = { 0.84, 0.92, 0.88 }, -- foam line along the banks
  waterHighlight = { 0.78, 0.92, 0.95 }, -- ripple sparkle color
  waterFlowSpeed = 6, -- pixels per second the ripples drift downstream
  waterRippleScale = 0.09, -- ripple noise frequency (higher = smaller ripples)
  waterSparkle = 0.55, -- 0..1 strength of ripple highlights in daylight
  waterFoamWidth = 0.09, -- depth units of foam past the bank line (~0.03 per art pixel)
  iceColor = { 0.78, 0.88, 0.92 }, -- frozen creek, near the banks
  iceDeepColor = { 0.52, 0.66, 0.76 }, -- frozen creek, mid-channel and cracks
  iceHoleColor = { 0.08, 0.16, 0.24 }, -- open water showing through a cut ice hole
  -- Snow, frost and wet ground (shaders/ground.glsl, snowcap.glsl)
  snowColor = { 0.93, 0.95, 0.98 }, -- fresh snow
  snowShade = { 0.72, 0.80, 0.90 }, -- clump edges
  snowClumpScale = 0.18, -- snow clump noise frequency, 1/ground pixels (higher = smaller patches; world-anchored)
  snowPatchScale = 0.035, -- broad snow drift noise frequency, 1/ground pixels (0.035 = drifts about 2 tiles across)
  snowRampDays = 1.5, -- in-game days for snow to cover the ground once the freeze starts
  snowMeltDays = 2, -- in-game days for snow to melt after the thaw
  snowCapDepth = 3, -- art pixels of snow resting on the top of objects at full snow (1..4; shaders/snowcap.glsl)
  frostReach = 3, -- art pixels the frost creeps in from the creek bank when the creek is frozen over (1..4)
  frostColor = { 0.86, 0.94, 1.00 }, -- frost crust along the bank over bare ground
  frostSnowColor = { 0.58, 0.77, 0.94 }, -- frost crust over snow: a deeper ice blue than the snow, so it reads on white (#218)
  frostSparkle = 0.18, -- 0..1 share of the frost pixels over snow that glint white (static, picked per ground pixel)
  frostSparkleColor = { 1.00, 1.00, 1.00 }, -- the glint pixel
  iceRampDays = 0.5, -- in-game days for the creek to freeze over / break up
  -- Screen grading (shaders/grade.glsl)
  lightKeysSunrise = 6, -- sunrise hour the lightKeys are authored for; stretched to the season's sunrise
  lightKeysSunset = 20, -- sunset hour the lightKeys are authored for; stretched to the season's sunset
  lightKeys = { -- day/night lighting keyframes: hour (0-24), tint multiplier, light level 0..1
    { hour = 0, tint = { 0.52, 0.58, 0.88 }, light = 0.56 },
    { hour = 5, tint = { 0.56, 0.60, 0.88 }, light = 0.60 },
    { hour = 6.5, tint = { 1.00, 0.78, 0.62 }, light = 0.85 },
    { hour = 9, tint = { 1.00, 0.98, 0.94 }, light = 1.00 },
    { hour = 16, tint = { 1.00, 0.97, 0.90 }, light = 1.00 },
    { hour = 18.5, tint = { 1.00, 0.70, 0.52 }, light = 0.85 },
    { hour = 20.5, tint = { 0.58, 0.60, 0.88 }, light = 0.62 },
    { hour = 24, tint = { 0.52, 0.58, 0.88 }, light = 0.56 },
  },
  saturation = 0.92, -- 1 = unchanged; lower is more muted
  tone = { -- split toning and contrast in the colour grade (D128); gradeStrength scales all of it toward neutral
    shadowTone = { 0.93, 0.98, 1.07 }, -- colour multiplier for dark pixels (cool)
    highlightTone = { 1.06, 1.01, 0.93 }, -- colour multiplier for bright pixels (warm)
    mid = 0.42, -- luma (0..1) where the tone swings from the shadow to the highlight colour
    width = 0.32, -- luma span either side of `mid` over which it swings
    contrast = 0.22, -- 0..1 strength of the S-curve (0 = none)
    blackLift = { 0.010, 0.014, 0.026 }, -- light added to the darkest pixels, so black reads as deep blue instead of mud
  },
  seasonGrade = { -- season id -> { tint multiplier, saturation multiplier } on top of the day/night grade
    spring = { tint = { 1.00, 1.00, 1.00 }, saturation = 1.00 },
    summer = { tint = { 1.02, 1.00, 0.96 }, saturation = 1.05 },
    autumn = { tint = { 1.04, 0.98, 0.90 }, saturation = 0.95 },
    winter = { tint = { 0.94, 0.98, 1.06 }, saturation = 0.78 },
  },
  actionRing = { -- progress ring over the target tile while the homesteader works (D44); sizes in virtual UI pixels, so it is the same size at every zoom
    radius = 9, -- outer radius; a ~20 px circle stays readable at 640x360 and on a phone
    thickness = 3, -- ring width
    minSeconds = 0.5, -- hide actions with less work than this (game seconds at 1x); they'd only flicker
    backColor = { 0.06, 0.07, 0.06, 0.75 }, -- disc behind the ring so it reads on any ground
    trackColor = { 0.93, 0.91, 0.84, 0.35 }, -- the unfilled part of the ring
    orderedColor = { 0.89, 0.71, 0.36, 1 }, -- fill for actions the player ordered (matches the UI accent)
    routineColor = { 0.62, 0.80, 0.84, 1 }, -- fill for actions the idle routine chose
    machineColor = { 0.86, 0.66, 0.20, 1 }, -- fill for a machine's work (D65), the machines' yellow
    segments = 28, -- polygon segments in a full circle
  },
  powerLamp = { -- status light on powered devices and generators (GDD §7.5)
    size = 3, -- pixels along one edge, in world art pixels
    ok = { 0.45, 0.90, 0.42 }, -- running at full power
    short = { 0.95, 0.35, 0.30 }, -- served less than it wants
    idle = { 0.85, 0.75, 0.35 }, -- on but nothing to do right now
    off = { 0.35, 0.37, 0.36 }, -- switched off
  },
  waterLamp = { -- status light on drip lines (GDD §5.3); same size as powerLamp
    ok = { 0.45, 0.75, 0.95 }, -- cistern has water to give
    dry = { 0.95, 0.35, 0.30 }, -- cistern empty: the zone is dry and crops must be hand-watered
    frozen = { 0.35, 0.37, 0.36 }, -- ground frozen: nothing to water
  },
  waterGauge = { -- fill gauge drawn over a cistern
    width = 12, -- pixels, in world art pixels
    height = 2, -- pixels
    back = { 0, 0, 0, 0.6 }, -- behind the bar
    fill = { 0.45, 0.75, 0.95 }, -- water level
    low = { 0.95, 0.35, 0.30 }, -- level below tuning.water.lowFraction
  },
  waterZone = { -- tint over the tiles a drip line covers (shown when it is selected or being placed)
    ok = { 0.35, 0.62, 0.80, 0.30 },
    dry = { 0.95, 0.40, 0.30, 0.30 },
  },
  waterSpots = { 0.35, 0.62, 0.80, 0.28 }, -- tint over tiles where a well or pump can be sunk, while placing one
  frostPlan = { 0.95, 0.55, 0.15, 0.40 }, -- amber tint over a planned tile whose crop cannot ripen before winter (D70, #165)
  cropCues = { -- crop and plan readability (#20, D102; src/render/crop_cues.lua); icons are drawn over the graded world so they hold at night
    iconAlpha = 0.95, -- 0..1 opacity of the thirsty droplet and the ready sparkle at full strength
    nightIconDim = 0.15, -- 0..1 how much the icons fade at full darkness (they stay bright enough to read, but do not glare)
    dropletGap = 0, -- art pixels the droplet floats above the top of its tile (negative sinks it into the tile)
    sparkleSeconds = 1.8, -- seconds for one sparkle cycle (UI cue, real-time clock like the selection ring, D97)
    sparkleDuty = 0.35, -- 0..1 share of the cycle the sparkle twinkles; the rest of the time it rests as the small plus
    sparkleRest = 0.7, -- 0..1 opacity of the resting plus (the ripe cue is always visible, also under reduce motion)
    sparkleSpread = 8, -- number of staggered phases, so a whole field does not twinkle in step
    planGhostAlpha = 0.5, -- 0..1 opacity of the faint sprout drawn on a planned tile (a plant it is not yet)
    nightLift = 0.4, -- 0..1 extra brightness added to crop sprites at full darkness, so a graded sprout keeps contrast against the dark soil
  },
  rangePreview = { -- placement range preview (#268, D108): the ranges of placed items of the same kind, and where they overlap the one being placed
    others = { 0.75, 0.80, 0.85, 0.10 }, -- dimmed tint over a placed item's range (rgba)
    othersEdge = { 0.75, 0.80, 0.85, 0.45 }, -- outline of each placed item's range (rgba), so touching ranges stay distinct
    overlap = { 1.00, 0.30, 0.25, 0.45 }, -- tint over tiles that two ranges both cover (rgba); strong enough to read over the other tints
  },
  replacePreview = { -- planning over growing crops (D110, #257): tiles whose crop the plan would pull
    fill = { 0.90, 0.20, 0.15, 0.40 }, -- red tint over a tile that will be replaced (rgba)
    edge = { 1.00, 0.85, 0.80, 0.90 }, -- the X drawn on it (rgba), readable over the tint on any soil
  },
  shelter = { -- shelter ladder (D82)
    zone = { 1.00, 0.62, 0.22, 0.20 }, -- warm tint over the heater slot of a shelter (selected, being placed, or while placing a heat source)
  },
  machine = { -- machines (D65): status light, reach zone and the picking arm
    lamp = { -- status light colours by Machines status (same size as powerLamp)
      working = { 0.45, 0.90, 0.42 }, -- working at full power
      starting = { 0.45, 0.90, 0.42 }, -- asked for power this tick (shown as working)
      slow = { 0.95, 0.75, 0.30 }, -- partly powered: working slowly
      unpowered = { 0.95, 0.35, 0.30 }, -- has work but not enough power
      full = { 0.95, 0.55, 0.85 }, -- work held back by a full store
      idle = { 0.85, 0.75, 0.35 }, -- nothing ripe in reach
      off = { 0.35, 0.37, 0.36 }, -- switched off
    },
    zone = { 0.95, 0.80, 0.30, 0.22 }, -- tint over the tiles a machine reaches (selected or being placed)
    zoneUnpowered = { 0.95, 0.40, 0.30, 0.25 }, -- the same while it is unpowered
    arm = { 0.80, 0.82, 0.84, 0.9 }, -- line from the machine's arm to the tile it is working
    armWidth = 1, -- world art pixels
    grip = { 13, 9 }, -- pixel (x, y) on the 16x24 placeholder sprite where the arm leaves the machine
    armWobble = 1.5, -- world art pixels the arm's tip bobs while working
    armWobbleSpeed = 6, -- radians per second of the bob
  },
  weather = { -- day-to-day weather look (D51, D83); wind sway is in `wind` below (D84)
    blendSeconds = 3, -- real seconds for the look to ease into a new day's weather
    looks = { -- weather kind -> { tint multiplier on the grade, light multiplier, rain 0..1 streak density }
      clear = { tint = { 1.00, 1.00, 1.00 }, light = 1.00, rain = 0 },
      cloudy = { tint = { 0.90, 0.94, 1.00 }, light = 0.86, rain = 0 },
      rain = { tint = { 0.80, 0.88, 1.00 }, light = 0.76, rain = 0.7 },
      windy = { tint = { 0.95, 0.97, 1.00 }, light = 0.94, rain = 0 },
      storm = { tint = { 0.68, 0.76, 0.94 }, light = 0.62, rain = 1 },
    },
    wet = { -- land soaked by rain (shaders/ground.glsl, object tint); eases in with the rain and dries out slowly, on the effect clock (game time, D97/D124)
      riseSeconds = 6, -- effect-clock seconds for the land to soak through once the rain starts (1x game speed = real seconds; paused = frozen; 2x and 4x run at the 2x cap)
      drySeconds = 45, -- effect-clock seconds for it to dry out after the rain stops
      objectTint = { 0.80, 0.85, 0.93 }, -- rgb multiplier on objects, crops and tilled soil when fully wet: darker and cooler (1 = unchanged)
      fullRain = 0.7, -- rain intensity (looks.rain) at which the ground is fully wet
      darken = 0.72, -- brightness left on fully wet ground (1 = unchanged)
      saturation = 1.15, -- saturation on fully wet ground (above 1 = richer)
      puddleCover = 0.16, -- 0..1 share of the ground under a puddle when fully wet
      puddleOpacity = 0.5, -- 0..1 how much of the sky shows in a puddle (the wet ground shows through the rest)
      puddleScale = 0.1, -- puddle noise frequency, 1/ground pixels (0.1 = puddles about a tile across)
      puddleColor = { 0.46, 0.60, 0.72 }, -- the sky in a puddle
      puddleGlint = { 0.80, 0.90, 0.98 }, -- bright pixel along a puddle's upper edge
    },
    waterRain = { -- rain rings on the creek (shaders/water.glsl; #98)
      cell = 10, -- art pixels per ring cell: one ring at a time per cell
      seconds = 0.7, -- seconds a ring takes to spread and fade
      radius = 3, -- art pixels, widest ring radius (flat: half as tall)
      density = 0.6, -- 0..1 chance a cell gets a ring each cycle at full rain
      alpha = 0.7, -- 0..1 ring strength when it lands, fading to 0
    },
    clouds = { -- cloud shadows drifting over the land (shaders/clouds.glsl); world-anchored, subtle. Cover comes from the weather kind's `cloud` (tuning.weather.kinds, the same number that dims solar power)
      base = 0.2, -- 0..1 cover under an open sky, so even a clear day has a few passing shadows
      gain = 1.0, -- cover added per unit of the kind's cloud (0.8 on a storm makes it 1.0)
      scale = 0.012, -- noise frequency, 1/art pixels (0.012 = clouds about 80 art pixels across, five tiles)
      block = 2, -- art pixels per shadow pixel, so the edges stay chunky pixel art
      strength = 0.30, -- 0..1 alpha of the darkest shadow band at full daylight
      color = { 0.10, 0.14, 0.26 }, -- shadow tint (cool, not black)
      speed = 5, -- art pixels per second the shadows drift at wind strength 1
      direction = { 1.0, 0.35 }, -- drift direction (x east, y south); normalised in code
      windBlendSeconds = 4, -- real seconds for the drift speed to ease toward a new day's wind
    },
    rain = { -- falling streaks and splash rings, drawn over the graded world in WORLD art pixels (#193):
      -- every size, speed and count below is in art pixels, scaled by the camera zoom on screen, so
      -- rain looks the same at every zoom, window size and widget mode and snaps to the art grid
      drops = 260, -- streaks on screen at full intensity per referenceArea
      referenceArea = 57600, -- art pixels^2 the drops count is for (320x180, the default zoom on a 640x360 view)
      length = 5, -- art pixels, average streak length
      slant = 0.25, -- art pixels each streak leans sideways per art pixel fallen (wind direction)
      speed = 130, -- art pixels per second, average fall speed
      color = { 0.78, 0.88, 1.00, 0.7 }, -- r, g, b, alpha at full intensity
      splashCellW = 24, -- art pixels wide of one splash cell: each cell lands at most one ring per cycle, placed in world space
      splashCellH = 16, -- art pixels tall of one splash cell
      splashChance = 0.25, -- 0..1 chance a cell lands a ring each cycle at full intensity (about 36 rings per 320x180 view)
      splashSeconds = 0.6, -- seconds a ring takes to spread and fade
      splashRadius = 3, -- art pixels, widest ring radius (rings are flat: half as tall as wide)
      splashAlpha = 0.55, -- 0..1 ring alpha when it first lands, fading to 0 as it spreads
    },
  },
  wind = { -- wind sway of crops, brush and tree canopies (shaders/sway.glsl, D84); the strength is Weather.windStrength, eased
    amplitude = 2.4, -- art pixels the top of a sprite leans at wind strength 1 (offsets snap to whole art pixels, so the sway steps like pixel art)
    speed = 0.75, -- radians per second of the sway at wind strength 1 (faster in a gale); slow, since 4x play shows effects at 2x and a quick sway reads as scan lines
    lean = 0.4, -- 0..1 how much of the sway is a steady lean downwind (the rest is the back-and-forth)
    gust = 0.35, -- 0..1 extra, slower swell on top of the sway, travelling across the land
    spread = 0.11, -- radians of sway phase per tile across the map, so a gust rolls over the field instead of every plant moving together
    jitter = 1.0, -- 0..1 of a full sway cycle of random phase per tile, so each plant sways on its own beat and the field does not move as one band
    crop = { weight = 1.0, root = 0.2 }, -- crops: weight = multiplier on the amplitude, root = 0..1 share of the sprite height (from the bottom) that stays still
    thirsty = { 0.86, 0.80, 0.58 }, -- colour multiplier on a crop that needs water (same as the unswayed draw)
  },
  mist = { -- morning mist over the creek and low ground (shaders/mist.glsl, D84); world-anchored, drifting
    preHours = 1.0, -- in-game hours before sunrise that it starts to form
    holdHours = 0.8, -- hours after sunrise it stays at full strength
    fadeHours = 2.5, -- hours it then takes to burn off by mid-morning
    dryLevel = 0.75, -- 0..1 strength on an ordinary dry morning (a wet morning after rain is 1)
    calmUntil = 1.0, -- wind strength up to which the air is calm enough for mist
    windKill = 1.5, -- wind strength at which the mist is gone (it thins out between calmUntil and here)
    frozen = 0.5, -- 0..1 multiplier while the creek is frozen over (cold air holds less)
    reach = 7, -- tiles from the creek bank that the mist spreads over land
    ground = 0.2, -- 0..1 mist left over the low open ground far from the creek, at full strength
    scale = 0.022, -- noise frequency, 1/art pixels (0.022 = banks of mist about 45 art pixels across)
    block = 2, -- art pixels per mist pixel, so the edges stay chunky pixel art
    levels = 4, -- number of visible density bands
    alpha = 0.75, -- 0..1 alpha of the thickest band at full strength
    color = { 0.86, 0.91, 0.96 }, -- mist colour (graded afterwards, so it warms at dawn)
    drift = 2.5, -- art pixels per second the banks drift downwind at wind strength 1
    direction = { 1.0, 0.25 }, -- drift direction (x east, y south)
  },
  shadows = { -- sun shadows (shaders/shadow.glsl): each sprite's silhouette is flipped onto the ground and sheared away from the sun, plus a small contact shadow underneath
    enabled = true,
    color = { 0.06, 0.08, 0.20 }, -- shadow tint (cool, not black); the grade tints it afterwards
    castStrength = 0.42, -- 0..1 alpha of cast shadows at full sun
    contactStrength = 0.30, -- 0..1 alpha of the contact shadow under a sprite; it stays at night and in cloud
    maxShear = 1.1, -- sideways art pixels of shadow per art pixel of height at sunrise/sunset (west at dawn, east at dusk)
    lengthNoon = 0.28, -- vertical squash of the cast shadow at noon (1 = as long as the sprite is tall)
    lengthLow = 1.0, -- the same at sunrise and sunset
    fadeElevation = 0.2, -- 0..1 sun height (0 horizon, 1 noon) below which cast shadows fade out
    cloudDim = 0.7, -- 0..1 share of the cast shadow lost under full cloud cover (an overcast sky has none)
    minHeight = 7, -- art pixels: sprites shorter than this cast no shadow
    contactMaxWidth = 26, -- art pixels, the widest contact shadow
    contactWidth = 0.8, -- share of the sprite's width the contact shadow spans
    dither = { -- shadows drawn as an ordered-dither stipple on the world art-pixel grid instead of a flat translucent tone (shaders/shadow_composite.glsl)
      amount = 1.0, -- 0..1 how much of the shadow is stippled (0 = the old flat tone, 1 = all stipple)
      alpha = 0.6, -- 0..1 alpha of one shadow pixel in the stipple; the share of pixels that are shadow is strength / this (so 0.42 / 0.6 = 70% in full sun)
    },
    dapple = { -- leaf dapple: sun flecks through a tree canopy's cast shadow (shaders/shadow_composite.glsl); trees opt in with `dapple` in data/content/objects.lua
      strength = 0.9, -- 0..1 share of the shadow a fleck's bright heart takes away (0 = no dapple)
      shade = 1.5, -- multiplier on a canopy's cast shadow between the flecks (leaves shade deeper than a post or a wall)
      cover = 0.34, -- 0..1 share of a canopy's shadow that is fleck (its half-lit rim included)
      scale = 0.32, -- fleck noise frequency, 1/art pixels (0.32 = flecks about 3 art pixels across)
      sway = 1.6, -- art pixels the flecks shuffle at wind strength 1 (whole pixels, on the sway clock)
      calmSway = 0.35, -- 0..1 share of that shuffle left on a still day (the leaves never stop quite)
    },
  },
  reflections = { -- the creek mirrors what stands on its bank (shaders/water.glsl, D130)
    enabled = true,
    opacity = 0.55, -- 0..1 how much of a reflection shows at the bank (it fades toward deep water and with ice)
    distort = 1.6, -- art pixels the ripples shove the reflection sideways at most
    tint = { 0.72, 0.84, 1.00 }, -- colour multiplier on the mirrored picture: darker and bluer than the real thing
    squash = 0.85, -- vertical scale of the mirror image (1 = as tall as the object)
    skyColor = { 0.62, 0.78, 0.92 }, -- what open water mirrors of the sky (graded afterwards, so it warms at dawn and dusk)
    skyAmount = 0.30, -- 0..1 how much sky colour the water takes on in full daylight
    reach = 1, -- tiles below an object's feet that may be water for it to cast a reflection
  },
  sunbeams = { -- slanted shafts of warm light at low sun (shaders/sunbeams.glsl, D131); world-anchored, subtle
    enabled = true,
    strength = 0.34, -- 0..1 brightness of the brightest band, added over the graded frame at the lowest sun
    lowSun = 0.75, -- 0..1 sun height (0 horizon, 1 noon) at and above which there are no shafts
    horizon = 0.12, -- 0..1 sun height below which the shafts fade out with the light
    cloudKill = 0.85, -- 0..1 share of the shafts lost under full cloud cover (they need a clear sky)
    mistBoost = 0.5, -- extra strength (a share of `strength`) while morning mist hangs in the air
    scale = 0.035, -- stripe frequency across the shafts, 1/art pixels (0.035 = shafts about 30 art pixels apart)
    patch = 0.006, -- frequency of the broad patches that break the shafts up, 1/art pixels
    block = 2, -- art pixels per beam pixel, so the edges stay chunky pixel art
    color = { 1.00, 0.80, 0.52 }, -- warm light (graded afterwards)
  },
  sparkle = { -- single pixels of snow and puddle that flash in the sun (shaders/ground.glsl, D131)
    density = 0.006, -- 0..1 share of the snow pixels flashing at once in full sun (puddles get twice that)
    steps = 3, -- times a second the flashing pixels move on
    cloudKill = 0.8, -- 0..1 share of the sparkle lost under full cloud cover
  },
  rim = { -- warm rim light on the sun side of sprites on golden afternoons (shaders/rim.glsl and sway.glsl, #283)
    enabled = true,
    seasons = { spring = 0, summer = 0, autumn = 1, winter = 0 }, -- season id -> 0..1 how much rim light it has (autumn's low golden sun)
    strength = 0.36, -- 0..1 brightness added on a rim pixel at the lowest sun of a clear autumn day
    color = { 1.00, 0.70, 0.36 }, -- warm light (graded afterwards)
    noonShare = 0.35, -- 0..1 share of the rim left at noon (it grows as the sun sinks)
    horizon = 0.12, -- 0..1 sun height below which the rim fades out with the light
    cloudKill = 0.9, -- 0..1 share of the rim lost under full cloud cover (it needs direct sun)
    top = 0.7, -- 0..1 how much the top edges catch (the sun is up-screen, the way the shadows fall)
    sideGain = 1.6, -- how fast the sunward side's share grows as the sun moves off noon (1 at side 1/sideGain)
    inkLuma = 0.16, -- brightness below which a pixel is outline: the rim sits just inside it and the outline stays dark
  },
  depthOfField = { -- optional softening of the top and bottom of the view (shaders/grade.glsl, #283); the player turns it on in Settings > Visuals
    strength = 0.85, -- 0..1 how much of the softened picture shows at the very edge
    clear = 0.5, -- 0..1 share of the half-height, out from the middle of the view, that stays sharp
    steps = 3, -- steps the softening takes toward the edge (whole art pixels: 1 then 2 pixels of spread)
  },
  bloom = { -- glow round bright pixels (shaders/bloom_*.glsl, D129): lamps, fires, lit windows, snow in the sun
    enabled = true,
    threshold = 0.66, -- 0..1 brightness (of the brightest channel) where glow starts
    knee = 0.22, -- 0..1 softness of that start
    strength = 0.18, -- 0..1 how much glow is added back in full daylight
    nightBoost = 5.5, -- extra strength at full darkness, as a multiple of `strength` (the glow matters most at night)
    wide = 0.7, -- 0..1 share of the glow that comes from the wide, soft layer (the rest is the tight halo)
    tightDivisor = 4, -- the tight layer is rendered at 1/this of the screen size
    wideDivisor = 10, -- the wide layer is rendered at 1/this of the screen size
  },
  lights = { -- night lights over the graded world (shaders/light.glsl, D84); which objects glow is the `light` field in data/content/objects.lua
    fadeStart = 0.7, -- daylight level (0 night .. 1 day) below which the lights begin to come on
    fadeEnd = 0.25, -- daylight level at which they are at full strength
    intensity = 1.0, -- 0..1 brightness at the centre of a light at full darkness, in the light buffer
    gain = 1.15, -- how strongly the light brightens and warms the picture it reaches (multiplies the lit pixels, D128)
    glow = 0.16, -- how much of the light is also added flat, so a lamp core stays bright and dark ground still shows it
    neutral = 0.6, -- 0..1 how far a lit colour is pulled toward grey before the light tints it, so firelight on grass reads warm, not olive
    bands = 5, -- number of pixel-art brightness steps in the falloff (the dither interleaves them, so fewer steps still fade smoothly)
    falloff = 1.8, -- exponent of the falloff (higher = tighter, brighter core)
    dither = 1.0, -- 0..1 how much of the Bayer 8x8 dither pattern is used between bands, on the world art-pixel grid (1 = full, no ring reads as a hard edge; 0 = plain bands)
    flickerSpeed = 7, -- flicker steps per second (the glow radius jumps in whole art pixels)
    coreSize = 3, -- art pixels, the bright core drawn at the centre of a light that has no window (flame, bulb)
    coreGlow = 0.4, -- 0..1 brightness of that core at full darkness
    windowGlow = 0.85, -- 0..1 brightness of lit window and stove-door pixels at full darkness
    margin = 4, -- tiles past the screen edge whose lights still count (at least the biggest radius in tiles)
    heatNeedMin = 0.01, -- a heat source glows when the night's warmth need is at least this (warmth units; it burns fuel for it)
  },
  selection = { -- outline round the selected object or tile (drawn on the art-pixel grid, over the graded world, so it reads at every zoom and at night; D85)
    color = { 0.89, 0.71, 0.36 }, -- ring colour (the UI accent)
    cornerColor = { 1.00, 0.93, 0.70 }, -- brighter corner brackets, so the footprint reads at a glance
    shadow = { 0.04, 0.05, 0.05, 0.6 }, -- dark ring just outside, so the outline reads on snow and bright ground (r, g, b, alpha)
    thickness = 1, -- art pixels, the ring is at least this thick
    minScreen = 3, -- physical screen pixels, the ring is never thinner than this (so it stays readable when zoomed out on a phone)
    cornerLength = 3, -- art pixels along each edge that the corner brackets run
    pulseSeconds = 1.6, -- seconds for one slow breath of the ring's alpha
    pulseDepth = 0.25, -- 0..1 how far the ring's alpha dips at the bottom of the breath
  },
  fireflies = { -- warm-evening fireflies, drawn additively over the graded world in world cells (src/render/ambient.lua; D85)
    seasons = { spring = 0.35, summer = 1.0, autumn = 0.3, winter = 0 }, -- season -> 0..1 how many are out
    inStart = -0.3, -- hours relative to sunset at which the first appear
    inEnd = 0.5, -- hours relative to sunset at which they are all out
    outStart = 3.0, -- hours after sunset at which they start to fade away
    outEnd = 4.5, -- hours after sunset at which they are gone
    calmUntil = 1.0, -- wind strength up to which they fly freely
    windKill = 1.6, -- wind strength at which none are out
    cell = 40, -- art pixels per world cell (each holds up to `perCell` flies)
    perCell = 2, -- most flies per cell, where the odds below allow
    nearCreek = 1.0, -- 0..1 odds that a fly is out on grass right beside the creek
    farGrass = 0.25, -- 0..1 odds on grass far from the creek
    reach = 9, -- tiles from the creek over which the odds fall from nearCreek to farGrass
    wander = 6, -- art pixels each way a fly drifts from its spot
    wanderSpeed = 0.5, -- radians per second of the drift
    pulseSeconds = 2.6, -- seconds for one glow (each fly is a little faster or slower)
    color = { 1.00, 0.90, 0.35 }, -- glow colour (added to the picture)
    glow = 0.9, -- 0..1 brightness of the centre pixel at the top of the glow
    halo = 0.35, -- 0..1 brightness of the four pixels round it, as a share of the centre
  },
  dust = { -- dust motes in dry daylight, drifting with the wind (src/render/ambient.lua; D85)
    seasons = { spring = 0.6, summer = 1.0, autumn = 0.9, winter = 0.25 }, -- season -> 0..1 how dusty the air is
    daylightFrom = 0.6, -- daylight level (0 night .. 1 day) at which the motes start to show
    daylightFull = 0.9, -- daylight level at which they show fully
    calm = 0.25, -- 0..1 share of the motes that float on a still dry day (the rest need wind)
    windMin = 0.9, -- wind strength above which more motes are raised
    windFull = 1.6, -- wind strength at which the air is full of them
    cell = 64, -- art pixels per world cell (a power of two, so the wrapped drift stays exact)
    perCell = 6, -- most motes per cell
    speed = 10, -- art pixels per second that the motes drift at wind strength 1
    direction = { 1.0, 0.3 }, -- drift direction (x east, y south)
    bob = 2, -- art pixels each way a mote bobs up and down
    streak = 2, -- extra art pixels of length a mote gets in a full gale
    color = { 0.95, 0.88, 0.72 }, -- mote colour
    alpha = 0.7, -- 0..1 brightness of a mote at the middle of its path
  },
  heat = { -- heat shimmer: whole-pixel wobble in the grade pass (shaders/grade.glsl; D85)
    seasons = { spring = 0.05, summer = 1.0, autumn = 0.2, winter = 0 }, -- season -> 0..1 how hot the day gets
    sky = { clear = 1.0, cloudy = 0.3, rain = 0, windy = 0.6, storm = 0 }, -- weather kind -> 0..1 share of the sun that gets through
    noonHours = 3.5, -- hours either side of solar noon over which the heat fades out
    cover = 0.35, -- 0..1 share of the land that wobbles at full heat
    patchW = 14, -- art pixels wide of one shimmering patch
    patchH = 3, -- art pixels tall of one patch
    rise = 5, -- art pixels per second that the patches climb
    speed = 5, -- radians per second of the wobble
    sourceWidth = 7, -- art pixels, half-width of the shimmer column over a burning stove or campfire
    sourceHeight = 22, -- art pixels the column climbs, fading out toward the top
    sourceSpeed = 7, -- radians per second of the column's wobble
    sourceSteps = 8, -- times a second the column's wobble moves on (whole steps, so it stays chunky pixel art)
    sourceWave = 0.9, -- radians per art-pixel row of the wobble (its vertical frequency; about 7 rows per wave)
    sourceDeadZone = 0.3, -- 0..1 wave level below which a pixel stays put (the calm between the bands)
    sourceReach = 1.6, -- how far the dithered column reaches (higher keeps more pixels moving toward its edges and top)
    maxSources = 4, -- most shimmering fires drawn at once (the shader's array size)
  },
  hens = { -- the flock around the coop (D63): drawn only by day, a pure function of the render clock
    wander = 1.8, -- tiles each way from the coop's middle that a hen drifts
    runDepth = 0.5, -- tiles in front of the coop the run reaches
    speed = 0.3, -- radians per second of the slow drift
    peckSpeed = 4, -- radians per second of the pecking bob
    peckAbove = 0.8, -- sine level above which a hen pecks (dips one pixel)
    eggMarker = { 0.96, 0.92, 0.82 }, -- colour of the egg dot drawn on the coop while eggs wait in the nest box
    maxDrawn = 6, -- most hens drawn (more are real but share the run)
  },
  goats = { -- the herd in each pen's yard (D71): drawn only by day, a pure function of the render clock
    wander = 0.5, -- tiles each way from the pen's middle that a goat drifts (the yard is two tiles wide)
    yardDepth = 0.9, -- tiles of the pen's front yard the herd roams
    speed = 0.25, -- radians per second of the slow drift
    grazeSpeed = 3, -- radians per second of the grazing bob
    grazeAbove = 0.8, -- sine level above which a goat grazes (dips one pixel)
    milkMarker = { 0.96, 0.96, 0.94 }, -- colour of the milk dots drawn on the pen while milk waits in the pail
    maxDrawn = 3, -- most goats drawn
  },
  tripMarker = { -- the arrow over the truck while a trip is ready (D101); a UI cue on the real-time clock
    bobSeconds = 1.2, -- seconds for one bob up and down
    bobPixels = 2, -- art pixels the arrow travels (0 when reduce motion is on)
    gap = 1, -- art pixels between the arrow's tip and the top of the truck sprite at the top of the bob
  },
  effectClock = { -- the render layer's own time (D97): world effects run on game time, UI pulses on real time
    maxSpeed = 2, -- game-speed multiplier above which effects stop speeding up: 4x game speed (and the 8x of sleep) show effects at their 2x rate, so flames, sway, shimmer, mist and lights never strobe (#265)
    wrap = 3600, -- seconds after which the effect clocks wrap (keeps shader floats small)
  },
  vignette = 0.28, -- 0..1 darkening toward the screen edges
  grain = 0.035, -- 0..1 film grain strength
}
