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
  -- Wardrobe garments (docs/PLAN_WARDROBE.md): each a three-step ramp in the same family as the rest.
  tweed = { "#9aa874", "#6f7f50", "#465436" }, -- the flat cap: moss
  pelt = { "#b08a64", "#82603f", "#573d29" }, -- the trapper hat
  fur = { "#f6f1e7", "#d9d0c0", "#9f9482" }, -- fur trim and the parka's hem
  sage = { "#bdd3b0", "#93b088", "#62845f" }, -- the tank top
  denim = { "#a9c2dc", "#7396bd", "#4a6790" }, -- the denim jacket, faded lighter than the jeans
  oil = { "#f2d25e", "#d3a835", "#9a7222" }, -- the oilskin coat
  parka = { "#79adb2", "#4c808c", "#305468" }, -- the down parka
  overall = { "#6f86b0", "#34497a", "#202e54" }, -- overalls, darker than the jeans
  bibs = { "#6f9a82", "#456f58", "#2c4a3c" }, -- insulated bibs
  felt = { "#a89880", "#7d6e58", "#53473a" }, -- felt-lined boots
  snow = { "#7f8b9c", "#4d5868", "#2d3445" }, -- snow boots
  leather = { "#d4b078", "#a8814a", "#74552f" }, -- work gloves
  knit = { "#b4cdbf", "#85a898", "#5a7c6d" }, -- mittens
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

-- What is worn: the fields of a "look", each naming a ramp: top, sleeve, legs, boots, plus `hat` (straw, toque,
-- cap, trapper). `cuff` and `mitts` take a ramp (true is the default ramp), `glove` thins the hands to one row,
-- `shorts` bares the shins, `belt` is a ramp for a hem row, `bib` a ramp for a bib over the torso, `bandana`
-- ties a small red kerchief, `accent` puts four red pixels at the hem of a torso that is not the red flannel (the red
-- travels). The starter outfit is today's flannel, jeans and boots. Garments name these fields in
-- data/content/garments.lua and `Character.outfitFor` merges them.
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

Character.slots = { "head", "torso", "legs", "feet", "extra" } -- the wardrobe's slots, in paint order

--- The look (the fields `build` reads) of a wardrobe outfit `{ slot = garmentId }`: each slot's garment
--- `look` merged in slot order. A missing or unknown id, or one for another slot, wears that slot's default
--- garment. Pure: reads the registry's garments, draws nothing.
function Character.outfitFor(registry, outfit)
  local look = {}
  local garments = registry:all("garments")
  for _, slot in ipairs(Character.slots) do
    local id = outfit and outfit[slot]
    local def
    if id and registry:has("garments", id) then
      def = registry:get("garments", id)
      if def.slot ~= slot then
        def = nil
      end
    end
    if not def then
      for _, g in ipairs(garments) do
        if g.slot == slot and g.default then
          def = g
          break
        end
      end
    end
    if def then
      for field, value in pairs(def.look) do
        look[field] = value
      end
    end
  end
  return look
end

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

--- The figure as a grid of colours, out[y][x] (0-based), for a look (the fields of `Character.outfits`). The
--- second result is the grid of part ids, ids[y][x] (the part that owns each pixel, before the face is drawn
--- over it), so a garment's pixels can be found.
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
  fill(g, "legL", tx, ly, lw, o.shorts and 1 or geo.legH)
  fill(g, "legR", tx + lw, ly, lw, o.shorts and 1 or geo.legH)
  if o.shorts then
    parts.shinL, parts.shinR = "skin", "skin"
    fill(g, "shinL", tx, ly + 1, lw, 1)
    fill(g, "shinR", tx + lw, ly + 1, lw, 1)
  end
  parts.bootL, parts.bootR = o.boots, o.boots
  fill(g, "bootL", tx - 1, by, lw + 1, geo.bootH)
  fill(g, "bootR", tx + lw, by, lw + 1, geo.bootH)
  if o.cuff then
    local cuff = o.cuff == true and "cuff" or o.cuff
    parts.cuffL, parts.cuffR = cuff, cuff
    fill(g, "cuffL", tx - 1, by - 1, lw + 1, 1)
    fill(g, "cuffR", tx + lw, by - 1, lw + 1, 1)
  end

  fill(g, o.top, tx, ty, geo.torsoW, geo.torsoH)
  local sleeve = o.sleeve or "skin"
  parts.armL, parts.armR = sleeve, sleeve
  fill(g, "armL", tx - geo.armW, ty, geo.armW, geo.armH - 1)
  fill(g, "armR", tx + geo.torsoW, ty, geo.armW, geo.armH - 1)
  local hand = "skin"
  if o.mitts then
    hand = o.mitts == true and "mitt" or o.mitts
  end
  parts.handL, parts.handR = hand, hand
  local handH = (o.mitts and not o.glove) and 2 or 1
  fill(g, "handL", tx - geo.armW, ty + geo.armH - 1, geo.armW, handH)
  fill(g, "handR", tx + geo.torsoW, ty + geo.armH - 1, geo.armW, handH)
  if o.belt then
    parts.belt = o.belt
    fill(g, "belt", tx, ty + geo.torsoH - 1, geo.torsoW, 1)
  end
  if o.bib then
    parts.bib = o.bib
    fill(g, "bib", tx + 1, ty + 1, geo.torsoW - 2, 2)
  end

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
  elseif o.hat == "cap" then
    fill(g, "tweed", hx, TOP - 1, geo.headW, 3, true) -- the crown, flat and wide
    parts.brim = "tweed"
    fill(g, "brim", hx + 2, TOP + 2, geo.headW - 4, 2) -- the bill over the forehead
  elseif o.hat == "trapper" then
    fill(g, "pelt", hx, TOP - 1, geo.headW, 4, true)
    parts.band = "fur"
    fill(g, "band", hx, TOP + 2, geo.headW, 1) -- the fur turn-up
    parts.flapL, parts.flapR = "pelt", "pelt"
    fill(g, "flapL", hx - 1, TOP + 2, 2, 5, true) -- ear flaps hang past the cheeks
    fill(g, "flapR", hx + geo.headW - 1, TOP + 2, 2, 5, true)
  end
  if o.scarf then
    fill(g, "shirt", tx - 1, ty - 1, geo.torsoW + 2, 2)
    fill(g, "shirt", tx + geo.torsoW - 2, ty + 1, 2, math.min(3, geo.torsoH))
  elseif o.bandana then
    parts.knot = "shirt"
    fill(g, "knot", tx, ty - 1, geo.torsoW, 2, true) -- a small kerchief, tied at the throat
  end

  local out = shade(g, parts)
  local ids = newGrid()
  for y = 0, Character.H - 1 do
    for x = 0, Character.W - 1 do
      if g[y][x] then
        ids[y][x] = g[y][x].id
      end
    end
  end

  -- The red travels: a torso that is not the red flannel keeps four red pixels at its hem (a tag, a buckle),
  -- drawn after shading so they stay saturated. Four pixels read as the homesteader's accent, not a patch.
  if o.accent then
    for dx = -2, 1 do
      out[ty + geo.torsoH - 1][CX + dx] = RAMPS.shirt[2]
    end
  end

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
  return out, ids
end

local function sameColour(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

--- The pixels garment `id` adds to the figure of `outfit` (`{ slot = garmentId }`) beyond the slot's default
--- garment: mask[y][x] = true where the figure wearing it has a pixel the default does not, or one of another
--- colour or part. Pure. The wardrobe draws it in ink over the draft figure for a garment not yet earned.
function Character.silhouette(registry, outfit, slot, id)
  local with, base = {}, {}
  for _, s in ipairs(Character.slots) do
    with[s], base[s] = outfit and outfit[s], outfit and outfit[s]
  end
  with[slot], base[slot] = id, nil
  local a, aIds = Character.build(Character.outfitFor(registry, base))
  local b, bIds = Character.build(Character.outfitFor(registry, with))
  local mask = {}
  for y = 0, Character.H - 1 do
    mask[y] = {}
    for x = 0, Character.W - 1 do
      local c = b[y][x]
      if c and (not a[y][x] or aIds[y][x] ~= bIds[y][x] or not sameColour(a[y][x], c)) then
        mask[y][x] = true
      end
    end
  end
  return mask
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
