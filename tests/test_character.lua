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
