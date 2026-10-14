-- Pointer & touch gesture thresholds, and the keyboard bindings.
return {
  dragThreshold = 4, -- virtual pixels a press must move before it becomes a pan instead of a tap
  longPressTime = 0.5, -- seconds a still press must be held to count as a long-press (context action)
  minTouchTarget = 24, -- virtual pixels; smallest allowed edge for tappable UI elements
  -- Key bindings, by LÖVE key name. These are the defaults; the player's overrides live in the settings
  -- file and are merged over them by src/core/key_bindings.lua (D121, Settings > Controls).
  keyActions = { -- key -> action name sent to the scene (no payload)
    escape = "cancel",
    space = "speed", -- cycle the game speed
    r = "routine", -- start the idle routine now
    pageup = "pageUp", -- scroll the open panel list up one window (D94)
    pagedown = "pageDown", -- scroll the open panel list down one window
    home = "listHome", -- jump to the top of the open panel list
    ["end"] = "listEnd", -- jump to the bottom of the open panel list
  },
  rebindable = { "speed", "routine", "pageUp", "pageDown", "listHome", "listEnd" }, -- action names the Controls screen lets the player rebind, in display order; each has exactly one default key above (cancel stays on Esc)
  reservedKeys = { -- LÖVE key names no action may be bound to: they carry fixed meanings in every scene
    "escape", -- cancel / back; also how a rebind is abandoned
    "f1", "f2", "f3", "f6", "f7", -- debug overlay, sim speed, perf overlay, reload tuning, sound test (live in every build)
    "return", "kpenter", "backspace", "tab", -- text fields and confirmations
    "lshift", "rshift", "lctrl", "rctrl", "lalt", "ralt", "lgui", "rgui", -- modifiers (Shift latches the Plan tool, Ctrl+F searches)
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
