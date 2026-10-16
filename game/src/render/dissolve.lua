-- The dither dissolve (GDD §9.4, D142): draw something that opens or closes (the tool wheel, a book, a card)
-- through the shared dither instead of an alpha fade. Presentation only. Use:
--
--   if Dissolve.begin(coverage) then
--     ... draw it ...
--     Dissolve.finish()
--   end
--
-- At coverage 1 `begin` lets the drawing go straight to the screen (no canvas, no extra cost) and at 0 it says
-- to skip the drawing; only between the two does the drawing go to a canvas the size of the target and come
-- back through shaders/ui_dissolve.glsl. A dissolve begun inside another just draws straight.

local Dither = require("src.render.dither")
local Shaders = require("src.render.shaders")

local Dissolve = {}

local tuning
local canvas
local capture = { depth = 0, coverage = 0, previous = false, scale = nil }
local stack = {} -- per begin: true when it captured to the canvas

--- Hand over the live tuning tables once at start-up.
function Dissolve.setup(t)
  tuning = t
end

local function layer()
  local target = love.graphics.getCanvas()
  local w, h
  if target then
    w, h = target:getDimensions()
  else
    w, h = love.graphics.getDimensions()
  end
  if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
    canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
  end
  return canvas, target
end

--- Start a dissolve at `coverage` (0..1). Returns false when there is nothing to draw (coverage 0). When it
--- returns true, draw, then call `finish`. `scale`: target pixels per UI pixel for the dither cells, for a call
--- made with an identity transform (default: read from the current transform).
function Dissolve.begin(coverage, scale)
  if coverage <= 0 then
    return false
  end
  local depth = capture.depth + 1
  capture.depth = depth
  local shader = tuning and Shaders.get("ui_dissolve")
  if coverage >= 1 or depth > 1 or (not shader and coverage >= 0.5) then
    stack[depth] = false -- drawn straight (without the shader, a dissolve is a plain show above half)
    return true
  end
  if not shader then
    capture.depth = depth - 1
    return false
  end
  local c, previous = layer()
  love.graphics.push("all")
  capture.previous, capture.coverage, capture.scale = previous or false, coverage, scale
  stack[depth] = true
  love.graphics.setCanvas(c)
  love.graphics.clear(0, 0, 0, 0)
  return true
end

--- Finish a dissolve `begin` started: put what was drawn on the screen through the dither.
function Dissolve.finish()
  local depth = capture.depth
  capture.depth = depth - 1
  if not stack[depth] then
    return
  end
  love.graphics.setCanvas(capture.previous or nil)
  local shader = Shaders.get("ui_dissolve")
  local ux = capture.scale
  if not ux then
    ux = love.graphics.transformPoint(1, 0) - love.graphics.transformPoint(0, 0)
  end
  love.graphics.origin()
  Shaders.send(shader, { coverage = capture.coverage, uiScale = ux })
  Dither.send(shader, tuning, { dither = "transition" })
  love.graphics.setShader(shader)
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  love.graphics.pop()
end

return Dissolve
