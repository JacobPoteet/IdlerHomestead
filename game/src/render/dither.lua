-- Dither settings for the shaders (GDD D133). tuning.visuals.dither holds one table per effect:
--   { algorithm = id, scale = art pixels per pattern cell, amount = 0..1, steps = levels (when the effect has them) }
-- and `algorithms`, the list of ids in the order the shader include (shaders/include/dither.glsl) numbers them.
-- Dither.send packs one effect's table into the shader's vec4 and hands over the blue-noise texture, so the
-- in-game editor can change a value and the next frame draws with it.

local BlueNoise = require("src.render.blue_noise")
local Shaders = require("src.render.shaders")

local Dither = {}

local blue -- { image, size }, built the first time a shader asks for blue noise

--- Index (0-based, as the shader numbers them) of an algorithm id.
function Dither.index(tuning, id)
  for i, name in ipairs(tuning.visuals.dither.algorithms) do
    if name == id then
      return i - 1
    end
  end
  error("unknown dither algorithm " .. tostring(id))
end

--- The vec4 { algorithm, scale, amount, steps } for the effect `name` (steps 0 when it has none).
function Dither.vec(tuning, name)
  local cfg = tuning.visuals.dither[name]
  local steps = rawget(cfg, "steps") or 0
  return { Dither.index(tuning, cfg.algorithm), cfg.scale, cfg.amount, steps }
end

--- The blue-noise texture, built on first use and kept.
function Dither.blueNoise(tuning)
  local size = tuning.visuals.dither.blueSize
  if not blue or blue.size ~= size then
    local ranks = BlueNoise.ranks(size)
    local data = love.image.newImageData(size, size, "r8")
    local n = size * size
    for i = 1, n do
      local v = (ranks[i] + 0.5) / n
      data:setPixel((i - 1) % size, math.floor((i - 1) / size), v, v, v, 1)
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    image:setWrap("repeat", "repeat")
    blue = { image = image, size = size }
  end
  return blue.image, size
end

--- Send the dither uniforms of `shader`: `uniforms` maps a uniform name in the shader to an effect name
--- ({ dither = "light" }, or two for the grade shader). Unused uniforms are skipped.
function Dither.send(shader, tuning, uniforms)
  local values, needBlue = {}, false
  for uniform, name in pairs(uniforms) do
    values[uniform] = Dither.vec(tuning, name)
    needBlue = needBlue or tuning.visuals.dither[name].algorithm == "blue"
  end
  if needBlue or shader:hasUniform("blueNoise") then
    -- Always bound (blue only built when something uses it; else a 1x1 stand-in the shader never reads).
    local image, size = Dither.standIn(tuning, needBlue)
    values.blueNoise, values.blueSize = image, size
  end
  Shaders.send(shader, values)
end

local plain
--- The blue-noise texture when `needed`, else a tiny white image (so no shader pays for the build).
function Dither.standIn(tuning, needed)
  if needed then
    return Dither.blueNoise(tuning)
  end
  if blue then
    return blue.image, blue.size
  end
  if not plain then
    plain = love.graphics.newImage(love.image.newImageData(1, 1))
  end
  return plain, 1
end

return Dither
