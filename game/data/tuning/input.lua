-- Pointer & touch gesture thresholds.
return {
  dragThreshold = 4, -- virtual pixels a press must move before it becomes a pan instead of a tap
  longPressTime = 0.5, -- seconds a still press must be held to count as a long-press (context action)
  minTouchTarget = 24, -- virtual pixels; smallest allowed edge for tappable UI elements
}
