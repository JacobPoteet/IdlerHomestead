-- Pointer & touch gesture thresholds, and the keyboard bindings.
return {
  dragThreshold = 4, -- virtual pixels a press must move before it becomes a pan instead of a tap
  longPressTime = 0.5, -- seconds a still press must be held to count as a long-press (context action)
  minTouchTarget = 24, -- virtual pixels; smallest allowed edge for tappable UI elements
  -- Key bindings, by LÖVE key name. Rebindable from the Settings menu once it exists (#50).
  keyActions = { -- key -> action name sent to the scene (no payload)
    escape = "cancel",
    space = "speed", -- cycle the game speed
    r = "routine", -- start the idle routine now
  },
  panKeys = { -- key -> { dx, dy } direction the camera view moves (held keys)
    left = { -1, 0 },
    a = { -1, 0 },
    right = { 1, 0 },
    d = { 1, 0 },
    up = { 0, -1 },
    w = { 0, -1 },
    down = { 0, 1 },
    s = { 0, 1 },
  },
  zoomKeys = { -- key -> zoom steps
    ["="] = 1,
    ["+"] = 1,
    ["kp+"] = 1,
    ["-"] = -1,
    ["kp-"] = -1,
  },
}
