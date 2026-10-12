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
  -- Screen grading (shaders/grade.glsl)
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
  vignette = 0.28, -- 0..1 darkening toward the screen edges
  grain = 0.035, -- 0..1 film grain strength
}
