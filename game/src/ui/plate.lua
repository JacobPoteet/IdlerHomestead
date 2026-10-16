-- Plates: the frosted, world-lit surfaces every HUD element, panel and button is drawn on (GDD §9.4, D142).
-- Presentation only. Each frame the game resets the plate state (Plate.beginFrame); the homestead then hands
-- over its graded frame (Plate.capture) and the world's light (Plate.setLight), so plates drawn after it,
-- in the HUD and in panels pushed over it, show the land behind them and take a share of its light. With
-- no world (the title, the slot list) a plate is its own solid colour. Text and icons are drawn over a
-- plate and are never tinted. Knobs: tuning.ui.plate and tuning.visuals.dither.plate.

local Shaders = require("src.render.shaders")
local Dither = require("src.render.dither")
local Settings = require("src.core.settings")
local theme = require("src.ui.theme")

local Plate = {}

local tuning -- the live tuning tables (F6 reloads them in place)
local frost -- the blurred world for this frame, or nil
local light = { tint = { 1, 1, 1 }, frost = 0, snow = 0, level = 1 }
local layers = {}
local blank
local NO_GLINT = { -1, -1 }

--- Hand over the live tuning tables once at start-up.
function Plate.setup(t)
  tuning = t
end

--- Forget last frame's world and light (called by the game before any scene draws).
function Plate.beginFrame()
  frost = nil
  light.tint[1], light.tint[2], light.tint[3] = 1, 1, 1
  light.frost, light.snow, light.level = 0, 0, 1
end

local function layer(key, w, h)
  local c = layers[key]
  if not c or c:getWidth() ~= w or c:getHeight() ~= h then
    c = love.graphics.newCanvas(w, h)
    c:setFilter("linear", "linear")
    c:setWrap("clamp", "clamp")
    layers[key] = c
  end
  return c
end

--- Make the blurred copy of the world the plates look through. `src` is the graded frame, screen-sized.
function Plate.capture(src)
  if not tuning then
    return
  end
  local cfg = tuning.ui.plate
  local w, h = src:getDimensions()
  local sw, sh = math.max(1, math.floor(w / cfg.blurDivisor)), math.max(1, math.floor(h / cfg.blurDivisor))
  local a, b = layer("a", sw, sh), layer("b", sw, sh)
  local blur = Shaders.get("bloom_blur")
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas(a)
  love.graphics.draw(src, 0, 0, 0, sw / w, sh / h)
  if blur then
    for _ = 1, cfg.blurPasses do
      love.graphics.setShader(blur)
      love.graphics.setCanvas(b)
      blur:send("step", { 1 / sw, 0 })
      love.graphics.draw(a, 0, 0)
      love.graphics.setCanvas(a)
      blur:send("step", { 0, 1 / sh })
      love.graphics.draw(b, 0, 0)
    end
  end
  love.graphics.pop()
  frost = a
end

--- The world's light for this frame: `tint` (the grade's colour multiplier), `level` (0 night .. 1 day),
--- and the winter amounts `frozen` (the creek's ice, 0..1) and `snow` (snow on the ground, 0..1).
function Plate.setLight(tint, level, frozen, snow)
  local cfg = tuning.ui.plate
  local share = cfg.gradeShare
  local dim = 1 - cfg.nightDim * (1 - level)
  light.level = level
  for i = 1, 3 do
    light.tint[i] = (1 + (tint[i] - 1) * share) * dim
  end
  local weather = Settings.read("ambientFx", true)
  light.frost = weather and frozen or 0
  light.snow = weather and snow or 0
end

--- The world's daylight level this frame (0 night .. 1 day), for things drawn over the world that follow it.
function Plate.level()
  return light.level
end

local function blankImage()
  if not blank then
    blank = love.graphics.newImage(love.image.newImageData(1, 1))
  end
  return blank
end

local function targetSize()
  local canvas = love.graphics.getCanvas()
  if canvas then
    return canvas:getDimensions()
  end
  return love.graphics.getDimensions()
end

--- Draw a plate at x, y, w, h (UI pixels, current transform). opts: { base = colour, see = 0..1, lit = 0..1,
--- ink = outline colour, alpha, weather = false (no frost or snow), kind = "button" | "panel" (more solid),
--- glintX, glintY (the amber signal's one pixel on the plate, src/ui/motion.lua) }.
function Plate.draw(x, y, w, h, opts)
  opts = opts or {}
  x, y, w, h = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
  local shader = tuning and Shaders.get("ui_plate")
  local colors = theme.colors
  local base = opts.base or colors.panel
  if not shader then
    love.graphics.setColor(base[1], base[2], base[3], opts.alpha or base[4] or 1)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(opts.ink or colors.panelBorder)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    return
  end
  local cfg = tuning.ui.plate
  local sx, sy = love.graphics.transformPoint(x, y)
  local ex, ey = love.graphics.transformPoint(x + w, y + h)
  local ux = love.graphics.transformPoint(x + 1, y) - sx
  local tw, th = targetSize()
  local weather = opts.weather ~= false
  local snow = (weather and w >= cfg.snowMinSize and h >= cfg.snowMinSize) and light.snow or 0
  local see = opts.see
  if not see then
    see = (opts.kind == "button" and cfg.buttonSee) or (opts.kind == "panel" and cfg.panelSee) or cfg.see
  end
  local ink = opts.ink or colors.panelBorder
  Shaders.send(shader, {
    frost = frost or blankImage(),
    screenSize = { tw, th },
    uiScale = ux,
    rect = { sx, sy, ex - sx, ey - sy },
    base = { base[1], base[2], base[3] },
    tint = light.tint,
    see = frost and see or 0,
    litColor = colors.panelLit,
    litAmount = opts.lit or cfg.litAmount,
    shadeColor = colors.panelShade,
    shadeAmount = cfg.shadeAmount,
    inkColor = { ink[1], ink[2], ink[3] },
    alpha = opts.alpha or cfg.alpha,
    cornerCut = cfg.cornerCut,
    frostAmount = weather and light.frost or 0,
    frostReach = cfg.frostReach,
    frostRing = (w < cfg.frostMinSize or h < cfg.frostMinSize) and 1 or 0,
    glintAt = opts.glintX and { opts.glintX, opts.glintY } or NO_GLINT,
    glintColor = tuning.ui.motion.amber.color,
    frostColor = tuning.visuals.frostColor,
    snowAmount = snow,
    snowColor = tuning.visuals.snowColor,
    snowShade = tuning.visuals.snowShade,
  })
  Dither.send(shader, tuning, { dither = "plate" })
  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(blankImage(), x, y, 0, w, h)
  love.graphics.setShader()
end

return Plate
