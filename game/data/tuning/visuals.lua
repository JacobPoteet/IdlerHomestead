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
  -- Snow (shaders/snow.glsl)
  snowColor = { 0.93, 0.95, 0.98 }, -- fresh snow
  snowShade = { 0.72, 0.80, 0.90 }, -- clump edges
  snowClumpScale = 0.18, -- snow clump noise frequency (higher = smaller patches)
  snowRampDays = 1.5, -- in-game days for snow to cover the ground once the freeze starts
  snowMeltDays = 2, -- in-game days for snow to melt after the thaw
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
  weather = { -- day-to-day weather look (D51); full ambience (cloud shadows, wind sway, wet ground) is #49
    blendSeconds = 3, -- real seconds for the look to ease into a new day's weather
    looks = { -- weather kind -> { tint multiplier on the grade, light multiplier, rain 0..1 streak density }
      clear = { tint = { 1.00, 1.00, 1.00 }, light = 1.00, rain = 0 },
      cloudy = { tint = { 0.90, 0.94, 1.00 }, light = 0.86, rain = 0 },
      rain = { tint = { 0.80, 0.88, 1.00 }, light = 0.76, rain = 0.7 },
      windy = { tint = { 0.95, 0.97, 1.00 }, light = 0.94, rain = 0 },
      storm = { tint = { 0.68, 0.76, 0.94 }, light = 0.62, rain = 1 },
    },
    rain = { -- the falling streaks, drawn over the graded world in virtual UI pixels
      drops = 260, -- streaks on screen at full intensity per referenceArea
      referenceArea = 230400, -- virtual pixels^2 the drops count is for (640x360)
      length = 9, -- pixels, average streak length
      width = 1, -- pixels
      slant = 0.25, -- horizontal pixels each streak leans per vertical pixel (wind direction)
      speed = 260, -- pixels per second, average fall speed
      color = { 0.78, 0.88, 1.00, 0.7 }, -- r, g, b, alpha at full intensity
    },
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
  vignette = 0.28, -- 0..1 darkening toward the screen edges
  grain = 0.035, -- 0..1 film grain strength
}
