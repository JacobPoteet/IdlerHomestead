-- Journal focus drawing (GDD D81, #194): one chapter fitted to the body. The regions themselves (stamps,
-- links, nodes) are drawn by the scene (`scene:drawRegion`), so the tree looks as it always did; this
-- only places them at the fitted scale and dims what the active filter hides. Reads state only.
-- INTENTIONALLY MINIMAL (a temporary design).

local Layout = require("src.ui.journal_layout")
local Journal = require("src.sim.systems.journal")

local Focus = {}

function Focus.draw(scene, nav, spec)
  local fit, b = nav.fit, nav.body
  local scale = scene.app.view.scale
  love.graphics.setScissor(
    math.floor(b.x * scale),
    math.floor(b.y * scale),
    math.ceil(b.w * scale),
    math.ceil(b.h * scale)
  )
  love.graphics.push()
  love.graphics.translate(fit.ox, fit.oy - nav.focusOffset)
  love.graphics.scale(fit.scale, fit.scale)
  for _, region in ipairs(fit.map.regions) do
    scene:drawRegion(region)
    if nav.filter ~= "all" then
      love.graphics.setColor(spec.colors.dim)
      for _, node in ipairs(region.nodes) do
        if not Layout.matches(nav.filter, Journal.status(scene.world, node.id)) then
          love.graphics.rectangle("fill", node.x, node.y, node.w, node.h, 4, 4)
        end
      end
    end
  end
  love.graphics.pop()
  -- Scroll thumb, only where a very large chapter overflows (D120).
  if fit.contentH > b.h then
    local thumbH = math.max(spec.thumbMin, b.h * b.h / fit.contentH)
    local at = nav.focusOffset / (fit.contentH - b.h) * (b.h - thumbH)
    love.graphics.setColor(1, 1, 1, spec.thumbAlpha)
    love.graphics.rectangle("fill", b.x + b.w - spec.thumbWidth, b.y + at, spec.thumbWidth, thumbH)
  end
  love.graphics.setScissor()
end

return Focus
