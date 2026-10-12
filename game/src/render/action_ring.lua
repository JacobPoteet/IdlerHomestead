-- Action progress ring (GDD D44): a circle that fills over the tile the homesteader is working
-- on. Presentation only: it reads Actors.progress and never changes the world. Drawn in screen
-- (virtual UI) space after the world grade, so its size does not depend on the camera zoom.

local Grid = require("src.sim.grid")
local Actors = require("src.sim.systems.actors")

local ActionRing = {}

--- Should the ring show for this progress record? (Instant and very short actions stay hidden.)
function ActionRing.visible(progress, cfg)
  return progress ~= nil and progress.duration >= cfg.minSeconds
end

-- Filled pie from -90 degrees (12 o'clock) clockwise.
local function pie(x, y, radius, fraction, segments)
  if fraction <= 0 then
    return
  end
  local start = -math.pi / 2
  local steps = math.max(1, math.ceil(segments * math.min(1, fraction)))
  local verts = { x, y }
  for n = 0, steps do
    local a = start + math.pi * 2 * math.min(1, fraction) * n / steps
    verts[#verts + 1] = x + math.cos(a) * radius
    verts[#verts + 1] = y + math.sin(a) * radius
  end
  love.graphics.polygon("fill", verts)
end

--- Draw the ring at view position (x, y).
function ActionRing.drawAt(x, y, fraction, color, cfg)
  local r = cfg.radius
  love.graphics.setColor(cfg.backColor)
  love.graphics.circle("fill", x, y, r + 1, cfg.segments)
  love.graphics.setColor(cfg.trackColor)
  love.graphics.circle("fill", x, y, r, cfg.segments)
  love.graphics.setColor(color)
  pie(x, y, r, fraction, cfg.segments)
  love.graphics.setColor(cfg.backColor)
  love.graphics.circle("fill", x, y, r - cfg.thickness, cfg.segments)
end

--- Draw the ring for every actor with a timed action in progress. `area` = { top, bottom } is the
--- band of the view the world occupies, so rings under the HUD bars are skipped.
function ActionRing.draw(world, camera, view, area)
  local cfg = world.tuning.visuals.actionRing
  local grid, tile = world.state.grid, camera.tileSize
  for _, actor in ipairs(world.state.actors) do
    local progress = Actors.progress(world, actor)
    if ActionRing.visible(progress, cfg) then
      local tx, ty = Grid.coords(grid, progress.target)
      local vx, vy = camera:worldToView((tx - 0.5) * tile, (ty - 0.5) * tile, view)
      if vy - cfg.radius > area.top and vy + cfg.radius < area.bottom and vx > 0 and vx < view.w then
        local ordered = actor.job and actor.job.ordered
        ActionRing.drawAt(vx, vy, progress.fraction, ordered and cfg.orderedColor or cfg.routineColor, cfg)
      end
    end
  end
end

return ActionRing
