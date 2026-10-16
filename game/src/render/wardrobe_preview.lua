-- The homesteader's figure outside the atlas (docs/PLAN_WARDROBE_MENU.md §6.4): small nearest-filtered canvases
-- of an outfit for the Wardrobe's big preview and its tiles, painted by the same `Character.paint` that paints the
-- world sprite, so the two always match. Built lazily and kept in a small cache by outfit. And the other half of
-- the job: `dressWorld` repaints the world sprite (`Assets.recomposite`) when the outfit changes. Presentation
-- only; it reads garments and never writes the sim.

local Assets = require("src.render.assets")
local Character = require("src.render.character")
local placeholders = require("src.render.placeholders")

local Preview = {}

local cfg -- tuning.ui.wardrobe, handed over by `setup`
local cache = {} -- key -> { canvas, used }
local count = 0
local tick = 0 -- bumped on every use, so the least recently used entry is the lowest
local budget = math.huge -- images that may still be built this frame

--- Hand over the live tuning once (the cache size, the silhouette inks).
function Preview.setup(wardrobeCfg)
  cfg = wardrobeCfg
end

--- Start a frame: at most `n` images are built before the next one (the rest read nil and fill in a frame later).
function Preview.frame(n)
  budget = n or math.huge
end

--- Throw every image away (the Wardrobe closed, or the window changed).
function Preview.clear()
  for _, entry in pairs(cache) do
    entry.canvas:release()
  end
  cache, count = {}, 0
end

local function outfitKey(outfit)
  local keys = {}
  for _, slot in ipairs(Character.slots) do
    keys[#keys + 1] = outfit[slot] or "-"
  end
  return table.concat(keys, "|")
end

local function evict()
  local oldest, oldestKey
  for key, entry in pairs(cache) do
    if not oldest or entry.used < oldest then
      oldest, oldestKey = entry.used, key
    end
  end
  if oldestKey then
    cache[oldestKey].canvas:release()
    cache[oldestKey] = nil
    count = count - 1
  end
end

-- A cached canvas for `key`, painted by `paint(p)` into a W x H canvas the first time. nil when this frame's
-- build budget is spent and `force` is not set.
local function image(key, force, paint)
  tick = tick + 1
  local entry = cache[key]
  if entry then
    entry.used = tick
    return entry.canvas
  end
  if budget <= 0 and not force then
    return nil
  end
  budget = budget - 1
  while count >= (cfg and cfg.previewCache or 24) do
    evict()
  end
  local canvas = love.graphics.newCanvas(Character.W, Character.H)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setBlendMode("alpha")
  love.graphics.clear(0, 0, 0, 0)
  paint(Assets.painter(0, 0, Character.W, Character.H))
  love.graphics.pop()
  cache[key] = { canvas = canvas, used = tick }
  count = count + 1
  return canvas
end

--- The figure wearing `outfit` (`{ slot = garmentId }`) as a W x H canvas, ground shadow and outline included, or
--- nil when this frame's builds are spent (`force` builds it anyway).
function Preview.figure(registry, outfit, force)
  return image("fig:" .. outfitKey(outfit), force, function(p)
    Character.paint(p, Character.outfitFor(registry, outfit), placeholders.colors.shadow)
  end)
end

--- The shape of garment `id` (not yet earned) as a canvas: its pixels in the silhouette ink with a pale ring, to
--- draw over the figure of `outfit`. nil like `figure`.
function Preview.silhouette(registry, outfit, slot, id, force)
  return image("sil:" .. outfitKey(outfit) .. ":" .. slot .. ":" .. id, force, function(p)
    local mask = Character.silhouette(registry, outfit, slot, id)
    local ink = cfg.silhouetteInk
    for y = 0, Character.H - 1 do
      for x = 0, Character.W - 1 do
        if mask[y][x] then
          p:px(x, y, ink)
        end
      end
    end
    p:outline(cfg.silhouetteEdge)
  end)
end

--- Repaint the world's homesteader sprite wearing `outfit`: the world figure, the badge's portrait and the cast
--- shadow all read that atlas rectangle, so they change together.
function Preview.dressWorld(registry, outfit)
  Assets.recomposite("homesteader", function(p)
    Character.paint(p, Character.outfitFor(registry, outfit), placeholders.colors.shadow)
  end)
end

return Preview
