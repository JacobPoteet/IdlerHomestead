-- The homesteader's figure (src/render/character.lua): every outfit fits the sprite, stands on its feet, keeps
-- the face and leaves room for the outline.
local T = require("harness")
local Character = require("src.render.character")
local manifest = require("assets.manifest")

local function bounds(grid)
  local minX, maxX, minY, maxY = math.huge, -1, math.huge, -1
  for y = 0, Character.H - 1 do
    for x = 0, Character.W - 1 do
      if grid[y][x] then
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minY, maxY = math.min(minY, y), math.max(maxY, y)
      end
    end
  end
  return minX, maxX, minY, maxY
end

T.test("character: the manifest sprite is the size the painter draws", function()
  local entry = manifest.sprites.homesteader
  T.eq(entry.w, Character.W)
  T.eq(entry.h, Character.H)
end)

T.test("character: every outfit leaves a 1 px margin for the outline and a row for the shadow", function()
  for name, outfit in pairs(Character.outfits) do
    local minX, maxX, minY, maxY = bounds(Character.build(outfit))
    T.truthy(minX >= 1 and maxX <= Character.W - 2, name .. " fits across with room for the outline")
    T.truthy(minY >= 1, name .. " leaves a row above for the outline")
    T.truthy(maxY <= Character.H - 2, name .. " leaves a row below for the outline and shadow")
  end
end)

T.test("character: the feet are on the same row in every outfit, so clothes never lift the figure", function()
  local _, _, _, base = bounds(Character.build(Character.outfits.starter))
  for name, outfit in pairs(Character.outfits) do
    local _, _, _, maxY = bounds(Character.build(outfit))
    T.eq(maxY, base, name .. " feet row")
  end
end)

T.test("character: every outfit keeps a face and a warm accent of at least 3 px", function()
  for name, outfit in pairs(Character.outfits) do
    local grid = Character.build(outfit)
    local dark, warm = 0, 0
    for y = 0, Character.H - 1 do
      for x = 0, Character.W - 1 do
        local c = grid[y][x]
        if c and c[1] < 0.1 and c[2] < 0.1 and c[3] < 0.2 then
          dark = dark + 1
        end
        if c and c[1] > 0.6 and c[2] < 0.35 and c[3] < 0.3 then
          warm = warm + 1
        end
      end
    end
    T.eq(dark, 6, name .. " has two eyes: 2x2 with a glint pixel each")
    T.truthy(warm >= 3, name .. " keeps a saturated warm accent (the red travels)")
  end
end)

-- Garments (docs/PLAN_WARDROBE.md, data/content/garments.lua): every garment, worn on its own over the
-- starter outfit, and the whole outfits of each weight class, paint within the same rules.
local Registry = require("src.core.registry")
local reg = Registry.new():loadAll()

local function starterWith(slot, id)
  local outfit = {}
  for _, def in ipairs(reg:all("garments")) do
    if def.default then
      outfit[def.slot] = def.id
    end
  end
  outfit[slot] = id
  return outfit
end

local function classOutfit(class)
  local outfit = {}
  for _, def in ipairs(reg:all("garments")) do
    if def.class == class and not outfit[def.slot] then
      outfit[def.slot] = def.id
    end
  end
  return outfit
end

local function paintsWithinTheRules(name, look)
  local grid = Character.build(look)
  local minX, maxX, minY, maxY = bounds(grid)
  T.truthy(minX >= 1 and maxX <= Character.W - 2, name .. " fits across with room for the outline")
  T.truthy(minY >= 1, name .. " leaves a row above for the outline")
  local _, _, _, base = bounds(Character.build(Character.outfitFor(reg, {})))
  T.eq(maxY, base, name .. " feet row")
  local dark, warm = 0, 0
  for y = 0, Character.H - 1 do
    for x = 0, Character.W - 1 do
      local c = grid[y][x]
      if c and c[1] < 0.1 and c[2] < 0.1 and c[3] < 0.2 then
        dark = dark + 1
      end
      if c and c[1] > 0.6 and c[2] < 0.35 and c[3] < 0.3 then
        warm = warm + 1
      end
    end
  end
  T.eq(dark, 6, name .. " keeps its two eyes")
  T.truthy(warm >= 3, name .. " keeps a saturated warm accent (the red travels), has " .. warm)
end

T.test("character: the starter garments make exactly the starter look", function()
  T.same(Character.outfitFor(reg, {}), Character.outfits.starter)
  T.same(Character.outfitFor(reg, nil), Character.outfits.starter)
  T.same(Character.outfitFor(reg, { head = "nope", torso = "wool_toque" }), Character.outfits.starter)
end)

local LOOK_FIELDS = {
  hat = true,
  top = true,
  sleeve = true,
  legs = true,
  boots = true,
  cuff = true,
  mitts = true,
  scarf = true,
  belt = true,
  bib = true,
  shorts = true,
  glove = true,
  bandana = true,
  accent = true,
}

T.test("character: every garment paints within the rules, alone and in a full outfit of its class", function()
  local seen = {}
  for _, def in ipairs(reg:all("garments")) do
    paintsWithinTheRules(def.id, Character.outfitFor(reg, starterWith(def.slot, def.id)))
    seen[def.slot] = true
    for field in pairs(def.look) do
      T.truthy(LOOK_FIELDS[field], def.id .. " sets an unknown look field " .. field)
    end
  end
  for _, slot in ipairs(Character.slots) do
    T.truthy(seen[slot], "slot " .. slot .. " has garments")
  end
  for _, class in ipairs({ "light", "mid", "heavy" }) do
    paintsWithinTheRules("all " .. class, Character.outfitFor(reg, classOutfit(class)))
  end
end)

T.test("character: every garment looks different from the others of its slot", function()
  local function key(look)
    local grid = Character.build(look)
    local parts = {}
    for y = 0, Character.H - 1 do
      for x = 0, Character.W - 1 do
        local c = grid[y][x]
        parts[#parts + 1] = c and string.format("%.2f%.2f%.2f", c[1], c[2], c[3]) or "-"
      end
    end
    return table.concat(parts, ",")
  end
  local seen = {}
  for _, def in ipairs(reg:all("garments")) do
    local k = key(Character.outfitFor(reg, starterWith(def.slot, def.id)))
    T.falsy(seen[def.slot .. k], def.id .. " paints the same as " .. tostring(seen[def.slot .. k]))
    seen[def.slot .. k] = def.id
  end
end)

-- The part-id grid and the silhouette (the Wardrobe draws a locked garment's shape in ink, D154).
T.test(
  "character: build also returns the part-id grid, set exactly where the figure has a pixel before the face",
  function()
    local grid, ids = Character.build(Character.outfits.starter)
    local both, onlyColour = 0, 0
    for y = 0, Character.H - 1 do
      for x = 0, Character.W - 1 do
        if ids[y][x] then
          T.truthy(grid[y][x], "a part pixel has a colour")
          both = both + 1
        elseif grid[y][x] then
          onlyColour = onlyColour + 1
        end
      end
    end
    T.truthy(both > 100, "the figure has parts")
    T.eq(onlyColour, 0, "the face is drawn over parts, never beyond them")
    T.eq(ids[Character.H - 1][0], nil, "the shadow row is not a part")
  end
)

T.test("character: a garment's silhouette is its own pixels, and a default garment has none", function()
  local draft = starterWith("head", "bare_head")
  for _, def in ipairs(reg:all("garments")) do
    local mask = Character.silhouette(reg, draft, def.slot, def.id)
    local n = 0
    for y = 0, Character.H - 1 do
      for x = 0, Character.W - 1 do
        if mask[y][x] then
          n = n + 1
        end
      end
    end
    if def.default then
      T.eq(n, 0, def.id .. " is the slot's default: nothing to show")
    else
      T.truthy(n >= 3, def.id .. " has a silhouette, " .. n .. " px")
    end
  end
  -- A hat's silhouette lies in the head's rows and boots' on the feet.
  local function rows(slot, id)
    local mask = Character.silhouette(reg, draft, slot, id)
    local lo, hi = math.huge, -1
    for y = 0, Character.H - 1 do
      for x = 0, Character.W - 1 do
        if mask[y][x] then
          lo, hi = math.min(lo, y), math.max(hi, y)
        end
      end
    end
    return lo, hi
  end
  local lo, hi = rows("head", "straw_hat")
  T.truthy(hi <= 10, "the straw hat stays on the head (rows " .. lo .. " to " .. hi .. ")")
  lo, hi = rows("feet", "snow_boots")
  T.truthy(lo >= 15, "the boots stay on the feet (rows " .. lo .. " to " .. hi .. ")")
end)
