-- The homesteader's figure (docs/PLAN_WARDROBE.md): a big-headed chibi, built from parts and shaded
-- by the same rule as the rest of the world (D136): a light edge on the top and left of each part, a
-- dark edge on the bottom and right, a cool ink outline round the whole. Parts overlap, so the head's
-- lower edge shades the chin and a leg's inner edge parts the legs. Presentation only: `build` is
-- pure (no love.graphics), `paint` draws the result through a placeholder painter.

local Character = {}

Character.W = 20 -- sprite width in art pixels
Character.H = 22 -- sprite height; the last row holds the ground shadow
local CX = 10 -- the figure's centre column line (between columns 9 and 10)
local TOP = 4 -- rows kept above the head for hats, a pom and the hair tuft

local function hex(s)
  local r, g, b = s:match("#(%x%x)(%x%x)(%x%x)")
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

-- Three-step ramps { light, base, dark }: the dark step leans cooler and redder, never black.
local RAMPS = {
  skin = { "#f8d8b8", "#edc299", "#c4846a" },
  hair = { "#8a6240", "#5e3f2a", "#3a2619" },
  shirt = { "#d8493a", "#b8332f", "#7f2128" }, -- the homesteader's red
  jeans = { "#5a74a8", "#3f5588", "#2a3860" },
  boot = { "#7a5538", "#52382a", "#2f2018" },
  straw = { "#f6dc86", "#dcb050", "#a77a35" },
  cream = { "#fbf3dc", "#e6dcc0", "#b9ab92" },
  khaki = { "#dccb96", "#bba76e", "#8a7648" },
  canvas = { "#fffdf5", "#e4ded0", "#a9a398" },
  wool = { "#f0e6d0", "#d2c3a0", "#938468" },
  toque = { "#8795ab", "#5d6a82", "#3a445c" },
  trous = { "#737781", "#4f535f", "#313542" },
  cuff = { "#ffffff", "#eceff2", "#b2b9c4" },
  mitt = { "#8a6240", "#6a4730", "#40291c" },
}
for _, ramp in pairs(RAMPS) do
  for k = 1, 3 do
    ramp[k] = hex(ramp[k])
  end
end

local INK = hex("#14161f")
local WHITE = hex("#ffffff")
local BLUSH = hex("#e8907f")
local MOUTH = hex("#a8554a")

-- Body measurements, in art pixels.
local GEO = {
  headW = 14,
  headH = 10,
  torsoW = 6,
  torsoH = 3,
  armW = 2,
  armH = 3,
  legH = 2,
  bootH = 2,
}

-- What is worn. Each slot names a ramp. The starter outfit is today's flannel, jeans and boots.
Character.outfits = {
  starter = { legs = "jeans", boots = "boot", top = "shirt", sleeve = "shirt" },
  summer = { legs = "khaki", boots = "canvas", top = "cream", hat = "straw" },
  winter = {
    legs = "trous",
    boots = "boot",
    cuff = true,
    top = "wool",
    sleeve = "wool",
    mitts = true,
    hat = "toque",
    scarf = true,
  },
}

local function newGrid()
  local g = {}
  for y = 0, Character.H - 1 do
    g[y] = {}
  end
  return g
end

--- Fill a part. `cut` rounds it by dropping the four corner pixels.
local function fill(g, id, x, y, w, h, cut)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local corner = (i == 0 or i == w - 1) and (j == 0 or j == h - 1)
      local px, py = x + i, y + j
      if not (cut and corner) and px >= 0 and px < Character.W and py >= 0 and py < Character.H then
        g[py][px] = { id = id }
      end
    end
  end
end

-- Left and right copies of a part share a ramp but not an id, so the seam between them shades.
local function rampOf(parts, id)
  return RAMPS[parts[id] or id]
end

--- Colour every pixel from its part's ramp by its neighbours: dark where the part ends below or to the
--- right, light where it ends above or to the left. The flannel and the knit take a pattern on top.
local function shade(g, parts)
  local out = newGrid()
  for y = 0, Character.H - 1 do
    for x = 0, Character.W - 1 do
      local p = g[y][x]
      if p then
        local ramp = rampOf(parts, p.id)
        local function same(xx, yy)
          local q = g[yy] and g[yy][xx]
          return q ~= nil and q.id == p.id
        end
        local c = ramp[2]
        if not same(x + 1, y) or not same(x, y + 1) then
          c = ramp[3]
        elseif not same(x - 1, y) or not same(x, y - 1) then
          c = ramp[1]
        end
        if p.id == "shirt" and c == ramp[2] and (y % 3 == 0 or x % 3 == 0) then
          c = ramp[3] -- the check
        elseif p.id == "wool" and c == ramp[2] and x % 3 == 0 then
          c = ramp[1] -- the ribs
        end
        out[y][x] = c
      end
    end
  end
  return out
end

--- The figure as a grid of colours, out[y][x] (0-based), for an outfit from `Character.outfits`.
function Character.build(o)
  local g = newGrid()
  local parts = {}
  local geo = GEO
  local hx = CX - math.floor(geo.headW / 2)
  local tx = CX - math.floor(geo.torsoW / 2)
  local ty = TOP + geo.headH
  local ly = ty + geo.torsoH
  local by = ly + geo.legH
  local lw = math.floor(geo.torsoW / 2)

  parts.legL, parts.legR = o.legs, o.legs
  fill(g, "legL", tx, ly, lw, geo.legH)
  fill(g, "legR", tx + lw, ly, lw, geo.legH)
  parts.bootL, parts.bootR = o.boots, o.boots
  fill(g, "bootL", tx - 1, by, lw + 1, geo.bootH)
  fill(g, "bootR", tx + lw, by, lw + 1, geo.bootH)
  if o.cuff then
    parts.cuffL, parts.cuffR = "cuff", "cuff"
    fill(g, "cuffL", tx - 1, by - 1, lw + 1, 1)
    fill(g, "cuffR", tx + lw, by - 1, lw + 1, 1)
  end

  fill(g, o.top, tx, ty, geo.torsoW, geo.torsoH)
  local sleeve = o.sleeve or "skin"
  parts.armL, parts.armR = sleeve, sleeve
  fill(g, "armL", tx - geo.armW, ty, geo.armW, geo.armH - 1)
  fill(g, "armR", tx + geo.torsoW, ty, geo.armW, geo.armH - 1)
  local hand = o.mitts and "mitt" or "skin"
  parts.handL, parts.handR = hand, hand
  local handH = o.mitts and 2 or 1
  fill(g, "handL", tx - geo.armW, ty + geo.armH - 1, geo.armW, handH)
  fill(g, "handR", tx + geo.torsoW, ty + geo.armH - 1, geo.armW, handH)

  fill(g, "skin", hx, TOP, geo.headW, geo.headH, true)
  fill(g, "hair", hx, TOP, geo.headW, 3, true)
  fill(g, "hair", hx, TOP + 3, 1, 3) -- sideburns
  fill(g, "hair", hx + geo.headW - 1, TOP + 3, 1, 3)
  fill(g, "hair", hx + 1, TOP + 3, 4, 1) -- the fringe
  fill(g, "hair", hx + 1, TOP + 4, 2, 1)
  fill(g, "hair", hx + geo.headW - 3, TOP + 3, 2, 1)
  if not o.hat then
    fill(g, "hair", CX - 1, TOP - 1, 3, 1) -- a cowlick
    fill(g, "hair", CX + 1, TOP - 2, 1, 1)
  end

  if o.hat == "straw" then
    fill(g, "straw", hx + 1, TOP - 2, geo.headW - 2, 4, true)
    fill(g, "shirt", hx + 1, TOP, geo.headW - 2, 2) -- the band: the red travels with the outfit
    fill(g, "straw", hx - 2, TOP + 2, geo.headW + 4, 2, true)
  elseif o.hat == "toque" then
    fill(g, "toque", hx, TOP - 1, geo.headW, 4, true)
    fill(g, "cuff", hx, TOP + 2, geo.headW, 1)
    fill(g, "cuff", CX - 1, TOP - 3, 2, 2)
  end
  if o.scarf then
    fill(g, "shirt", tx - 1, ty - 1, geo.torsoW + 2, 2)
    fill(g, "shirt", tx + geo.torsoW - 2, ty + 1, 2, math.min(3, geo.torsoH))
  end

  local out = shade(g, parts)

  -- The face goes on after shading so it keeps its own colours: 2x2 eyes with a glint, blush, a mouth.
  local ey = TOP + geo.headH - 5
  for _, ex in ipairs({ hx + 3, hx + geo.headW - 5 }) do
    for dy = 0, 1 do
      for dx = 0, 1 do
        out[ey + dy][ex + dx] = INK
      end
    end
    out[ey][ex] = WHITE
  end
  for _, bx in ipairs({ hx + 2, hx + geo.headW - 3 }) do
    if g[ey + 2][bx] and g[ey + 2][bx].id == "skin" then
      out[ey + 2][bx] = BLUSH
    end
  end
  out[ey + 3][CX - 1] = MOUTH
  out[ey + 3][CX] = MOUTH
  return out
end

--- Paint the figure and its ground shadow through a placeholder painter `p`.
function Character.paint(p, outfit, shadow)
  p:ellipse(CX, Character.H - 1, 6, 1, shadow)
  local grid = Character.build(outfit or Character.outfits.starter)
  for y = 0, Character.H - 1 do
    for x = 0, Character.W - 1 do
      local c = grid[y][x]
      if c then
        p:px(x, y, c)
      end
    end
  end
  p:outline(INK)
end

return Character
