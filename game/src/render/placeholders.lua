-- Procedural placeholder pixel art, drawn once into the sprite atlas at startup.
-- Each painter receives a pixel helper `p` (0-based coordinates inside the sprite) and the
-- variant number. Replace entries in assets/manifest.lua with real art to retire these.

local P = {}

local C = {
  grass = { 0.36, 0.55, 0.29 },
  grassDark = { 0.29, 0.46, 0.24 },
  grassLight = { 0.45, 0.63, 0.34 },
  road = { 0.55, 0.44, 0.31 },
  roadDark = { 0.46, 0.36, 0.25 },
  pebble = { 0.66, 0.60, 0.50 },
  soilDry = { 0.45, 0.32, 0.21 },
  furrowDry = { 0.35, 0.24, 0.15 },
  soilWet = { 0.31, 0.21, 0.14 },
  furrowWet = { 0.22, 0.15, 0.10 },
  stone = { 0.60, 0.60, 0.56 },
  stoneLight = { 0.76, 0.76, 0.71 },
  stoneDark = { 0.40, 0.40, 0.38 },
  leaf = { 0.22, 0.42, 0.20 },
  leafLight = { 0.35, 0.58, 0.28 },
  leafDark = { 0.15, 0.30, 0.15 },
  bark = { 0.40, 0.28, 0.18 },
  barkDark = { 0.28, 0.19, 0.12 },
  barkLight = { 0.55, 0.40, 0.26 },
  rust = { 0.55, 0.30, 0.18 },
  metal = { 0.50, 0.53, 0.55 },
  shadow = { 0, 0, 0, 0.28 },
  radish = { 0.80, 0.22, 0.32 },
  potatoFlower = { 0.92, 0.90, 0.80 },
  skin = { 0.93, 0.76, 0.60 },
  shirt = { 0.70, 0.25, 0.22 },
  shirtDark = { 0.52, 0.17, 0.16 },
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
}
P.colors = C

local function speckle(p, w, h, base, specks, count)
  p:rect(0, 0, w, h, base)
  for _ = 1, count do
    p:px(p.rng:int(0, w - 1), p.rng:int(0, h - 1), specks[p.rng:int(1, #specks)])
  end
end

function P.grass(p, w, h)
  speckle(p, w, h, C.grass, { C.grassDark, C.grassLight }, 22)
  for _ = 1, 3 do -- little blades
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

function P.plan_marker(p, w, h)
  local c = { 0.95, 0.88, 0.60, 0.85 }
  for _, corner in ipairs({ { 1, 1, 1, 1 }, { w - 2, 1, -1, 1 }, { 1, h - 2, 1, -1 }, { w - 2, h - 2, -1, -1 } }) do
    local x, y, dx, dy = corner[1], corner[2], corner[3], corner[4]
    p:px(x, y, c)
    p:px(x + dx, y, c)
    p:px(x, y + dy, c)
  end
end

function P.brush(p)
  p:ellipse(8, 13, 6, 2, C.shadow)
  p:circle(5, 9, 4, C.leafDark)
  p:circle(10, 8, 5, C.leaf)
  p:circle(7, 6, 3, C.leaf)
  for _ = 1, 8 do
    p:px(p.rng:int(3, 13), p.rng:int(4, 11), C.leafLight)
  end
  p:px(4, 12, C.barkDark)
  p:px(11, 12, C.barkDark)
end

function P.rock(p)
  p:ellipse(8, 13, 6, 2, C.shadow)
  p:ellipse(8, 9, 6, 4, C.stoneDark)
  p:ellipse(8, 8, 5, 4, C.stone)
  p:rect(5, 6, 3, 1, C.stoneLight)
  p:px(10, 9, C.stoneDark)
end

function P.log(p)
  p:ellipse(8, 12, 7, 2, C.shadow)
  p:rect(1, 7, 13, 5, C.bark)
  p:rect(1, 7, 13, 1, C.barkLight)
  p:rect(1, 11, 13, 1, C.barkDark)
  p:ellipse(13, 9, 2, 2, C.barkLight)
  p:px(13, 9, C.barkDark)
  p:px(5, 9, C.barkDark)
  p:px(9, 8, C.barkDark)
end

function P.junk(p)
  p:ellipse(8, 13, 7, 2, C.shadow)
  p:rect(2, 7, 6, 5, C.rust) -- crate
  p:rect(2, 7, 6, 1, C.barkLight)
  p:circle(11, 10, 3, C.tire) -- tire
  p:circle(11, 10, 1, C.metal)
  p:rect(5, 4, 5, 3, C.metal) -- sheet metal
  p:px(6, 5, C.stoneLight)
end

function P.tree(p)
  p:ellipse(8, 30, 7, 2, C.shadow)
  p:rect(6, 18, 4, 12, C.bark)
  p:rect(6, 18, 1, 12, C.barkLight)
  p:rect(9, 18, 1, 12, C.barkDark)
  p:circle(8, 11, 8, C.leafDark)
  p:circle(7, 9, 7, C.leaf)
  p:circle(10, 12, 5, C.leaf)
  for _ = 1, 14 do
    p:px(p.rng:int(2, 13), p.rng:int(3, 15), C.leafLight)
  end
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

local function cropBase(p)
  p:rect(4, 12, 8, 1, C.furrowWet)
end

function P.radish(p, _, _, variant)
  cropBase(p)
  if variant == 1 then
    p:px(7, 10, C.leafLight)
    p:px(8, 9, C.leafLight)
    p:px(8, 10, C.leaf)
  elseif variant == 2 then
    p:ellipse(6, 8, 2, 3, C.leaf)
    p:ellipse(10, 8, 2, 3, C.leafLight)
    p:rect(8, 9, 1, 3, C.leafDark)
  else
    p:circle(8, 11, 2, C.radish)
    p:ellipse(5, 6, 2, 3, C.leaf)
    p:ellipse(11, 6, 2, 3, C.leafLight)
    p:ellipse(8, 5, 2, 3, C.leaf)
  end
end

function P.potato(p, _, _, variant)
  cropBase(p)
  if variant == 1 then
    p:px(7, 10, C.leafLight)
    p:px(8, 10, C.leaf)
    p:px(8, 9, C.leafLight)
  elseif variant == 2 then
    p:circle(8, 8, 4, C.leaf)
    p:px(6, 7, C.leafLight)
    p:px(10, 8, C.leafLight)
  else
    p:circle(8, 7, 6, C.leafDark)
    p:circle(8, 7, 5, C.leaf)
    for _, f in ipairs({ { 5, 4 }, { 10, 5 }, { 8, 8 } }) do
      p:px(f[1], f[2], C.potatoFlower)
    end
  end
end

function P.homesteader(p)
  p:ellipse(8, 19, 4, 1, C.shadow)
  p:rect(6, 15, 2, 4, C.pants)
  p:rect(9, 15, 2, 4, C.pants)
  p:rect(6, 18, 2, 1, C.boot)
  p:rect(9, 18, 2, 1, C.boot)
  p:rect(5, 8, 7, 7, C.shirt)
  p:rect(5, 10, 7, 1, C.shirtDark) -- flannel check
  p:rect(8, 8, 1, 7, C.shirtDark)
  p:rect(4, 9, 1, 5, C.skin)
  p:rect(12, 9, 1, 5, C.skin)
  p:rect(6, 2, 5, 6, C.skin)
  p:rect(6, 1, 5, 2, C.hair)
  p:px(6, 3, C.hair)
  p:px(7, 5, C.tire)
  p:px(9, 5, C.tire)
end

-- Icons ---------------------------------------------------------------------------------

function P.icon_money(p)
  p:circle(6, 6, 5, C.gold)
  p:circle(6, 6, 3, { 0.80, 0.62, 0.20 })
  p:rect(5, 4, 2, 5, C.gold)
end

function P.icon_food(p)
  p:ellipse(6, 7, 5, 3, { 0.62, 0.45, 0.30 })
  p:ellipse(6, 6, 4, 2, { 0.78, 0.60, 0.40 })
  p:px(4, 5, C.white)
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
end

function P.icon_scrap(p)
  p:rect(2, 5, 6, 4, C.rust)
  p:rect(5, 2, 5, 4, C.metal)
  p:px(6, 3, C.stoneLight)
end

function P.icon_seed_radish(p)
  p:ellipse(6, 7, 4, 4, C.radish)
  p:rect(5, 1, 2, 3, C.leaf)
  p:px(5, 6, C.white)
end

function P.icon_seed_potato(p)
  p:ellipse(6, 7, 5, 4, { 0.72, 0.56, 0.36 })
  p:px(4, 6, { 0.52, 0.38, 0.24 })
  p:px(8, 8, { 0.52, 0.38, 0.24 })
end

function P.icon_heart(p)
  p:circle(4, 5, 3, C.heart)
  p:circle(8, 5, 3, C.heart)
  for row = 0, 4 do
    p:rect(2 + row, 6 + row, 9 - row * 2, 1, C.heart)
  end
  p:px(3, 4, C.white)
end

return P
