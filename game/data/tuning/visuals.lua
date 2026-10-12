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
    segments = 28, -- polygon segments in a full circle
  },
  vignette = 0.28, -- 0..1 darkening toward the screen edges
  grain = 0.035, -- 0..1 film grain strength
}
