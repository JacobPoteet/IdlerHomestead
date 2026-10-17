-- The tool in the homesteader's hand (a static overlay, no animation yet, #335). Pure: it reads a
-- job and the tuning in data/tuning/visuals.lua `heldTool` and says which tool is held, which way the figure
-- faces and where the tool sprite goes; world_renderer.lua draws it. Routine and ordered jobs hold the same
-- tools, because both are just `actor.job`.

local Grid = require("src.sim.grid")

local HeldTool = {}

--- The tool id ("hoe", "pail", "axe") held for `job`, or nil when there is no job or its task holds nothing.
--- The job, not a queued order, is what the homesteader is doing.
function HeldTool.forJob(cfg, job)
  return job and rawget(cfg.tasks, job.task) or nil -- tuning is strict: an unlisted task is not an error here
end

--- Which way the figure faces: 1 right, -1 left. It turns to its target once it is working (or on its way
--- when no step has been taken yet), else to the way it last stepped, else keeps `last`.
function HeldTool.facing(cfg, grid, actor, job, last)
  local dx = actor.x - (actor.prevX or actor.x)
  if job and #job.path == 0 and type(job.target) == "number" then
    local tx = Grid.coords(grid, job.target)
    dx = tx - actor.x
  end
  if dx > cfg.turnEpsilon then
    return 1
  elseif dx < -cfg.turnEpsilon then
    return -1
  end
  return last or 1
end

--- Where to draw the tool sprite `spriteId` (w art pixels wide) for a figure sprite `figureW` wide whose top-left
--- is (x0, y0): returns x, y, sx for `love.graphics.draw` (sx -1 mirrors it and x is then its right edge).
function HeldTool.placement(cfg, spriteId, figureW, x0, y0, facing)
  local grip = assert(cfg.grips[spriteId], "no grip for tool sprite " .. tostring(spriteId))
  local hx, hy = cfg.hand[1], cfg.hand[2]
  if facing >= 0 then
    return x0 + hx - grip[1], y0 + hy - grip[2], 1
  end
  return x0 + (figureW - 1 - hx) + grip[1] + 1, y0 + hy - grip[2], -1
end

return HeldTool
