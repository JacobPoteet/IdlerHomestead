-- Procedural placeholder pixel art, drawn once into the sprite atlas at startup.
-- Each painter receives a pixel helper `p` (0-based coordinates inside the sprite) and the
-- variant number. Replace entries in assets/manifest.lua with real art to retire these.

local Character = require("src.render.character")

local P = {}

-- The value plan: the open ground is light and warm, foliage and objects are deep and cool, and the
-- homesteader's red is kept for the homesteader and a few other things, so what matters stands out at a glance.
local C = {
  grass = { 0.561, 0.690, 0.373 },
  grassDark = { 0.490, 0.624, 0.333 },
  grassLight = { 0.631, 0.749, 0.420 },
  road = { 0.72, 0.56, 0.38 },
  roadDark = { 0.62, 0.46, 0.30 },
  pebble = { 0.82, 0.74, 0.58 },
  soilDry = { 0.57, 0.37, 0.24 },
  furrowDry = { 0.44, 0.27, 0.18 },
  soilWet = { 0.36, 0.22, 0.15 },
  furrowWet = { 0.26, 0.15, 0.11 },
  stone = { 0.56, 0.57, 0.60 },
  stoneLight = { 0.76, 0.76, 0.75 },
  stoneDark = { 0.33, 0.34, 0.38 },
  leaf = { 0.15, 0.40, 0.24 },
  leafLight = { 0.33, 0.57, 0.27 },
  leafDark = { 0.08, 0.25, 0.18 },
  bark = { 0.45, 0.28, 0.19 },
  barkDark = { 0.27, 0.15, 0.13 },
  barkLight = { 0.62, 0.42, 0.27 },
  rust = { 0.55, 0.30, 0.18 },
  metal = { 0.50, 0.53, 0.55 },
  shadow = { 0, 0, 0, 0.28 },
  radish = { 0.80, 0.22, 0.32 },
  potatoFlower = { 0.92, 0.90, 0.80 },
  skin = { 0.93, 0.76, 0.60 },
  shirt = { 0.80, 0.24, 0.20 },
  shirtDark = { 0.56, 0.15, 0.17 },
  pants = { 0.25, 0.32, 0.45 },
  hair = { 0.35, 0.24, 0.16 },
  boot = { 0.22, 0.16, 0.12 },
  truckBody = { 0.78, 0.82, 0.84 },
  truckDark = { 0.55, 0.60, 0.64 },
  glass = { 0.32, 0.46, 0.56 },
  tire = { 0.12, 0.12, 0.13 },
  gold = { 0.92, 0.76, 0.30 },
  water = { 0.35, 0.62, 0.80 },
  white = { 0.95, 0.95, 0.92 },
  heart = { 0.86, 0.30, 0.32 },
  outline = { 0.07, 0.08, 0.12 }, -- the 1-pixel edge round crops and small sprites (#20); a cool ink, not black
  sprout = { 0.58, 0.88, 0.36 }, -- fresh bright green: sprouts and new leaves
  sproutLight = { 0.80, 0.97, 0.52 },
  sproutDark = { 0.30, 0.62, 0.24 },
  moundSoil = { 0.66, 0.50, 0.34 }, -- pale turned soil under a sprout
  radishLight = { 0.98, 0.50, 0.55 },
  waterLight = { 0.58, 0.82, 0.96 },
  sparkle = { 1.00, 0.90, 0.45 },
  sparkleEdge = { 0.55, 0.38, 0.08, 0.8 },
}
P.colors = C

local function speckle(p, w, h, base, specks, count)
  p:rect(0, 0, w, h, base)
  for _ = 1, count do
    p:px(p.rng:int(0, w - 1), p.rng:int(0, h - 1), specks[p.rng:int(1, #specks)])
  end
end

function P.grass(p, w, h)
  speckle(p, w, h, C.grass, { C.grassDark, C.grassLight }, 10) -- few specks: the ground is a calm plane the light and shadows play on
  for _ = 1, 2 do -- little blades
    local x, y = p.rng:int(1, w - 2), p.rng:int(2, h - 1)
    p:px(x, y, C.grassDark)
    p:px(x, y - 1, C.grassLight)
  end
end

function P.road(p, w, h)
  speckle(p, w, h, C.road, { C.roadDark, C.pebble }, 18)
end

local function furrows(p, w, h, soil, furrow)
  p:rect(0, 0, w, h, soil)
  for y = 2, h - 1, 4 do
    p:rect(1, y, w - 2, 1, furrow)
  end
  for _ = 1, 6 do
    p:px(p.rng:int(0, w - 1), p.rng:int(0, h - 1), furrow)
  end
end

function P.tilled_dry(p, w, h)
  furrows(p, w, h, C.soilDry, C.furrowDry)
end

function P.tilled_wet(p, w, h)
  furrows(p, w, h, C.soilWet, C.furrowWet)
end

function P.ford_stones(p)
  for _, s in ipairs({ { 3, 4 }, { 10, 6 }, { 5, 11 }, { 12, 12 } }) do
    p:ellipse(s[1], s[2] + 1, 2, 1, C.shadow)
    p:ellipse(s[1], s[2], 2, 1, C.stone)
    p:px(s[1] - 1, s[2] - 1, C.stoneLight)
  end
end

function P.trip_marker(p)
  -- A downward arrow, gold with a dark edge, pointing at the truck (D101).
  local function arrow(ox, oy, color)
    p:rect(ox + 3, oy, 3, 5, color)
    for row = 0, 4 do
      p:rect(ox + row, oy + 5 + row, 9 - 2 * row, 1, color)
    end
  end
  for _, d in ipairs({ { 0, 1 }, { 2, 1 }, { 1, 0 }, { 1, 2 } }) do
    arrow(d[1], d[2], { 0.12, 0.10, 0.06, 0.9 })
  end
  arrow(1, 1, C.gold)
end

-- Foliage as lit clumps instead of speckle: each clump { cx, cy, r } is a dark ball with a mid-tone ball
-- nudged up-left, a light patch toward the top-left and a small highlight, painted back to front so the
-- front clump's dark rim separates it from the one behind. `ramp` = { dark, mid, light, highlight }.
local function clumps(p, list, ramp)
  for _, k in ipairs(list) do
    local cx, cy, r = k[1], k[2], k[3]
    p:circle(cx, cy, r, ramp[1])
    p:circle(cx - 1, cy - 1, r - 1, ramp[2])
    local q = math.max(1, math.floor(r / 2))
    p:circle(cx - math.ceil(r / 3), cy - math.ceil(r / 3), q - 1, ramp[3])
    p:px(cx - math.ceil(r / 2), cy - math.ceil(r / 2), ramp[4])
  end
end

local BROADLEAF = { C.leafDark, C.leaf, C.leafLight, { 0.52, 0.70, 0.33 } }
local PINE = { { 0.05, 0.19, 0.16 }, { 0.09, 0.31, 0.22 }, { 0.19, 0.44, 0.27 }, { 0.32, 0.56, 0.31 } }
local BIRCH = { { 0.20, 0.42, 0.20 }, { 0.36, 0.58, 0.27 }, { 0.55, 0.72, 0.33 }, { 0.74, 0.85, 0.45 } }

function P.brush(p)
  p:ellipse(8, 13, 6, 2, C.shadow)
  clumps(p, { { 9, 6, 3 }, { 5, 9, 3 }, { 11, 9, 3 }, { 8, 11, 3 } }, BROADLEAF)
  p:px(4, 12, C.barkDark)
  p:px(11, 12, C.barkDark)
  p:outline(C.outline)
end

-- A boulder with a pebble beside it, in planes: a dark body, a mid face turned up-left, a lit facet on
-- top and one highlight, so it reads as a solid lump rather than a grey disc.
function P.rock(p)
  p:ellipse(8, 13, 6, 2, C.shadow)
  p:ellipse(12, 11, 2, 2, C.stoneDark) -- the pebble
  p:px(11, 10, C.stone)
  p:ellipse(7, 9, 5, 4, C.stoneDark)
  p:ellipse(6, 8, 4, 3, C.stone)
  p:ellipse(5, 7, 2, 1, C.stoneLight)
  p:px(4, 6, C.white)
  p:rect(8, 10, 3, 1, C.stoneDark) -- a crack along the shaded side
  p:outline(C.outline)
end

-- A fallen log as a lit cylinder: a light band along the top, a dark underside, bark grooves, and a pale
-- cut end with its rings.
function P.log(p)
  local grain, ring = { 0.84, 0.66, 0.44 }, { 0.66, 0.46, 0.28 }
  p:ellipse(8, 12, 7, 2, C.shadow)
  p:rect(1, 7, 12, 5, C.bark)
  p:rect(1, 7, 12, 1, C.barkLight)
  p:rect(1, 10, 12, 2, C.barkDark)
  for _, g in ipairs({ { 3, 9, 3 }, { 7, 8, 4 }, { 10, 9, 2 } }) do
    p:rect(g[1], g[2], g[3], 1, C.barkDark)
  end
  p:ellipse(13, 9, 2, 2, grain)
  p:px(13, 9, ring)
  p:px(14, 10, ring)
  p:outline(C.outline)
end

-- A crate, a tyre and a bent sheet of metal, each with a lit top and a shaded side.
function P.junk(p)
  local rustDark = { 0.36, 0.18, 0.12 }
  p:ellipse(8, 13, 7, 2, C.shadow)
  p:rect(2, 7, 6, 5, C.rust) -- crate
  p:rect(2, 7, 6, 1, C.barkLight)
  p:rect(2, 9, 5, 1, rustDark) -- plank line
  p:rect(7, 8, 1, 4, rustDark) -- shaded side
  p:circle(11, 10, 3, C.tire) -- tyre
  p:circle(11, 10, 1, C.metal)
  p:px(9, 8, C.stoneDark)
  p:rect(5, 4, 5, 3, C.metal) -- sheet metal
  p:rect(5, 4, 5, 1, C.stoneLight)
  p:rect(5, 6, 5, 1, C.stoneDark)
  p:outline(C.outline)
end

function P.tree(p)
  p:ellipse(8, 30, 7, 2, C.shadow)
  p:rect(6, 16, 4, 14, C.bark)
  p:rect(6, 16, 1, 14, C.barkLight)
  p:rect(9, 16, 1, 14, C.barkDark)
  clumps(p, { { 8, 5, 4 }, { 4, 9, 4 }, { 12, 8, 4 }, { 7, 13, 5 }, { 12, 13, 3 } }, BROADLEAF)
  p:outline(C.outline)
end

-- A conifer: four stacked tiers, each a triangle lit on its left half, on a short trunk.
function P.pine(p)
  p:ellipse(8, 30, 6, 2, C.shadow)
  p:rect(7, 24, 3, 6, C.bark)
  p:rect(7, 24, 1, 6, C.barkLight)
  p:rect(9, 24, 1, 6, C.barkDark)
  for _, t in ipairs({ { 1, 7, 3 }, { 6, 7, 5 }, { 11, 8, 6 }, { 16, 8, 7 } }) do
    local top, h, halfW = t[1], t[2], t[3]
    for row = 0, h - 1 do
      local half = math.max(1, math.floor(halfW * (row + 1) / h + 0.5))
      p:rect(8 - half, top + row, half, 1, row < h - 1 and PINE[2] or PINE[1]) -- lit side
      p:rect(8, top + row, half, 1, PINE[1]) -- shaded side
      p:px(8 - half, top + row, PINE[3]) -- the lit edge
    end
    p:px(7, top + 1, PINE[4])
  end
  p:outline(C.outline)
end

-- A birch: pale marked trunk under a light, airy crown of small clumps.
function P.birch(p)
  local trunk, trunkDark = { 0.86, 0.85, 0.78 }, { 0.20, 0.19, 0.17 }
  p:ellipse(8, 30, 6, 2, C.shadow)
  p:rect(7, 12, 2, 18, trunk)
  for y = 16, 28, 4 do
    p:px(7 + (y / 4) % 2, y, trunkDark)
  end
  clumps(p, { { 8, 4, 3 }, { 5, 8, 3 }, { 11, 7, 3 }, { 8, 11, 3 }, { 12, 12, 2 }, { 4, 13, 2 } }, BIRCH)
  p:outline(C.outline)
end

function P.truck(p)
  -- Top-down 3/4 electric pickup, facing right. Footprint is 2x1 tiles; the cab rises above it.
  p:ellipse(16, 22, 15, 2, C.shadow)
  p:rect(1, 10, 30, 11, C.truckDark) -- lower body
  p:rect(1, 8, 30, 6, C.truckBody) -- upper body / bed rails
  p:rect(3, 9, 15, 4, C.truckDark) -- empty bed
  p:rect(19, 3, 10, 8, C.truckBody) -- cab
  p:rect(21, 4, 7, 4, C.glass) -- windshield
  p:rect(21, 4, 2, 1, C.white)
  p:rect(29, 12, 2, 2, C.gold) -- headlight
  for _, wx in ipairs({ 6, 24 }) do
    p:rect(wx - 3, 18, 6, 4, C.tire)
    p:rect(wx - 1, 19, 2, 2, C.metal)
  end
end

-- Crops (#20, D102): every stage is a bright shape with a dark outline, and the sprout stands on a
-- pale mound of turned soil, so it reads against dark furrows, snow and the night grade.
local function cropBase(p, mound)
  p:rect(4, 12, 8, 1, C.furrowWet)
  if mound then
    p:ellipse(8, 12, 3, 1, C.moundSoil)
  end
end

function P.radish(p, _, _, variant)
  cropBase(p, variant == 1)
  if variant == 1 then -- sprout: two seed leaves on a stem, 8 pixels wide
    p:rect(8, 8, 1, 4, C.sproutDark)
    p:ellipse(5, 8, 2, 1, C.sprout)
    p:ellipse(11, 7, 2, 1, C.sproutLight)
    p:px(8, 7, C.sproutLight)
  elseif variant == 2 then -- growing: a leafy fan, twice as tall
    p:rect(8, 6, 1, 6, C.leafDark)
    p:ellipse(5, 7, 2, 3, C.leaf)
    p:ellipse(11, 7, 2, 3, C.sprout)
    p:ellipse(8, 4, 2, 3, C.sproutLight)
  else -- ready: the red root shows above the soil under a tall crown
    p:ellipse(5, 5, 2, 3, C.leaf)
    p:ellipse(11, 5, 2, 3, C.sprout)
    p:ellipse(8, 3, 2, 3, C.sproutLight)
    p:circle(8, 10, 3, C.radish)
    p:px(7, 9, C.radishLight)
    p:px(8, 13, C.white)
  end
  p:outline(C.outline)
end

function P.potato(p, _, _, variant)
  cropBase(p, variant == 1)
  if variant == 1 then -- sprout: a stem with a round cluster of leaves
    p:rect(8, 9, 1, 3, C.sproutDark)
    p:circle(8, 8, 2, C.sprout)
    p:px(7, 7, C.sproutLight)
    p:px(9, 8, C.sproutLight)
  elseif variant == 2 then -- growing: a bushy mound of two lit clumps
    clumps(p, { { 7, 7, 3 }, { 9, 9, 3 } }, { C.sproutDark, C.sprout, C.sproutLight, C.white })
  else -- ready: a big dark bush of lit clumps dotted with white flowers
    clumps(p, { { 6, 5, 3 }, { 10, 6, 3 }, { 8, 9, 4 } }, BROADLEAF)
    for _, f in ipairs({ { 5, 4 }, { 10, 5 }, { 8, 8 }, { 6, 8 }, { 11, 9 }, { 8, 3 } }) do
      p:px(f[1], f[2], C.potatoFlower)
    end
  end
  p:outline(C.outline)
end

-- The nine later crops (D177, #363) share one placeholder painter, set by a look: the shape of the ready stage
-- (rosette, bush, root, tall) and the colour of what you pick. Real art replaces them one id at a time.
local function shade(c, k)
  return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k) }
end

local CROP_LOOKS = {
  lettuce = { kind = "rosette", fruit = { 0.50, 0.80, 0.32 } },
  beans = { kind = "bush", fruit = { 0.42, 0.72, 0.26 } },
  carrot = { kind = "root", fruit = { 0.93, 0.55, 0.18 } },
  onion = { kind = "root", fruit = { 0.86, 0.70, 0.40 } },
  garlic = { kind = "root", fruit = { 0.92, 0.90, 0.82 } },
  squash = { kind = "bush", fruit = { 0.92, 0.62, 0.18 } },
  tomato = { kind = "bush", fruit = { 0.86, 0.20, 0.16 } },
  corn = { kind = "tall", fruit = { 0.95, 0.82, 0.30 } },
  herbs = { kind = "rosette", fruit = { 0.55, 0.36, 0.68 } },
  berries = { kind = "bush", fruit = { 0.34, 0.22, 0.62 } }, -- D183: the perennials
  apple = { kind = "bush", fruit = { 0.82, 0.16, 0.14 } },
}

local function laterCrop(look)
  local ramp = { shade(look.fruit, 0.6), look.fruit, shade(look.fruit, 1.3), shade(look.fruit, 1.6) }
  return function(p, _, _, variant)
    cropBase(p, variant == 1)
    if variant == 1 then -- sprout: two seed leaves on a stem
      p:rect(8, 8, 1, 4, C.sproutDark)
      p:ellipse(5, 8, 2, 1, C.sprout)
      p:ellipse(11, 7, 2, 1, C.sproutLight)
      p:px(8, 7, C.sproutLight)
    elseif variant == 2 then -- growing: a leafy fan (a stalk for the tall ones)
      if look.kind == "tall" then
        p:rect(7, 3, 2, 9, C.leafDark)
        p:ellipse(4, 6, 2, 1, C.leaf)
        p:ellipse(12, 5, 2, 1, C.sprout)
        p:ellipse(4, 9, 2, 1, C.sprout)
      else
        p:rect(8, 6, 1, 6, C.leafDark)
        p:ellipse(5, 7, 2, 3, C.leaf)
        p:ellipse(11, 7, 2, 3, C.sprout)
        p:ellipse(8, 4, 2, 3, C.sproutLight)
      end
    elseif look.kind == "rosette" then -- ready: a full head of leaves in the crop's colour
      clumps(p, { { 5, 8, 3 }, { 11, 8, 3 }, { 8, 6, 4 } }, ramp)
    elseif look.kind == "bush" then -- ready: a leafy bush hung with the fruit
      clumps(p, { { 6, 6, 3 }, { 10, 7, 3 }, { 8, 9, 3 } }, BROADLEAF)
      for _, f in ipairs({ { 5, 5 }, { 10, 6 }, { 8, 9 }, { 6, 9 }, { 11, 9 } }) do
        p:rect(f[1], f[2], 2, 2, look.fruit)
      end
    elseif look.kind == "root" then -- ready: the root shows above the soil under a tall crown
      p:ellipse(5, 5, 2, 3, C.leaf)
      p:ellipse(11, 5, 2, 3, C.sprout)
      p:ellipse(8, 3, 2, 3, C.sproutLight)
      p:circle(8, 10, 3, look.fruit)
      p:px(7, 9, shade(look.fruit, 1.4))
    else -- tall, ready: a stalk with leaves and a heavy ear
      p:rect(7, 2, 2, 10, C.leafDark)
      p:ellipse(4, 5, 2, 1, C.leaf)
      p:ellipse(12, 4, 2, 1, C.sprout)
      p:ellipse(4, 8, 2, 1, C.sprout)
      p:rect(9, 6, 3, 4, look.fruit)
      p:px(9, 6, shade(look.fruit, 1.4))
    end
    p:outline(C.outline)
  end
end

for id, look in pairs(CROP_LOOKS) do
  P[id] = laterCrop(look)
  P["icon_seed_" .. id] = function(p)
    p:ellipse(6, 7, 4, 4, look.fruit)
    p:rect(5, 1, 2, 3, C.leaf)
    p:px(5, 6, shade(look.fruit, 1.4))
    p:outline(C.outline)
  end
end

-- The "thirsty" droplet over a dry crop (#20): a blue drop with a dark edge, drawn over the graded world.
function P.cue_droplet(p)
  p:px(3, 1, C.waterLight)
  p:rect(2, 2, 3, 2, C.waterLight)
  p:rect(1, 4, 5, 3, C.water)
  p:rect(2, 7, 3, 1, C.water)
  p:px(2, 5, C.white)
  p:outline(C.outline)
end

-- The "ready to harvest" sparkle (#20), two twinkle frames: a small plus, then a bigger four-point star.
function P.cue_ready(p, _, _, variant)
  if variant == 1 then
    p:rect(3, 2, 1, 3, C.sparkle)
    p:rect(2, 3, 3, 1, C.sparkle)
  else
    p:rect(3, 0, 1, 7, C.sparkle)
    p:rect(0, 3, 7, 1, C.sparkle)
    p:rect(2, 2, 3, 3, C.white)
  end
  p:outline(C.sparkleEdge)
end

-- The homesteader: a big-headed chibi built from shaded parts (src/render/character.lua).
function P.homesteader(p)
  Character.paint(p, Character.outfits.starter, C.shadow)
end

local CAT_FUR = { 0.78, 0.52, 0.28 }
local CAT_DARK = { 0.55, 0.34, 0.18 }

-- The cat, 14x10, sitting (facing right) and curled up napping.
function P.cat(p)
  p:ellipse(7, 9, 5, 1, C.shadow)
  p:rect(3, 4, 7, 5, CAT_FUR) -- body
  p:rect(3, 6, 7, 1, CAT_DARK)
  p:rect(9, 1, 4, 4, CAT_FUR) -- head
  p:px(9, 0, CAT_DARK) -- ears
  p:px(12, 0, CAT_DARK)
  p:px(11, 2, C.tire) -- eye
  p:rect(0, 3, 3, 2, CAT_DARK) -- tail
  p:px(0, 2, CAT_DARK)
  p:rect(4, 8, 2, 1, C.white) -- paws
  p:rect(8, 8, 2, 1, C.white)
end

function P.cat_nap(p)
  p:ellipse(7, 9, 6, 1, C.shadow)
  p:ellipse(7, 6, 6, 3, CAT_FUR)
  p:rect(2, 5, 9, 1, CAT_DARK)
  p:rect(9, 4, 4, 3, CAT_FUR) -- head tucked in
  p:px(9, 3, CAT_DARK)
  p:px(12, 3, CAT_DARK)
  p:rect(10, 5, 2, 1, C.tire) -- closed eye
  p:rect(1, 7, 4, 1, CAT_DARK) -- tail wrapped round
end

local DOG_FUR = { 0.62, 0.45, 0.28 }
local DOG_DARK = { 0.38, 0.26, 0.15 }

-- The farm dog, 16x11, sitting up (facing right) and curled up asleep.
function P.dog(p)
  p:ellipse(8, 10, 6, 1, C.shadow)
  p:rect(3, 4, 8, 6, DOG_FUR) -- body
  p:rect(3, 7, 8, 1, DOG_DARK)
  p:rect(10, 1, 5, 5, DOG_FUR) -- head
  p:rect(14, 3, 2, 2, DOG_DARK) -- snout
  p:rect(10, 0, 2, 3, DOG_DARK) -- ear
  p:px(13, 2, C.tire) -- eye
  p:rect(0, 4, 3, 2, DOG_FUR) -- tail
  p:rect(4, 9, 2, 1, C.white) -- paws
  p:rect(9, 9, 2, 1, C.white)
end

function P.dog_nap(p)
  p:ellipse(8, 10, 7, 1, C.shadow)
  p:ellipse(8, 7, 7, 3, DOG_FUR)
  p:rect(2, 6, 11, 1, DOG_DARK)
  p:rect(11, 5, 4, 4, DOG_FUR) -- head on its paws
  p:rect(11, 4, 2, 2, DOG_DARK) -- ear
  p:rect(13, 6, 2, 1, C.tire) -- closed eye
  p:rect(1, 8, 4, 1, DOG_DARK) -- tail curled round
end

-- Icons ---------------------------------------------------------------------------------

function P.icon_dog(p)
  p:rect(2, 4, 8, 7, DOG_FUR)
  p:rect(1, 2, 2, 5, DOG_DARK)
  p:rect(9, 2, 2, 5, DOG_DARK)
  p:px(4, 6, C.tire)
  p:px(7, 6, C.tire)
  p:rect(5, 8, 2, 2, DOG_DARK)
  p:px(5, 10, C.heart)
end

function P.icon_lantern(p)
  p:rect(5, 1, 2, 1, C.metal) -- the handle
  p:rect(4, 2, 4, 1, C.metal)
  p:rect(3, 3, 6, 6, C.glass) -- the glass
  p:rect(5, 4, 2, 3, { 1.0, 0.85, 0.35 }) -- the flame
  p:rect(3, 9, 6, 2, C.metal) -- the base
end

function P.icon_cat(p)
  p:rect(2, 4, 8, 7, CAT_FUR)
  p:rect(2, 1, 2, 3, CAT_FUR)
  p:rect(8, 1, 2, 3, CAT_FUR)
  p:px(3, 2, C.heart)
  p:px(8, 2, C.heart)
  p:px(4, 6, C.tire)
  p:px(7, 6, C.tire)
  p:px(5, 8, C.heart)
  p:px(6, 8, C.heart)
  p:rect(1, 7, 1, 1, C.white)
  p:rect(10, 7, 1, 1, C.white)
end

function P.icon_money(p)
  p:circle(6, 6, 5, C.gold)
  p:circle(6, 6, 3, { 0.80, 0.62, 0.20 })
  p:rect(5, 4, 2, 5, C.gold)
end

function P.icon_food(p)
  p:ellipse(6, 7, 5, 3, { 0.62, 0.45, 0.30 })
  p:ellipse(6, 6, 4, 2, { 0.78, 0.60, 0.40 })
  p:px(4, 5, C.white)
  p:outline(C.outline)
end

function P.icon_water(p)
  p:circle(6, 8, 3, C.water)
  p:rect(5, 3, 2, 3, C.water)
  p:px(6, 2, C.water)
  p:px(5, 7, C.white)
end

function P.icon_wood(p)
  p:rect(1, 4, 10, 4, C.bark)
  p:rect(1, 4, 10, 1, C.barkLight)
  p:circle(10, 6, 2, C.barkLight)
  p:px(10, 6, C.barkDark)
end

function P.icon_stone(p)
  p:ellipse(6, 7, 5, 3, C.stoneDark)
  p:ellipse(6, 6, 4, 3, C.stone)
  p:px(4, 5, C.stoneLight)
  p:outline(C.outline)
end

function P.icon_scrap(p)
  p:rect(2, 5, 6, 4, C.rust)
  p:rect(5, 2, 5, 4, C.metal)
  p:px(6, 3, C.stoneLight)
  p:outline(C.outline)
end

function P.icon_seed_radish(p)
  p:ellipse(6, 7, 4, 4, C.radish)
  p:rect(5, 1, 2, 3, C.leaf)
  p:px(5, 6, C.white)
  p:outline(C.outline)
end

function P.icon_seed_potato(p)
  p:ellipse(6, 7, 5, 4, { 0.72, 0.56, 0.36 })
  p:px(4, 6, { 0.52, 0.38, 0.24 })
  p:px(8, 8, { 0.52, 0.38, 0.24 })
  p:outline(C.outline)
end

function P.icon_heart(p)
  p:circle(4, 5, 3, C.heart)
  p:circle(8, 5, 3, C.heart)
  for row = 0, 4 do
    p:rect(2 + row, 6 + row, 9 - row * 2, 1, C.heart)
  end
  p:px(3, 4, C.white)
end

function P.folding_panel(p)
  p:ellipse(8, 14, 7, 1, C.shadow)
  p:rect(5, 11, 1, 3, C.metal) -- stand
  p:rect(10, 11, 1, 3, C.metal)
  p:rect(1, 3, 14, 9, C.metal) -- frame
  p:rect(2, 4, 12, 7, { 0.16, 0.24, 0.42 }) -- cells
  for x = 5, 11, 3 do
    p:rect(x, 4, 1, 7, { 0.30, 0.40, 0.60 })
  end
  p:rect(2, 7, 12, 1, { 0.30, 0.40, 0.60 })
  p:px(3, 5, C.white)
end

function P.smoker(p)
  p:ellipse(8, 22, 6, 2, C.shadow)
  p:rect(3, 8, 10, 13, { 0.25, 0.25, 0.27 }) -- barrel body
  p:rect(3, 8, 1, 13, { 0.36, 0.36, 0.38 })
  p:rect(3, 12, 10, 1, { 0.18, 0.18, 0.2 })
  p:rect(3, 17, 10, 1, { 0.18, 0.18, 0.2 })
  p:rect(2, 6, 12, 2, { 0.32, 0.32, 0.34 }) -- lid
  p:rect(7, 2, 2, 4, { 0.22, 0.22, 0.24 }) -- chimney
  p:rect(6, 14, 4, 2, C.rust) -- firebox door
  p:px(4, 20, C.metal)
  p:px(11, 20, C.metal)
end

-- Heat & wood ------------------------------------------------------------------------

local FLAME = { 0.98, 0.62, 0.20 }
local FLAME_HOT = { 1.00, 0.88, 0.45 }
local SPLIT = { 0.78, 0.62, 0.40 } -- fresh-cut wood face

function P.campfire(p)
  p:ellipse(8, 12, 7, 3, C.shadow)
  for _, s in ipairs({ { 2, 11 }, { 5, 13 }, { 9, 13 }, { 12, 11 }, { 4, 9 }, { 11, 9 } }) do
    p:rect(s[1], s[2], 3, 2, C.stoneDark)
    p:px(s[1], s[2], C.stone)
  end
  p:rect(4, 10, 8, 2, C.bark) -- logs
  p:rect(6, 9, 4, 1, C.barkDark)
  p:rect(6, 5, 4, 5, FLAME)
  p:rect(7, 3, 2, 3, FLAME)
  p:rect(7, 7, 2, 3, FLAME_HOT)
end

function P.woodshed(p)
  p:ellipse(16, 22, 15, 2, C.shadow)
  p:rect(1, 4, 30, 3, C.barkDark) -- roof
  p:rect(0, 3, 32, 1, C.bark)
  p:rect(2, 7, 2, 14, C.barkDark) -- posts
  p:rect(28, 7, 2, 14, C.barkDark)
  for row = 0, 3 do
    for col = 0, 5 do
      local x, y = 5 + col * 4 + (row % 2) * 2, 9 + row * 3
      if x < 27 then
        p:rect(x, y, 3, 3, C.bark)
        p:px(x + 1, y + 1, SPLIT)
      end
    end
  end
end

-- Shelter ladder (D82) ------------------------------------------------------------------

local CANVAS = { 0.74, 0.70, 0.55 }
local CANVAS_DARK = { 0.58, 0.54, 0.40 }

function P.camp(p) -- 32x32: a canvas lean-to with a bedroll under it
  p:ellipse(16, 29, 15, 3, C.shadow)
  p:rect(2, 24, 28, 3, CANVAS_DARK)
  for row = 0, 12 do -- sloped canvas roof
    local inset = 13 - row
    p:rect(3 + inset, 8 + row, 26 - inset * 2 + 1, 1, row % 4 == 3 and CANVAS_DARK or CANVAS)
  end
  p:rect(15, 5, 2, 20, C.barkDark) -- ridge pole
  p:rect(7, 21, 18, 4, C.shirtDark) -- bedroll in the doorway
  p:rect(7, 21, 18, 1, C.shirt)
  p:rect(10, 23, 12, 2, C.barkDark)
  p:px(14, 10, CANVAS_DARK)
  p:px(18, 14, CANVAS_DARK)
end

function P.shack(p) -- 48x32: a small plank shack with a tin roof, a window and a stove pipe
  p:ellipse(24, 30, 23, 3, C.shadow)
  p:rect(2, 12, 44, 17, C.barkLight) -- plank walls
  for x = 2, 44, 4 do
    p:rect(x, 12, 1, 17, C.bark)
  end
  p:rect(0, 7, 48, 5, C.metal) -- tin roof
  p:rect(0, 7, 48, 1, { 0.70, 0.72, 0.74 })
  p:rect(0, 11, 48, 1, C.barkDark)
  p:rect(36, 1, 3, 8, { 0.20, 0.20, 0.22 }) -- stove pipe
  p:rect(7, 17, 9, 7, C.barkDark) -- window
  p:rect(8, 18, 7, 5, { 0.86, 0.78, 0.50 }) -- lit glass
  p:rect(11, 18, 1, 5, C.barkDark)
  p:rect(26, 15, 9, 14, C.barkDark) -- door
  p:rect(27, 16, 7, 12, C.bark)
  p:px(32, 23, C.metal)
end

function P.icon_camp(p)
  for row = 0, 6 do
    local inset = 6 - row
    p:rect(1 + inset, 3 + row, 10 - inset * 2 + 1, 1, CANVAS)
  end
  p:rect(5, 9, 3, 1, C.shirtDark)
end

function P.icon_shack(p)
  p:rect(0, 3, 12, 2, C.metal)
  p:rect(1, 5, 10, 6, C.barkLight)
  p:rect(2, 6, 3, 3, { 0.86, 0.78, 0.50 })
  p:rect(7, 7, 3, 4, C.barkDark)
end

function P.wood_stove(p)
  p:ellipse(8, 22, 7, 2, C.shadow)
  p:rect(11, 0, 2, 9, { 0.20, 0.20, 0.22 }) -- stove pipe
  p:rect(2, 9, 12, 11, { 0.16, 0.16, 0.18 }) -- body
  p:rect(2, 9, 12, 1, { 0.30, 0.30, 0.32 })
  p:rect(5, 13, 6, 4, { 0.10, 0.10, 0.11 }) -- door
  p:rect(6, 14, 4, 2, FLAME)
  p:rect(3, 20, 2, 2, { 0.16, 0.16, 0.18 }) -- feet
  p:rect(11, 20, 2, 2, { 0.16, 0.16, 0.18 })
end

function P.icon_cold(p)
  local ice = { 0.75, 0.88, 1.0 }
  p:rect(5, 1, 1, 10, ice)
  p:rect(1, 5, 10, 1, ice)
  for d = 2, 8 do
    p:px(d + 1, d, ice)
    p:px(10 - d, d, ice)
  end
end

function P.icon_axe(p)
  p:rect(5, 2, 1, 9, C.barkLight)
  p:rect(2, 2, 4, 3, C.metal)
  p:px(2, 2, { 0.8, 0.82, 0.84 })
end

function P.icon_campfire(p)
  p:rect(2, 8, 8, 2, C.bark)
  p:rect(4, 4, 4, 4, FLAME)
  p:rect(5, 2, 2, 3, FLAME)
  p:rect(5, 6, 2, 2, FLAME_HOT)
end

function P.icon_woodshed(p)
  p:rect(0, 2, 12, 2, C.barkDark)
  p:rect(1, 4, 1, 7, C.barkDark)
  p:rect(10, 4, 1, 7, C.barkDark)
  p:rect(3, 6, 6, 5, C.bark)
  p:px(4, 7, SPLIT)
  p:px(7, 9, SPLIT)
end

function P.icon_wood_stove(p)
  p:rect(8, 0, 2, 4, { 0.25, 0.25, 0.27 })
  p:rect(1, 4, 10, 7, { 0.20, 0.20, 0.22 })
  p:rect(4, 6, 4, 3, FLAME)
end

-- Power network (GDD §7.5) ---------------------------------------------------------------------

local CELL = { 0.16, 0.24, 0.42 }
local CELL_LINE = { 0.30, 0.40, 0.60 }
local CASE = { 0.28, 0.30, 0.32 }
local CASE_LIGHT = { 0.42, 0.45, 0.48 }

function P.solar_array(p)
  p:ellipse(16, 14, 15, 1, C.shadow)
  p:rect(6, 12, 2, 3, C.metal) -- legs
  p:rect(24, 12, 2, 3, C.metal)
  p:rect(1, 1, 30, 12, C.metal) -- frame
  p:rect(2, 2, 28, 10, CELL)
  for x = 7, 25, 5 do
    p:rect(x, 2, 1, 10, CELL_LINE)
  end
  p:rect(2, 6, 28, 1, CELL_LINE)
  p:rect(3, 3, 4, 1, C.white)
end

function P.battery_bank(p)
  p:ellipse(8, 15, 7, 1, C.shadow)
  p:rect(1, 4, 14, 11, CASE)
  p:rect(1, 4, 14, 1, CASE_LIGHT)
  p:rect(3, 2, 3, 2, C.metal) -- terminals
  p:rect(10, 2, 3, 2, C.metal)
  for n = 0, 3 do -- charge lamps
    p:rect(3 + n * 3, 8, 2, 4, n < 3 and { 0.45, 0.82, 0.42 } or { 0.20, 0.30, 0.20 })
  end
end

function P.wind_turbine(p)
  p:ellipse(8, 30, 5, 1, C.shadow)
  p:rect(7, 11, 2, 19, C.white) -- tower
  p:rect(6, 28, 4, 3, C.metal)
  p:rect(6, 9, 4, 3, C.metal) -- nacelle
  p:rect(7, 1, 2, 8, C.white) -- blades
  p:rect(2, 12, 5, 2, C.white)
  p:rect(9, 12, 6, 2, C.white)
  p:circle(8, 10, 1, C.stoneDark)
end

function P.micro_hydro(p)
  p:ellipse(8, 14, 7, 1, C.shadow)
  p:rect(2, 5, 12, 9, C.rust) -- housing
  p:rect(2, 5, 12, 1, C.barkLight)
  p:circle(8, 10, 3, C.metal) -- wheel
  p:circle(8, 10, 1, C.stoneDark)
  p:rect(0, 12, 4, 3, C.water) -- water in
  p:rect(12, 1, 2, 4, C.metal) -- cable post
end

function P.generator(p)
  p:ellipse(8, 15, 7, 1, C.shadow)
  p:rect(1, 5, 14, 9, { 0.78, 0.30, 0.20 }) -- red frame
  p:rect(1, 5, 14, 1, { 0.92, 0.50, 0.38 })
  p:rect(3, 7, 6, 4, CASE) -- engine
  p:rect(10, 7, 4, 3, { 0.12, 0.12, 0.13 }) -- tank
  p:rect(11, 6, 2, 1, C.gold)
  p:rect(2, 14, 2, 2, C.tire)
  p:rect(12, 14, 2, 2, C.tire)
  p:rect(5, 2, 2, 3, C.metal) -- exhaust
end

function P.electric_heater(p)
  p:ellipse(8, 15, 6, 1, C.shadow)
  p:rect(2, 4, 12, 11, CASE)
  p:rect(2, 4, 12, 1, CASE_LIGHT)
  for n = 0, 3 do -- glowing bars
    p:rect(4, 6 + n * 2, 8, 1, FLAME)
  end
  p:px(12, 13, C.heart)
end

function P.lamp(p)
  p:ellipse(8, 15, 4, 1, C.shadow)
  p:rect(7, 5, 2, 10, C.metal) -- stand
  p:rect(5, 14, 6, 2, CASE)
  p:rect(4, 1, 8, 4, C.stoneLight) -- shade
  p:rect(5, 5, 6, 1, FLAME_HOT)
end

function P.chest_freezer(p)
  p:ellipse(8, 15, 7, 1, C.shadow)
  p:rect(1, 6, 14, 9, C.white)
  p:rect(1, 4, 14, 3, { 0.80, 0.84, 0.86 }) -- lid
  p:rect(1, 7, 14, 1, C.metal)
  p:rect(6, 5, 4, 1, C.stoneDark) -- handle
  p:px(13, 10, { 0.45, 0.82, 0.42 })
end

function P.icon_wind_turbine(p)
  p:rect(5, 4, 1, 8, C.white)
  p:rect(5, 0, 1, 4, C.white)
  p:rect(1, 4, 4, 1, C.white)
  p:rect(6, 4, 4, 1, C.white)
end

function P.icon_micro_hydro(p)
  p:circle(6, 6, 4, C.metal)
  p:circle(6, 6, 1, C.stoneDark)
  p:rect(0, 9, 5, 2, C.water)
end

function P.icon_generator(p)
  p:rect(1, 3, 10, 7, { 0.78, 0.30, 0.20 })
  p:rect(2, 4, 4, 4, CASE)
  p:rect(7, 4, 3, 3, { 0.12, 0.12, 0.13 })
  p:rect(3, 10, 2, 1, C.tire)
  p:rect(8, 10, 2, 1, C.tire)
end

function P.icon_electric_heater(p)
  p:rect(1, 2, 10, 9, CASE)
  for n = 0, 2 do
    p:rect(3, 4 + n * 2, 6, 1, FLAME)
  end
end

function P.icon_lamp(p)
  p:rect(5, 4, 2, 7, C.metal)
  p:rect(3, 1, 6, 3, C.stoneLight)
  p:rect(4, 4, 4, 1, FLAME_HOT)
  p:rect(3, 10, 6, 1, CASE)
end

function P.icon_chest_freezer(p)
  p:rect(1, 5, 10, 6, C.white)
  p:rect(1, 3, 10, 3, { 0.80, 0.84, 0.86 })
  p:rect(5, 4, 2, 1, C.stoneDark)
end

function P.icon_fuel(p)
  p:rect(2, 3, 7, 8, { 0.78, 0.30, 0.20 })
  p:rect(2, 3, 7, 1, { 0.92, 0.50, 0.38 })
  p:rect(7, 1, 3, 2, C.metal)
  p:rect(4, 6, 3, 2, C.gold)
end

function P.bobber(p)
  p:rect(3, 0, 1, 3, C.white)
  p:circle(3, 5, 3, C.heart)
  p:rect(0, 5, 7, 4, C.white)
  p:ellipse(3, 8, 3, 1, C.white)
end

function P.icon_battery(p)
  p:rect(1, 3, 9, 6, { 0.85, 0.85, 0.82 })
  p:rect(10, 5, 1, 2, { 0.85, 0.85, 0.82 })
  p:rect(2, 4, 7, 4, { 0.12, 0.12, 0.13 })
  p:rect(2, 4, 4, 4, { 0.45, 0.82, 0.42 })
end

-- Weather glyphs for the top-bar weather chip (D112): each a different silhouette, so no kind is told by colour alone.
function P.icon_wx_clear(p)
  p:circle(6, 6, 3, C.sparkle)
  for _, r in ipairs({ { 6, 0 }, { 6, 11 }, { 0, 6 }, { 11, 6 }, { 2, 2 }, { 9, 2 }, { 2, 9 }, { 9, 9 } }) do
    p:px(r[1], r[2], C.sparkle)
  end
end

function P.icon_wx_cloudy(p)
  p:circle(4, 7, 3, C.stoneLight)
  p:circle(8, 6, 3, C.stoneLight)
  p:rect(2, 7, 9, 3, C.stoneLight)
  p:rect(2, 10, 9, 1, C.stone)
end

function P.icon_wx_rain(p)
  p:circle(4, 4, 3, C.stone)
  p:circle(8, 3, 3, C.stone)
  p:rect(2, 4, 9, 2, C.stone)
  for _, x in ipairs({ 3, 6, 9 }) do
    p:rect(x, 8, 1, 2, C.waterLight)
    p:px(x - 1, 11, C.waterLight)
  end
end

function P.icon_wx_windy(p)
  p:rect(1, 3, 8, 1, C.white)
  p:rect(9, 2, 2, 1, C.white)
  p:px(10, 3, C.white)
  p:rect(1, 6, 10, 1, C.white)
  p:rect(1, 9, 6, 1, C.white)
  p:rect(7, 9, 2, 1, C.white)
  p:px(8, 8, C.white)
end

function P.icon_wx_storm(p)
  p:circle(4, 3, 3, C.stoneDark)
  p:circle(8, 3, 3, C.stoneDark)
  p:rect(2, 3, 9, 2, C.stoneDark)
  p:rect(6, 6, 2, 2, C.sparkle)
  p:rect(4, 8, 3, 1, C.sparkle)
  p:rect(5, 9, 2, 2, C.sparkle)
end

function P.icon_crate(p)
  p:rect(1, 3, 10, 8, C.barkLight)
  p:rect(1, 3, 10, 1, C.bark)
  p:rect(1, 7, 10, 1, C.bark)
  p:rect(1, 10, 10, 1, C.barkDark)
  p:rect(3, 1, 2, 2, C.radish)
  p:rect(7, 1, 2, 2, C.leaf)
end

function P.icon_rod(p)
  for n = 0, 9 do
    p:px(1 + n, 10 - n, C.barkLight)
  end
  p:px(2, 9, C.barkDark)
  p:circle(3, 8, 1, C.metal)
  for n = 0, 6 do
    p:px(10, 1 + n, { 0.9, 0.9, 0.9, 0.7 })
  end
end

function P.icon_smoked_fish(p)
  p:ellipse(5, 6, 4, 2, { 0.62, 0.38, 0.20 })
  p:rect(9, 4, 2, 5, { 0.52, 0.30, 0.16 })
  p:px(3, 5, { 0.15, 0.1, 0.05 })
  p:px(6, 1, { 0.7, 0.7, 0.7, 0.7 })
  p:px(7, 0, { 0.7, 0.7, 0.7, 0.5 })
end

function P.icon_bait(p)
  for n, c in ipairs({ { 2, 8 }, { 3, 7 }, { 4, 7 }, { 5, 6 }, { 6, 6 }, { 7, 5 }, { 8, 5 }, { 9, 4 } }) do
    p:px(c[1], c[2], n % 2 == 0 and { 0.85, 0.50, 0.50 } or { 0.75, 0.42, 0.42 })
  end
end

function P.icon_smoker(p)
  p:rect(3, 4, 6, 7, { 0.25, 0.25, 0.27 })
  p:rect(2, 3, 8, 1, { 0.36, 0.36, 0.38 })
  p:rect(5, 1, 2, 2, { 0.22, 0.22, 0.24 })
  p:rect(5, 7, 2, 2, C.rust)
end

function P.icon_folding_panel(p)
  p:rect(1, 2, 10, 7, C.metal)
  p:rect(2, 3, 8, 5, { 0.16, 0.24, 0.42 })
  p:rect(5, 3, 1, 5, { 0.30, 0.40, 0.60 })
  p:rect(3, 9, 1, 2, C.metal)
  p:rect(8, 9, 1, 2, C.metal)
end

function P.icon_unknown(p)
  p:ellipse(5, 6, 4, 2, { 0.35, 0.37, 0.36 })
  p:rect(9, 4, 2, 5, { 0.30, 0.32, 0.31 })
end

-- A blank journal stamp: a note not written yet.
function P.icon_note_blank(p)
  p:rect(2, 2, 8, 8, { 0.30, 0.32, 0.30 })
  p:rect(3, 3, 6, 6, { 0.22, 0.24, 0.22 })
  p:rect(5, 4, 2, 1, { 0.40, 0.42, 0.40 })
  p:rect(6, 5, 1, 2, { 0.40, 0.42, 0.40 })
  p:px(5, 8, { 0.40, 0.42, 0.40 })
end

-- Water ladder (GDD §5.3): well, hand pump, cistern, solar pump, drip line.
local WATER_DEEP = { 0.18, 0.34, 0.50 }
local HOSE = { 0.16, 0.17, 0.18 }

function P.well(p)
  p:ellipse(8, 22, 7, 2, C.shadow)
  p:rect(2, 14, 12, 8, C.stone) -- stone ring
  p:rect(2, 14, 12, 1, C.stoneLight)
  p:rect(4, 15, 8, 3, WATER_DEEP) -- the dark water inside
  p:rect(4, 15, 8, 1, C.water)
  p:rect(2, 20, 12, 2, C.stoneDark)
  p:rect(2, 4, 2, 11, C.bark) -- posts
  p:rect(12, 4, 2, 11, C.bark)
  p:rect(1, 2, 14, 3, C.rust) -- little roof
  p:rect(1, 2, 14, 1, C.barkLight)
  p:rect(4, 7, 8, 1, C.barkLight) -- windlass with its rope
  p:rect(8, 8, 1, 6, C.pebble)
end

function P.hand_pump(p)
  p:ellipse(8, 15, 6, 1, C.shadow)
  p:rect(3, 12, 10, 3, C.stoneDark) -- stone base
  p:rect(3, 12, 10, 1, C.stone)
  p:rect(7, 4, 3, 8, C.metal) -- body
  p:rect(7, 4, 1, 8, C.stoneLight)
  p:rect(3, 3, 8, 2, CASE) -- handle
  p:rect(2, 2, 2, 3, CASE_LIGHT)
  p:rect(10, 7, 4, 2, C.metal) -- spout
  p:px(13, 9, C.water)
end

function P.cistern(p)
  p:ellipse(16, 15, 14, 1, C.shadow)
  p:rect(2, 4, 28, 11, { 0.48, 0.52, 0.55 }) -- tank
  p:rect(2, 4, 28, 2, { 0.64, 0.68, 0.70 })
  for x = 7, 25, 6 do -- ribs
    p:rect(x, 6, 1, 9, { 0.36, 0.40, 0.43 })
  end
  p:rect(12, 2, 8, 2, C.metal) -- lid hatch
  p:rect(26, 10, 4, 2, C.metal) -- tap
  p:px(29, 12, C.water)
end

function P.dc_pump(p)
  p:ellipse(8, 15, 6, 1, C.shadow)
  p:rect(2, 7, 9, 8, { 0.22, 0.38, 0.62 }) -- motor housing
  p:rect(2, 7, 9, 1, { 0.40, 0.56, 0.80 })
  p:rect(4, 9, 5, 2, CELL_LINE) -- little solar cell
  p:rect(11, 9, 3, 3, C.metal) -- pump head
  p:rect(13, 4, 2, 6, C.metal) -- riser pipe
  p:rect(5, 4, 3, 3, CASE) -- junction box
  p:px(6, 5, { 0.45, 0.82, 0.42 })
end

function P.drip_line(p)
  p:rect(1, 8, 14, 1, HOSE) -- the hose
  p:rect(7, 2, 1, 7, HOSE)
  p:rect(6, 9, 3, 2, C.metal) -- feed fitting
  for _, e in ipairs({ { 3, 9 }, { 11, 9 }, { 7, 3 }, { 3, 7 }, { 12, 7 } }) do -- emitters
    p:px(e[1], e[2], C.water)
  end
end

function P.sprinkler(p)
  p:rect(7, 7, 2, 5, C.metal) -- riser
  p:rect(5, 12, 6, 2, C.metal) -- base
  p:rect(6, 5, 4, 2, HOSE) -- head
  for _, e in ipairs({ { 3, 3 }, { 12, 3 }, { 4, 5 }, { 11, 5 }, { 2, 6 }, { 13, 6 }, { 8, 2 }, { 6, 3 }, { 10, 3 } }) do -- spray
    p:px(e[1], e[2], C.water)
  end
end

-- Chickens (GDD §7.7, D63) ----------------------------------------------------------------

local HEN_BODY = { 0.80, 0.50, 0.28 }
local HEN_DARK = { 0.60, 0.34, 0.18 }
local HEN_COMB = { 0.84, 0.22, 0.22 }
local COOP_WALL = { 0.72, 0.28, 0.24 }
local COOP_WALL_DARK = { 0.56, 0.20, 0.18 }
local COOP_ROOF = { 0.38, 0.30, 0.26 }
local EGG_SHELL = { 0.96, 0.92, 0.82 }

-- A hen, 10x9, facing right.
function P.hen(p)
  p:ellipse(5, 8, 4, 1, C.shadow)
  p:rect(1, 3, 6, 4, HEN_BODY) -- body
  p:rect(1, 5, 5, 1, HEN_DARK) -- wing
  p:rect(0, 2, 2, 2, HEN_DARK) -- tail
  p:rect(6, 1, 3, 3, HEN_BODY) -- head
  p:px(7, 0, HEN_COMB)
  p:px(8, 0, HEN_COMB)
  p:px(9, 2, C.gold) -- beak
  p:px(7, 2, C.tire) -- eye
  p:px(8, 4, HEN_COMB) -- wattle
  p:px(3, 7, C.gold) -- legs
  p:px(5, 7, C.gold)
end

-- The coop (32x24): a small red henhouse on stilts with a ramp, nest box on the side and a pitched roof.
function P.chicken_coop(p)
  p:ellipse(16, 22, 15, 2, C.shadow)
  p:rect(4, 8, 22, 12, COOP_WALL) -- walls
  for x = 6, 24, 4 do
    p:rect(x, 8, 1, 12, COOP_WALL_DARK) -- boards
  end
  p:rect(3, 6, 24, 2, COOP_ROOF) -- roof
  p:rect(5, 4, 20, 2, COOP_ROOF)
  p:rect(8, 2, 14, 2, COOP_ROOF)
  p:rect(5, 20, 2, 2, C.barkDark) -- stilts
  p:rect(23, 20, 2, 2, C.barkDark)
  p:rect(12, 12, 6, 8, C.barkDark) -- pop door
  p:rect(13, 13, 4, 7, { 0.12, 0.10, 0.09 })
  p:rect(9, 19, 12, 1, C.barkLight) -- ramp
  p:rect(8, 20, 3, 1, C.bark)
  p:rect(26, 11, 5, 6, C.barkLight) -- nest box
  p:rect(26, 10, 5, 1, C.bark)
  p:rect(27, 13, 3, 3, C.barkDark)
  p:px(28, 14, EGG_SHELL)
end

function P.icon_hen(p)
  p:rect(2, 4, 6, 5, HEN_BODY)
  p:rect(2, 7, 5, 1, HEN_DARK)
  p:rect(1, 3, 2, 2, HEN_DARK)
  p:rect(6, 2, 3, 3, HEN_BODY)
  p:px(7, 1, HEN_COMB)
  p:px(8, 1, HEN_COMB)
  p:px(9, 3, C.gold)
  p:px(7, 3, C.tire)
  p:px(3, 9, C.gold)
  p:px(6, 9, C.gold)
end

function P.icon_egg(p)
  p:ellipse(6, 6, 3, 4, EGG_SHELL)
  p:px(5, 4, C.white)
  p:rect(4, 8, 4, 1, { 0.82, 0.76, 0.64 })
end

function P.icon_chicken_coop(p)
  p:rect(1, 4, 10, 6, COOP_WALL)
  p:rect(0, 3, 12, 1, COOP_ROOF)
  p:rect(2, 1, 8, 2, COOP_ROOF)
  p:rect(4, 6, 3, 4, C.barkDark)
  p:rect(8, 7, 2, 2, EGG_SHELL)
end

function P.icon_chicken_feed(p)
  p:rect(2, 3, 8, 8, C.barkLight) -- sack
  p:rect(3, 2, 6, 1, C.bark)
  p:rect(4, 1, 4, 1, C.bark)
  for _, g in ipairs({ { 4, 5 }, { 6, 6 }, { 7, 8 }, { 4, 8 } }) do
    p:px(g[1], g[2], C.gold) -- grain
  end
end

function P.icon_chicken_fence(p)
  p:rect(0, 8, 12, 1, C.metal)
  p:rect(0, 4, 12, 1, C.metal)
  for x = 1, 10, 3 do
    p:rect(x, 2, 1, 9, C.bark)
  end
  p:px(5, 1, C.gold) -- the light
end

-- Goats (GDD §7.7, D71) -------------------------------------------------------------------

local GOAT_COAT = { 0.88, 0.85, 0.78 }
local GOAT_DARK = { 0.62, 0.58, 0.50 }
local GOAT_HORN = { 0.50, 0.44, 0.34 }
local PEN_WALL = { 0.46, 0.34, 0.22 }
local PEN_WALL_DARK = { 0.34, 0.25, 0.16 }
local PEN_ROOF = { 0.36, 0.40, 0.42 }
local HAY_GOLD = { 0.88, 0.76, 0.36 }
local HAY_DARK = { 0.72, 0.60, 0.26 }
local MILK_WHITE = { 0.96, 0.96, 0.94 }
local CHEESE_YELLOW = { 0.95, 0.80, 0.30 }
local CHEESE_DARK = { 0.80, 0.62, 0.20 }

-- A goat, 14x11, facing right: stocky body, horns, a beard.
function P.goat(p)
  p:ellipse(7, 10, 6, 1, C.shadow)
  p:rect(2, 4, 8, 4, GOAT_COAT) -- body
  p:rect(2, 7, 8, 1, GOAT_DARK) -- belly
  p:rect(1, 4, 1, 2, GOAT_DARK) -- tail
  p:rect(9, 2, 3, 4, GOAT_COAT) -- neck and head
  p:rect(11, 3, 2, 2, GOAT_COAT) -- muzzle
  p:px(12, 5, GOAT_DARK) -- beard
  p:px(10, 0, GOAT_HORN) -- horns
  p:px(11, 1, GOAT_HORN)
  p:px(9, 1, GOAT_HORN)
  p:px(11, 3, C.tire) -- eye
  p:rect(3, 8, 1, 2, GOAT_DARK) -- legs
  p:rect(5, 8, 1, 2, GOAT_DARK)
  p:rect(8, 8, 1, 2, GOAT_DARK)
  p:rect(10, 8, 1, 2, GOAT_DARK)
end

-- The goat pen (32x32): a rail fence round a yard with a small shed roof on the back.
function P.goat_pen(p)
  p:ellipse(16, 30, 15, 2, C.shadow)
  p:rect(2, 12, 28, 14, { 0.50, 0.40, 0.28 }) -- trodden yard
  p:rect(5, 3, 22, 8, PEN_WALL) -- shed
  for x = 7, 25, 4 do
    p:rect(x, 3, 1, 8, PEN_WALL_DARK)
  end
  p:rect(3, 1, 26, 2, PEN_ROOF) -- roof
  p:rect(5, 0, 22, 1, PEN_ROOF)
  p:rect(13, 6, 6, 5, C.barkDark) -- shed door
  for x = 1, 29, 7 do
    p:rect(x, 14, 2, 14, C.bark) -- fence posts
  end
  p:rect(1, 17, 30, 1, C.barkLight) -- rails
  p:rect(1, 23, 30, 1, C.barkLight)
  p:rect(12, 14, 1, 14, C.barkDark) -- gate posts
  p:rect(19, 14, 1, 14, C.barkDark)
  p:rect(24, 24, 5, 3, HAY_GOLD) -- hay in the corner
  p:rect(25, 23, 3, 1, HAY_DARK)
end

-- The cheese press (16x16): a wooden frame with a screw over a wheel of cheese.
function P.cheese_press(p)
  p:ellipse(8, 14, 7, 1, C.shadow)
  p:rect(2, 3, 2, 11, C.bark) -- uprights
  p:rect(12, 3, 2, 11, C.bark)
  p:rect(2, 2, 12, 2, C.barkLight) -- crossbar
  p:rect(7, 4, 2, 5, C.metal) -- screw
  p:rect(5, 9, 6, 1, C.barkDark) -- plate
  p:rect(4, 10, 8, 4, CHEESE_YELLOW) -- the wheel
  p:rect(4, 13, 8, 1, CHEESE_DARK)
  p:px(6, 11, CHEESE_DARK)
  p:px(9, 12, CHEESE_DARK)
end

local COMPOST_DARK = { 0.24, 0.17, 0.11 }
local COMPOST_MID = { 0.36, 0.26, 0.16 }
local COMPOST_PILE = { 0.30, 0.22, 0.14 }

-- The compost bin (16x16): a slatted box of boards with a heap of dark compost over the rim.
function P.compost_bin(p)
  p:ellipse(8, 14, 7, 1, C.shadow)
  p:rect(2, 6, 12, 8, COMPOST_MID) -- the heap, seen over the front boards
  p:rect(4, 4, 8, 3, COMPOST_PILE)
  p:px(6, 3, C.leafLight)
  p:px(9, 4, C.leafLight)
  p:px(7, 5, C.leaf)
  p:rect(2, 7, 12, 7, C.bark) -- front boards
  p:rect(2, 9, 12, 1, C.barkDark)
  p:rect(2, 12, 12, 1, C.barkDark)
  p:rect(2, 6, 2, 8, C.barkLight) -- corner posts
  p:rect(12, 6, 2, 8, C.barkLight)
end

function P.icon_compost_bin(p)
  p:rect(2, 2, 8, 3, COMPOST_PILE)
  p:rect(1, 4, 10, 6, C.bark)
  p:rect(1, 6, 10, 1, C.barkDark)
  p:rect(1, 8, 10, 1, C.barkDark)
  p:px(5, 1, C.leafLight)
end

function P.icon_manure(p)
  p:rect(2, 7, 8, 3, COMPOST_MID) -- a forkful of muck
  p:rect(3, 5, 6, 2, COMPOST_PILE)
  p:rect(4, 3, 3, 2, COMPOST_MID)
  p:px(5, 2, HAY_GOLD)
  p:px(8, 4, HAY_GOLD)
  p:px(2, 6, HAY_GOLD)
end

function P.icon_compost(p)
  p:rect(2, 7, 8, 3, COMPOST_DARK) -- a handful of crumbly compost
  p:rect(3, 5, 6, 2, COMPOST_PILE)
  p:rect(4, 3, 4, 2, COMPOST_DARK)
  p:px(5, 4, C.leafLight)
  p:px(7, 6, C.leaf)
end

function P.icon_goat(p)
  p:rect(2, 4, 7, 4, GOAT_COAT)
  p:rect(2, 7, 7, 1, GOAT_DARK)
  p:rect(8, 2, 3, 4, GOAT_COAT)
  p:px(9, 1, GOAT_HORN)
  p:px(10, 0, GOAT_HORN)
  p:px(10, 3, C.tire)
  p:px(10, 6, GOAT_DARK)
  p:rect(3, 8, 1, 3, GOAT_DARK)
  p:rect(7, 8, 1, 3, GOAT_DARK)
end

function P.icon_milk(p)
  p:rect(3, 3, 6, 8, MILK_WHITE) -- bottle
  p:rect(4, 1, 4, 2, MILK_WHITE)
  p:rect(4, 0, 4, 1, C.water)
  p:rect(3, 6, 6, 2, C.water) -- label
end

function P.icon_hay(p)
  p:rect(1, 4, 10, 7, HAY_GOLD) -- bale
  p:rect(1, 7, 10, 1, HAY_DARK)
  p:rect(4, 4, 1, 7, C.bark) -- twine
  p:rect(8, 4, 1, 7, C.bark)
  p:px(2, 3, HAY_GOLD)
  p:px(6, 3, HAY_GOLD)
  p:px(9, 2, HAY_GOLD)
end

function P.icon_cheese(p)
  p:rect(1, 5, 10, 6, CHEESE_YELLOW) -- wedge-shaped block
  p:rect(1, 9, 10, 2, CHEESE_DARK)
  p:rect(2, 3, 8, 2, CHEESE_YELLOW)
  p:rect(4, 3, 5, 1, CHEESE_DARK)
  p:px(4, 6, CHEESE_DARK) -- holes
  p:px(8, 7, CHEESE_DARK)
end

function P.icon_goat_pen(p)
  p:rect(1, 2, 10, 4, PEN_WALL)
  p:rect(0, 1, 12, 1, PEN_ROOF)
  p:rect(0, 7, 12, 1, C.barkLight)
  p:rect(0, 10, 12, 1, C.barkLight)
  for x = 1, 10, 4 do
    p:rect(x, 6, 1, 5, C.bark)
  end
end

function P.icon_goat_trailer(p)
  p:rect(0, 5, 10, 4, C.truckDark) -- bed
  p:rect(0, 3, 10, 1, C.metal) -- rail
  p:rect(1, 3, 1, 3, C.metal)
  p:rect(8, 3, 1, 3, C.metal)
  p:rect(10, 7, 2, 1, C.metal) -- hitch
  p:rect(3, 9, 3, 3, C.tire) -- wheel
  p:px(4, 10, C.metal)
end

function P.icon_cheese_press(p)
  p:rect(1, 1, 2, 10, C.bark)
  p:rect(9, 1, 2, 10, C.bark)
  p:rect(1, 1, 10, 2, C.barkLight)
  p:rect(5, 3, 2, 3, C.metal)
  p:rect(3, 7, 6, 4, CHEESE_YELLOW)
  p:rect(3, 10, 6, 1, CHEESE_DARK)
end

-- Threats (D67): a hailstone cloud, a cracked sun, a locust, a frosted sprout; and their
-- countermeasures (12x12 icons).
local HAIL_CLOUD = { 0.52, 0.56, 0.62 }
local HAIL_ICE = { 0.86, 0.93, 1.0 }
local SUN = { 0.98, 0.78, 0.25 }
local LOCUST = { 0.52, 0.62, 0.22 }
local LOCUST_DARK = { 0.34, 0.42, 0.14 }
local BLIGHT = { 0.42, 0.36, 0.22 }
local BLIGHT_DARK = { 0.24, 0.2, 0.12 }
local COPPER = { 0.36, 0.66, 0.58 }
local COPPER_DARK = { 0.22, 0.44, 0.4 }
local NET = { 0.85, 0.85, 0.80 }
local STRAW = { 0.86, 0.74, 0.40 }

function P.icon_hail(p)
  p:rect(2, 1, 8, 4, HAIL_CLOUD)
  p:rect(1, 2, 10, 2, HAIL_CLOUD)
  for _, d in ipairs({ { 2, 6 }, { 5, 7 }, { 8, 6 }, { 3, 9 }, { 7, 10 } }) do
    p:rect(d[1], d[2], 2, 2, HAIL_ICE)
  end
end

function P.icon_drought(p)
  p:rect(4, 1, 4, 4, SUN)
  p:rect(3, 2, 6, 2, SUN)
  p:rect(0, 7, 12, 4, C.soilDry)
  p:px(3, 8, C.furrowDry)
  p:px(4, 9, C.furrowDry)
  p:px(8, 7, C.furrowDry)
  p:px(7, 8, C.furrowDry)
  p:px(8, 9, C.furrowDry)
end

function P.icon_locust(p)
  p:rect(2, 5, 7, 3, LOCUST)
  p:rect(8, 4, 3, 3, LOCUST)
  p:px(10, 5, C.tire)
  p:rect(3, 3, 5, 2, LOCUST_DARK) -- wing
  p:px(3, 8, LOCUST_DARK)
  p:px(2, 9, LOCUST_DARK)
  p:px(6, 8, LOCUST_DARK)
  p:px(7, 9, LOCUST_DARK)
end

function P.icon_blight(p)
  p:rect(5, 4, 1, 7, C.leaf)
  p:rect(2, 3, 3, 3, BLIGHT)
  p:rect(6, 2, 3, 3, BLIGHT)
  p:px(3, 4, BLIGHT_DARK)
  p:px(7, 3, BLIGHT_DARK)
  p:px(4, 8, BLIGHT_DARK)
  p:px(8, 8, BLIGHT_DARK)
  p:rect(0, 11, 12, 1, C.soilWet)
end

function P.icon_copper_spray(p)
  p:rect(0, 9, 12, 2, C.soilDry)
  p:rect(3, 3, 5, 6, COPPER)
  p:rect(4, 1, 3, 2, COPPER_DARK)
  p:px(9, 2, COPPER)
  p:px(10, 3, COPPER)
  p:px(9, 4, COPPER)
end

function P.icon_frost(p)
  p:rect(5, 5, 1, 6, C.leaf)
  p:rect(2, 4, 3, 2, C.leafLight)
  p:rect(6, 3, 3, 2, C.leafLight)
  for _, d in ipairs({ { 1, 1 }, { 9, 1 }, { 2, 8 }, { 9, 8 }, { 5, 0 } }) do
    p:px(d[1], d[2], HAIL_ICE)
  end
  p:px(2, 4, HAIL_ICE)
  p:px(8, 3, HAIL_ICE)
end

-- A net or cloth over a small bed.
local function cover(p, color)
  p:rect(0, 9, 12, 2, C.soilDry)
  p:rect(3, 6, 1, 3, C.leaf)
  p:rect(8, 6, 1, 3, C.leaf)
  p:rect(1, 3, 10, 1, color)
  p:rect(1, 3, 1, 6, color)
  p:rect(10, 3, 1, 6, color)
end

function P.icon_hail_netting(p)
  cover(p, NET)
  for x = 2, 9, 2 do
    p:px(x, 4, NET)
  end
  p:rect(4, 0, 2, 2, HAIL_ICE)
end

function P.icon_row_covers(p)
  cover(p, NET)
  p:rect(2, 4, 8, 1, NET)
  p:px(10, 1, LOCUST)
end

function P.icon_frost_cloth(p)
  cover(p, { 0.92, 0.94, 0.98 })
  p:rect(2, 4, 8, 2, { 0.92, 0.94, 0.98 })
end

function P.icon_straw_mulch(p)
  p:rect(0, 8, 12, 3, C.soilWet)
  p:rect(1, 7, 10, 2, STRAW)
  p:px(2, 6, STRAW)
  p:px(6, 6, STRAW)
  p:px(9, 6, STRAW)
  p:rect(5, 3, 1, 4, C.leaf)
  p:rect(4, 2, 3, 2, C.leafLight)
end

-- Night raiders (C2 + C3, D188): the notes' stamps and the three counters' icons, 12x12 placeholders.
local RACCOON_FUR = { 0.52, 0.52, 0.55 }
local RACCOON_DARK = { 0.22, 0.22, 0.26 }
local BEAR_FUR = { 0.30, 0.20, 0.15 }
local DEER_FUR = { 0.70, 0.48, 0.28 }

function P.icon_raccoon(p)
  p:rect(2, 4, 8, 6, RACCOON_FUR)
  p:rect(2, 3, 2, 2, RACCOON_FUR) -- ears
  p:rect(8, 3, 2, 2, RACCOON_FUR)
  p:rect(2, 5, 8, 2, RACCOON_DARK) -- the mask
  p:px(4, 5, C.white)
  p:px(7, 5, C.white)
  p:rect(5, 8, 2, 1, RACCOON_DARK) -- nose
end

function P.icon_deer(p)
  p:rect(3, 5, 6, 5, DEER_FUR)
  p:rect(8, 3, 2, 3, DEER_FUR) -- head
  p:rect(8, 1, 1, 3, C.barkLight) -- antlers
  p:rect(10, 1, 1, 3, C.barkLight)
  p:px(9, 4, C.tire)
  p:rect(3, 10, 1, 2, C.bark) -- legs
  p:rect(8, 10, 1, 2, C.bark)
end

function P.icon_bear(p)
  p:rect(2, 4, 8, 7, BEAR_FUR)
  p:rect(2, 2, 2, 3, BEAR_FUR) -- ears
  p:rect(8, 2, 2, 3, BEAR_FUR)
  p:rect(4, 7, 4, 3, C.barkLight) -- muzzle
  p:px(4, 5, C.tire)
  p:px(7, 5, C.tire)
  p:px(5, 7, C.tire)
  p:px(6, 7, C.tire)
end

function P.icon_lidded_bins(p)
  p:rect(2, 4, 8, 7, C.metal) -- the bin
  p:rect(1, 3, 10, 2, C.stoneDark) -- the lid
  p:rect(5, 2, 2, 1, C.stoneDark) -- the handle
  p:rect(2, 7, 8, 1, C.stoneDark)
end

function P.icon_scarecrow(p)
  p:rect(5, 3, 2, 9, C.bark) -- the post
  p:rect(1, 5, 10, 1, C.bark) -- the arms
  p:rect(4, 1, 4, 3, STRAW) -- the head
  p:rect(3, 1, 6, 1, C.shirtDark) -- the hat
  p:rect(4, 6, 4, 3, C.shirt) -- the shirt
end

function P.icon_bear_box(p)
  p:rect(1, 3, 10, 8, C.stoneDark) -- the steel box
  p:rect(1, 3, 10, 1, C.metal)
  p:rect(5, 6, 2, 3, C.gold) -- the latch
  p:rect(2, 10, 8, 1, C.metal)
end

function P.icon_pipe_lagging(p)
  p:rect(5, 1, 2, 10, C.metal) -- the pipe
  p:rect(3, 3, 6, 2, STRAW) -- the wrapping
  p:rect(3, 6, 6, 2, STRAW)
  p:rect(3, 9, 6, 2, STRAW)
  p:rect(3, 5, 6, 1, C.bark) -- the twine
  p:rect(3, 8, 6, 1, C.bark)
end

-- Roadside stand: a plank table under a striped awning, with crates of goods (32x24).
function P.roadside_stand(p)
  local awningRed = { 0.74, 0.28, 0.24 }
  local awningCream = { 0.92, 0.88, 0.76 }
  p:ellipse(16, 23, 14, 1, C.shadow)
  p:rect(3, 8, 2, 15, C.bark) -- posts
  p:rect(27, 8, 2, 15, C.bark)
  for x = 1, 29, 4 do -- striped awning
    p:rect(x, 2, 2, 6, awningRed)
    p:rect(x + 2, 2, 2, 6, awningCream)
  end
  p:rect(1, 8, 30, 1, C.barkDark)
  p:rect(2, 15, 28, 3, C.barkLight) -- table top
  p:rect(2, 18, 28, 1, C.bark)
  p:rect(4, 19, 2, 4, C.bark)
  p:rect(26, 19, 2, 4, C.bark)
  p:rect(5, 12, 6, 3, C.radish) -- radishes
  p:rect(13, 12, 6, 3, C.barkLight) -- potatoes in a crate
  p:rect(13, 12, 6, 1, C.bark)
  p:rect(21, 12, 6, 3, { 0.62, 0.64, 0.58 }) -- a fish or two
  p:rect(11, 9, 10, 3, awningCream) -- price board
  p:rect(12, 10, 8, 1, awningRed)
end

-- Roadside stand tiers (D116): transparent 32x24 overlays drawn over the stand sprite while the upgrade is owned.
-- Painted sign: a bright board over the price board and a pennant on the right post.
function P.stand_sign_look(p)
  local board, ink = { 0.98, 0.82, 0.28 }, { 0.30, 0.18, 0.10 }
  p:rect(8, 8, 16, 5, C.barkDark)
  p:rect(9, 9, 14, 3, board)
  for x = 11, 21, 3 do
    p:rect(x, 10, 2, 1, ink)
  end
  p:rect(28, 0, 1, 8, C.bark) -- pennant pole
  p:rect(29, 0, 3, 3, { 0.74, 0.28, 0.24 })
end

-- Stand cooler: a pale blue chest on the table, lid and handle showing.
function P.stand_cooler_look(p)
  local body, lid = { 0.55, 0.74, 0.88 }, { 0.86, 0.93, 0.97 }
  p:rect(20, 10, 9, 6, body)
  p:rect(19, 9, 11, 2, lid)
  p:rect(22, 8, 5, 1, C.barkDark) -- handle
  p:rect(20, 13, 9, 1, { 0.40, 0.58, 0.74 })
end

function P.icon_roadside_stand(p)
  p:rect(1, 1, 10, 3, { 0.74, 0.28, 0.24 })
  p:rect(3, 1, 2, 3, { 0.92, 0.88, 0.76 })
  p:rect(7, 1, 2, 3, { 0.92, 0.88, 0.76 })
  p:rect(2, 4, 1, 6, C.bark)
  p:rect(9, 4, 1, 6, C.bark)
  p:rect(1, 7, 10, 2, C.barkLight)
  p:rect(3, 6, 2, 1, C.radish)
end

function P.icon_well(p)
  p:rect(1, 6, 10, 5, C.stone)
  p:rect(3, 7, 6, 2, WATER_DEEP)
  p:rect(1, 1, 10, 2, C.rust)
  p:rect(2, 3, 1, 3, C.bark)
  p:rect(9, 3, 1, 3, C.bark)
end

function P.icon_hand_pump(p)
  p:rect(5, 3, 2, 7, C.metal)
  p:rect(2, 2, 6, 1, CASE_LIGHT)
  p:rect(3, 10, 6, 1, C.stoneDark)
  p:rect(7, 6, 3, 1, C.metal)
  p:px(9, 7, C.water)
end

function P.icon_cistern(p)
  p:rect(1, 3, 10, 7, { 0.48, 0.52, 0.55 })
  p:rect(1, 3, 10, 1, { 0.64, 0.68, 0.70 })
  p:rect(4, 4, 1, 6, { 0.36, 0.40, 0.43 })
  p:rect(8, 4, 1, 6, { 0.36, 0.40, 0.43 })
  p:px(10, 8, C.water)
end

function P.icon_dc_pump(p)
  p:rect(1, 5, 6, 5, { 0.22, 0.38, 0.62 })
  p:rect(7, 6, 2, 3, C.metal)
  p:rect(8, 2, 1, 5, C.metal)
  p:px(3, 7, CELL_LINE)
end

function P.icon_drip_line(p)
  p:rect(1, 6, 10, 1, HOSE)
  p:rect(5, 2, 1, 5, HOSE)
  for _, e in ipairs({ { 2, 7 }, { 9, 7 }, { 5, 3 }, { 2, 5 }, { 9, 5 } }) do
    p:px(e[1], e[2], C.water)
  end
end

function P.icon_sprinkler(p)
  p:rect(5, 5, 2, 5, C.metal)
  p:rect(3, 9, 6, 2, C.metal)
  p:rect(4, 3, 4, 2, HOSE)
  for _, e in ipairs({ { 1, 2 }, { 10, 2 }, { 2, 4 }, { 9, 4 }, { 5, 1 }, { 6, 1 } }) do
    p:px(e[1], e[2], C.water)
  end
end

-- Machines (GDD §7.4, D65) -----------------------------------------------------------------

local MACHINE_PAINT = { 0.86, 0.66, 0.20 } -- farm-machine yellow
local MACHINE_PAINT_DARK = { 0.64, 0.46, 0.14 }

-- Auto-harvester (16x24): a squat yellow body on a turntable, a mast with a jointed picking arm and a
-- crate for the crop. The arm reaching to its target is drawn in code (visuals.machine).
function P.auto_harvester(p)
  p:ellipse(8, 22, 7, 2, C.shadow)
  p:rect(2, 19, 12, 3, C.stoneDark) -- turntable base
  p:rect(2, 19, 12, 1, C.stone)
  p:rect(3, 12, 10, 7, MACHINE_PAINT) -- body
  p:rect(3, 12, 10, 1, { 0.96, 0.80, 0.36 })
  p:rect(3, 17, 10, 2, MACHINE_PAINT_DARK)
  p:rect(5, 14, 3, 2, CELL_LINE) -- control panel
  p:rect(7, 3, 2, 9, C.metal) -- mast
  p:rect(7, 3, 1, 9, C.stoneLight)
  p:rect(8, 3, 6, 2, C.metal) -- arm
  p:rect(13, 5, 1, 3, C.metal) -- forearm
  p:rect(12, 8, 3, 2, CASE) -- gripper
  p:rect(9, 15, 4, 2, C.barkLight) -- crate for the crop
  p:px(10, 15, C.radish)
  p:px(12, 15, { 0.70, 0.56, 0.36 })
end

function P.icon_auto_harvester(p)
  p:rect(2, 6, 7, 4, MACHINE_PAINT)
  p:rect(2, 9, 7, 1, MACHINE_PAINT_DARK)
  p:rect(1, 10, 9, 1, C.stoneDark)
  p:rect(5, 1, 1, 5, C.metal)
  p:rect(5, 1, 5, 1, C.metal)
  p:rect(9, 2, 1, 2, C.metal)
  p:rect(8, 4, 3, 1, CASE)
  p:px(9, 6, C.radish)
end

local FISH_COLORS = {
  icon_spoiled = { { 0.45, 0.50, 0.25 }, { 0.62, 0.60, 0.32 } }, -- a fish gone off (journal note)
  icon_creek_chub = { { 0.62, 0.64, 0.58 }, { 0.80, 0.80, 0.74 } },
  icon_sunfish = { { 0.35, 0.55, 0.40 }, { 0.92, 0.62, 0.25 } },
  icon_brook_trout = { { 0.30, 0.38, 0.30 }, { 0.85, 0.45, 0.35 } },
  icon_smallmouth_bass = { { 0.48, 0.45, 0.25 }, { 0.70, 0.66, 0.42 } },
  icon_channel_catfish = { { 0.40, 0.42, 0.48 }, { 0.62, 0.64, 0.68 } },
  icon_rainbow_trout = { { 0.45, 0.55, 0.50 }, { 0.90, 0.50, 0.62 } },
  icon_golden_trout = { { 0.85, 0.65, 0.20 }, { 0.98, 0.85, 0.40 } },
}

function P.fish_icon(p, _, _, _, id)
  local colors = FISH_COLORS[id] or FISH_COLORS.icon_creek_chub
  p:ellipse(5, 6, 4, 2, colors[1])
  p:rect(2, 6, 6, 1, colors[2]) -- belly stripe
  p:rect(9, 4, 2, 5, colors[1]) -- tail
  p:px(3, 5, { 0.05, 0.05, 0.05 })
  p:outline(C.outline)
end

-- Interface icons (GDD §9.4, D142) ------------------------------------------------------
-- Tools, verbs, signals, books and seed packets, on the 12x12 icon grid. Lit from the top left with a
-- warm dark outline; tools lie on one diagonal (handle bottom left, head top right). Each is drawn
-- from rows of palette letters, so a placeholder reads like the pixel art it stands in for.

local UI_INK = {
  o = { 0.10, 0.08, 0.07 }, -- the warm dark outline
  w = { 0.50, 0.33, 0.19 }, -- wood
  W = { 0.70, 0.49, 0.29 }, -- wood, sunlit
  m = { 0.52, 0.56, 0.61 }, -- metal
  M = { 0.82, 0.85, 0.88 }, -- metal, sunlit
  d = { 0.30, 0.32, 0.37 }, -- metal in shade
  g = { 0.74, 0.56, 0.33 }, -- glove leather
  G = { 0.90, 0.75, 0.50 }, -- glove leather, sunlit
  b = { 0.50, 0.22, 0.17 }, -- notebook cover
  B = { 0.69, 0.33, 0.23 }, -- notebook cover, sunlit
  n = { 0.20, 0.27, 0.42 }, -- ledger cover
  N = { 0.31, 0.40, 0.57 }, -- ledger cover, sunlit
  p = { 0.93, 0.88, 0.75 }, -- paper
  P = { 0.80, 0.74, 0.60 }, -- paper in shade
  a = { 0.96, 0.74, 0.32 }, -- amber: needs you
  r = { 0.78, 0.25, 0.22 }, -- red: danger
  l = { 0.90, 0.92, 0.95, 0.8 }, -- fishing line
  k = { 1, 1, 1 }, -- a stamp's ink: white, so the book tabs tint it (#296)
}

local function rows(lines)
  return function(p)
    for y, line in ipairs(lines) do
      for x = 1, #line do
        local c = UI_INK[line:sub(x, x)]
        if c then
          p:px(x - 1, y - 1, c)
        end
      end
    end
  end
end

P.icon_tool_hand = rows({
  "...o.o.o....",
  "..oGoGoGo...",
  "..oGoGoGo.o.",
  "..oGGGGGGoGo",
  "..oGGGGGGGgo",
  "..ogGGGGGgo.",
  "..oggggggo..",
  "...ogggggo..",
  "...oooooo...",
  "...odddddo..",
  "...ooooooo..",
})

P.icon_tool_hoe = rows({
  "",
  ".......ooooo",
  "......oMMMmo",
  ".....oWoommo",
  "....oWwo.oo.",
  "...oWwo.....",
  "..oWwo......",
  ".oWwo.......",
  "oWwo........",
  "owo.........",
  "oo..........",
})

P.icon_tool_pail = rows({
  "",
  "...oooooo...",
  "..o......o..",
  ".o........o.",
  "oooooooooooo",
  "oMMmmmmmmddo",
  ".oMmmmmmmdo.",
  ".oMmmmmmmdo.",
  ".oMmmmmmmdo.",
  "..oMmmmmdo..",
  "..oooooooo..",
})

P.icon_tool_pail_big = rows({
  "..oooooooo..",
  ".o........o.",
  "oooooooooooo",
  "oMMmmmmmmmdo",
  "oMmmmmmmmmdo",
  "odddddddddo.",
  "oMmmmmmmmmdo",
  ".oMmmmmmmdo.",
  ".oMmmmmmmdo.",
  ".oMmmmmmmdo.",
  ".oooooooooo.",
})

P.icon_tool_hatchet = rows({
  "",
  "",
  "........oo..",
  ".......oMMo.",
  "......oMmmdo",
  ".....oWoMddo",
  "....oWo.ooo.",
  "...oWo......",
  "..oWo.......",
  ".oWo........",
  ".oo.........",
})

P.icon_tool_axe = rows({
  ".......oooo.",
  "......oMMMmo",
  ".....oMMmmdo",
  "....oWoMmmdo",
  "...oWo.oMddo",
  "..oWo...ooo.",
  ".oWo........",
  "oWo.........",
  "oo..........",
})

P.icon_tool_rod = rows({
  "..........oM",
  ".........oWo",
  "........oWo.",
  ".......oWo.l",
  "......oWo..l",
  ".....oWo...l",
  "...odWo....l",
  "..oddo.....o",
  ".oWo.......o",
  "oWo.........",
  "oo..........",
})

P.icon_tool_rod_sturdy = rows({
  "..........oM",
  ".........owo",
  "........owo.",
  ".......owo.l",
  "......oro..l",
  ".....owo...l",
  "...odwo....l",
  "..oddo.....o",
  ".owo.......o",
  "owo.........",
  "oo..........",
})

P.icon_tool_hammer = rows({
  "....oooooo..",
  "...oMMMMmdo.",
  "...oMmmmmdo.",
  "....oooWWo..",
  ".......oWo..",
  "......oWo...",
  ".....oWo....",
  "....oWo.....",
  "...oWo......",
  "..oWo.......",
  "..oo........",
})

P.icon_verb_move = rows({
  ".....oo.....",
  "....oppo....",
  "...oppppo...",
  ".....pp.....",
  ".oo..pp..oo.",
  "oppppppppppo",
  "oppppppppppo",
  ".oo..pp..oo.",
  ".....pp.....",
  "...oppppo...",
  "....oppo....",
  ".....oo.....",
})

P.icon_verb_pickup = rows({
  "....oo......",
  "...oppo.....",
  "..oppppo....",
  "....pp......",
  ".ooooooooo..",
  ".oWWWWWWWo..",
  ".owwwwwwwo..",
  ".oWWWWWWWo..",
  ".owwwwwwwo..",
  ".ooooooooo..",
})

P.icon_verb_demolish = rows({
  ".oooooooooo.",
  "orrrrrrrrMMo",
  "orrrrrrrrMro",
  "orrrrrrrMrro",
  "orrrrrrMrrro",
  "orrrrrMrrrro",
  "orrrrMrrrrro",
  "orrrMrrrrrro",
  "orrMrrrrrrro",
  "orMMrrrrrrro",
  ".oooooooooo.",
})

P.icon_verb_untill = rows({
  "",
  ".......ooooo",
  "......oMMMmo",
  ".....oWoommo",
  "....oWwo.oo.",
  "...oWwo.....",
  "..oWwo..r..r",
  ".oWwo....rr.",
  "oWwo.....rr.",
  "owo.....r..r",
  "oo..........",
})

P.icon_verb_plan = rows({
  "........oo..",
  ".......oaao.",
  "......oWoao.",
  ".....oWWo...",
  "....oWWo....",
  "...oWWo.....",
  "..oWWo......",
  ".opWo.......",
  ".opo........",
  ".oo.........",
  "............",
  "pppppppppp..",
})

P.icon_signal_alert = rows({
  "...oooooo...",
  "..oaaaaaao..",
  ".oaaaooaaao.",
  ".oaaaooaaao.",
  ".oaaaooaaao.",
  ".oaaaooaaao.",
  ".oaaaaaaaao.",
  ".oaaaooaaao.",
  "..oaaaaaao..",
  "...oooooo...",
})

P.icon_signal_idea = rows({
  "...oooooo...",
  "..oaaaaaao..",
  ".oaaooooaao.",
  ".oaoaaaaoao.",
  ".oaaaaaoaao.",
  ".oaaaaoaaao.",
  ".oaaaoaaaao.",
  ".oaaaaaaaao.",
  "..oaaoaaao..",
  "...oooooo...",
})

P.icon_book_notebook = rows({
  "",
  ".oooooooooo.",
  ".obBBBBBBpo.",
  ".obBBBBBBpo.",
  ".obBBaaBBpo.",
  ".obBBaaBBpo.",
  ".obBBBBBBpo.",
  ".obBBBBBBpo.",
  ".obbbbbbbpo.",
  ".oooooooooo.",
})

P.icon_book_ledger = rows({
  "",
  ".oooooooooo.",
  ".onNNNNNNpo.",
  ".onNppppNpo.",
  ".onNNNNNNpo.",
  ".onNppppNpo.",
  ".onNNNNNNpo.",
  ".onNppppNpo.",
  ".onnnnnnnpo.",
  ".oooooooooo.",
})

-- Ink-stamp icons for the books' tabs (D143): one colour, tinted when drawn.
P.icon_tab_journal = rows({
  "",
  "..kkkkkkkk..",
  "..k......k..",
  "..k.kkkk.k..",
  "..k......k..",
  "..k.kkkk.k..",
  "..k......k..",
  "..k.kkk..k..",
  "..k......k..",
  "..kkkkkkkk..",
})

P.icon_tab_fish = rows({
  "",
  "",
  "...kkkk.....",
  "..kkkkkk..k.",
  ".kk.kkkkkkk.",
  "..kkkkkk..k.",
  "...kkkk.....",
})

P.icon_tab_diary = rows({
  ".kkkkkkkkkk.",
  ".k........k.",
  ".k.kkkkkk.k.",
  ".k........k.",
  ".k.kkkk...k.",
  ".k........k.",
  ".kkkkkkkkkk.",
  "..kkk.......",
  "..kk........",
  "..k.........",
})

P.icon_tab_pantry = rows({
  "",
  "...kkkkkk...",
  "...k....k...",
  "..kkkkkkkk..",
  "..k......k..",
  "..k.kkkk.k..",
  "..k......k..",
  "..k.kkkk.k..",
  "..k......k..",
  "..kkkkkkkk..",
})

P.icon_tab_routine = rows({
  "",
  ".kk.kkkkkkk.",
  ".kk.........",
  "",
  ".kk.kkkkkkk.",
  ".kk.........",
  "",
  ".kk.kkkkkkk.",
  ".kk.........",
})

P.icon_tab_catalog = rows({
  "",
  "...kkkkkkk..",
  "..kk.....k..",
  ".kk..kk..k..",
  "kk...kk..k..",
  ".kk......k..",
  "..kk.....k..",
  "...kkkkkkk..",
})

P.icon_tab_truck = rows({
  "",
  "",
  ".kkkkkkk....",
  ".k.....k.kk.",
  ".k.....kkk.k",
  ".kkkkkkkkkkk",
  "..kk...kk...",
  "..kk...kk...",
})

-- Status icons (D167, #346): one per family of docs/PLAN_DEPTH.md §7, plus the plain one a new family falls back to.
P.icon_status = rows({
  "",
  "....oooo....",
  "....orro....",
  "..ooorrooo..",
  "..orrrrrro..",
  "..orrrrrro..",
  "..ooorrooo..",
  "....orro....",
  "....oooo....",
})

P.icon_status_ankle = rows({
  "...oooo.....",
  "...oppo.....",
  "...oPPo.....",
  "...oppo.....",
  "...oPPo.....",
  "...oppoooo..",
  "..oGgrrggo..",
  "..oGgggggo..",
  "..oooooooo..",
})

P.icon_status_limp = rows({
  "...oooo.....",
  "...oppo.....",
  "...oPPo.....",
  "...oppo.....",
  "..oPPPo.....",
  "..oppoooo...",
  ".oGgrrggo...",
  ".oGgggggo...",
  ".ooooooooo..",
})

P.icon_status_fever = rows({
  ".....oo.....",
  "....opPo....",
  "....opro....",
  "....opro....",
  "....opro....",
  "....opro....",
  "...oprrro...",
  "...orrrro...",
  "....oooo....",
})

P.icon_status_back = rows({
  "...oo.......",
  "..oWWo......",
  "...oWWo.....",
  "....oWWo....",
  "....oWWo..a.",
  "...oWWo..aaa",
  "..oWWo....a.",
  "..oWWo......",
  "...oo.......",
})

P.icon_status_burn = rows({
  ".....o......",
  "....oao.....",
  "...oaao.o...",
  "...oaroao...",
  "..oaarraao..",
  "..oarrrrao..",
  "..oarrrrao..",
  "...oaaaao...",
  "....oooo....",
})

P.icon_status_tired = rows({
  ".ooooooo....",
  ".opppppo....",
  "....oPo.....",
  "...oPo......",
  "..oPo.......",
  ".oppppppo...",
  ".ooooooo.oo.",
  ".......opo..",
  "........o...",
})

P.icon_status_wound = rows({
  "",
  "...oooooo...",
  "..oppppppo..",
  "..oprrrrpo..",
  "..oprrrrpo..",
  "..oppppppo..",
  "...oooooo...",
})

P.icon_status_rest = rows({
  ".oooooo.....",
  ".oPPPPo.....",
  "....oPo.....",
  "...oPo......",
  "..oPPPPo....",
  "..oooooo.oo.",
  "........oPPo",
  "..........oo",
})

P.icon_status_heat = rows({
  "....o..o....",
  "..o..oo..o..",
  "...oaaaao...",
  ".ooaaaaaaoo.",
  "..oaaaaaao..",
  ".ooaaaaaaoo.",
  "...oaaaao...",
  "..o..oo..o..",
  "....o..o....",
})

P.icon_status_tooth = rows({
  "...oooooo...",
  "..oppppppo..",
  "..oppppppo..",
  "..opppppPo..",
  "...oppPPo...",
  "...opoopo...",
  "...opo.opo..",
  "...ooo.ooo..",
})

-- Home event statuses (B7, D192): a drip, a draught, smoke and a split handle. Shared by the families that belong together.
P.icon_status_drip = rows({
  ".....oo.....",
  "....oPPo....",
  "...oPPPPo...",
  "...oPPPPo...",
  "...oPPPPo...",
  "....oPPo....",
  ".....oo.....",
})

P.icon_status_draught = rows({
  "ooooo.......",
  "PPPPPo..ooo.",
  "ooooPo.oPPPo",
  "....oPPPo.oo",
  "ooooPo......",
  "PPPPPo......",
  "ooooo.......",
})

P.icon_status_smoke = rows({
  "....oo......",
  "...oPPo.oo..",
  "..oPPPPoPPo.",
  "...oPPPPPo..",
  "....oooPo...",
  "...oPPPo....",
  "....ooo.....",
})

P.icon_status_tool = rows({
  ".......oo...",
  "......oaao..",
  ".....oaao...",
  "....oaao....",
  "...oPPo.....",
  "..oPPo......",
  ".oPPo.......",
  "..oo........",
})

-- The Wardrobe (D154): the decision stamp (a shirt on an amber round), the five slot tabs and the two presets.
P.icon_signal_clothes = rows({
  "...oooooo...",
  "..oaaaaaao..",
  ".oaoaaaaoao.",
  ".oooaaaaooo.",
  ".oaoaooaoao.",
  ".oaaaaaaaao.",
  ".oaaaaaaaao.",
  ".oaaaaaaaao.",
  "..oaaaaaao..",
  "...oooooo...",
})

P.icon_slot_head = rows({
  "",
  "....kkkk....",
  "...kkkkkk...",
  "..kkkkkkkk..",
  "..kkkkkkkk..",
  "kkkkkkkkkkkk",
  "kkkkkkkkkkkk",
})

P.icon_slot_torso = rows({
  "",
  "..kkk..kkk..",
  ".kkkkkkkkkk.",
  "kkkkkkkkkkkk",
  "kk.kkkkkk.kk",
  "kk.kkkkkk.kk",
  "...kkkkkk...",
  "...kkkkkk...",
  "...kkkkkk...",
})

P.icon_slot_legs = rows({
  "",
  "...kkkkkk...",
  "...kkkkkk...",
  "...kkkkkk...",
  "...kkk.kkk..",
  "...kkk.kkk..",
  "...kkk.kkk..",
  "...kkk.kkk..",
  "...kkk.kkk..",
})

P.icon_slot_feet = rows({
  "",
  "",
  "",
  "..kkk.......",
  "..kkk.......",
  "..kkkk......",
  "..kkkkkkk...",
  "..kkkkkkkkk.",
  "..kkkkkkkkk.",
})

P.icon_slot_extra = rows({
  "",
  ".....kk.....",
  "....kkkk....",
  ".....kk.....",
  "..kk.kk.kk..",
  ".kkkkkkkkkk.",
  "..kk.kk.kk..",
  ".....kk.....",
  "....kkkk....",
  ".....kk.....",
})

P.icon_preset_warm = rows({
  "",
  ".....kk.....",
  ".k...kk...k.",
  "..k.kkkk.k..",
  "....kkkk....",
  ".kk.kkkk.kk.",
  "....kkkk....",
  "..k.kkkk.k..",
  ".k...kk...k.",
  ".....kk.....",
})

P.icon_preset_cold = rows({
  "",
  ".....k......",
  "..k..k..k...",
  "...k.k.k....",
  ".k..kkk..k..",
  ".kkkkkkkkk..",
  ".k..kkk..k..",
  "...k.k.k....",
  "..k..k..k...",
  ".....k......",
})

P.icon_menu = rows({
  "",
  "",
  ".pppppppppp.",
  ".oooooooooo.",
  "",
  ".pppppppppp.",
  ".oooooooooo.",
  "",
  ".pppppppppp.",
  ".oooooooooo.",
})

local PACKET = {
  "oooooooooooo",
  "oPPPPPPPPPPo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oppppppppppo",
  "oooooooooooo",
}
P.icon_packet = rows(PACKET)

--- A seed packet with a crop on it: the packet, then the crop's own 12x12 icon painter drawn shrunk to
--- 8x8 in the middle (nearest pixel), so every crop gets a packet without a new drawing.
local function packet(cropPainter)
  return function(p)
    rows(PACKET)(p)
    local k = 8 / 12
    local q = { w = 12, h = 12 }
    function q.px(_, x, y, c)
      if x >= 0 and y >= 0 and x < 12 and y < 12 then
        p:px(2 + math.floor(x * k), 3 + math.floor(y * k), c)
      end
    end
    function q.rect(self, x, y, w, h, c)
      for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
          self:px(xx, yy, c)
        end
      end
    end
    function q.ellipse(self, cx, cy, rx, ry, c)
      for y = -ry, ry do
        for x = -rx, rx do
          if (x * x) / (rx * rx + 0.5) + (y * y) / (ry * ry + 0.5) <= 1 then
            self:px(cx + x, cy + y, c)
          end
        end
      end
    end
    function q.circle(self, cx, cy, r, c)
      self:ellipse(cx, cy, r, r, c)
    end
    function q.outline() end -- the packet frames it already
    cropPainter(q)
  end
end
P.icon_packet_radish = packet(P.icon_seed_radish)
P.icon_packet_potato = packet(P.icon_seed_potato)
for id in pairs(CROP_LOOKS) do
  P["icon_packet_" .. id] = packet(P["icon_seed_" .. id])
end

return P
