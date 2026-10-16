-- UI colours and text sizes (GDD §9.4, D142). Warm darks lit from the top left like the world; amber
-- means "needs you", red means danger, and the interface uses no green (the world is green).
return {
  colors = {
    background = { 0.09, 0.08, 0.08, 1 },
    panel = { 0.13, 0.12, 0.11, 0.94 }, -- a plate's base; also its flat fallback when the plate shader is missing
    panelBorder = { 0.06, 0.05, 0.05, 1 }, -- a plate's dark outline
    panelLit = { 1.00, 0.92, 0.74 }, -- the sun-side (top and left) inner edge
    panelShade = { 0.05, 0.06, 0.10 }, -- the shade-side (bottom and right) inner edge
    text = { 0.95, 0.92, 0.84, 1 },
    textDim = { 0.70, 0.67, 0.61, 1 },
    textShadow = { 0.06, 0.04, 0.03, 0.85 }, -- one UI pixel down and right of every glyph
    accent = { 0.96, 0.74, 0.32, 1 },
    danger = { 0.92, 0.42, 0.36, 1 },
    button = { 0.20, 0.18, 0.16, 1 },
    buttonHover = { 0.25, 0.22, 0.19, 1 },
    buttonPressed = { 0.12, 0.11, 0.10, 1 },
    buttonDisabled = { 0.15, 0.14, 0.13, 1 },
    overlay = { 0.03, 0.03, 0.05, 0.55 },
  },
  -- Text sizes as UI pixels per font pixel: the pixel font (src/ui/pixel_font.lua) is drawn only at
  -- whole multiples, so small and body share the 7 px font and headings are drawn twice or three times as big.
  textScale = {
    small = 1,
    body = 1,
    heading = 2,
    title = 3,
  },
}
