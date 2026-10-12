-- UI colors and text sizes. Placeholder palette until the art pass (GDD §9.2).
return {
  colors = {
    background = { 0.10, 0.12, 0.11, 1 },
    panel = { 0.16, 0.19, 0.17, 0.96 },
    panelBorder = { 0.36, 0.42, 0.34, 1 },
    text = { 0.93, 0.91, 0.84, 1 },
    textDim = { 0.64, 0.66, 0.60, 1 },
    accent = { 0.89, 0.71, 0.36, 1 },
    danger = { 0.85, 0.40, 0.34, 1 },
    button = { 0.25, 0.30, 0.24, 1 },
    buttonHover = { 0.31, 0.37, 0.29, 1 },
    buttonPressed = { 0.20, 0.24, 0.19, 1 },
    buttonDisabled = { 0.19, 0.21, 0.19, 1 },
    overlay = { 0, 0, 0, 0.55 },
  },
  -- Text sizes in virtual pixels.
  textSize = {
    small = 8,
    body = 10,
    heading = 16,
    title = 28,
  },
}
