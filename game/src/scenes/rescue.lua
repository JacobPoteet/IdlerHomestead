-- Search & rescue (GDD §4.3): lights in the snow. A short scene after Condition hits zero;
-- tap to continue to recovery in town. The run is already over (see src/meta/run.lua).

local Run = require("src.meta.run")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")

local Rescue = { name = "rescue", opaque = true }
Rescue.__index = Rescue

-- The rescuer recognizes you after the first time (GDD §7.8).
local FIRST_LINE = "Easy now. We've got you."
local AGAIN_LINES = {
  "You again?",
  "You again? Come on, up you get.",
  "We should name a trail after you.",
  "Same plan as last time? Let's get you warm.",
}

local SNOWFLAKES = 90
local CONTINUE_DELAY = 2.5 -- seconds before a tap moves on (so a stray tap can't skip it)

function Rescue.new()
  return setmetatable({ time = 0 }, Rescue)
end

function Rescue:enter(slot, data)
  self.slot, self.data = slot, data
  local rescues = Run.rescues(data.meta)
  if rescues <= 1 then
    self.line = FIRST_LINE
  else
    self.line = AGAIN_LINES[(rescues - 2) % #AGAIN_LINES + 1]
  end
  self.summary = data.meta.recovery and data.meta.recovery.summary
  -- Presentation-only randomness (not the sim RNG): where the snowflakes start.
  self.flakes = {}
  for n = 1, SNOWFLAKES do
    local h = (n * 2654435761) % 4294967296
    self.flakes[n] = { x = (h % 1000) / 1000, y = (math.floor(h / 1000) % 1000) / 1000, speed = 0.3 + (n % 7) / 10 }
  end
end

function Rescue:update(dt)
  self.time = self.time + dt
end

function Rescue:continue()
  self.app:switch(require("src.scenes.recovery").new(), self.slot, self.data)
end

function Rescue:action(name)
  if (name == "select" or name == "confirm" or name == "cancel") and self.time >= CONTINUE_DELAY then
    self:continue()
  end
  return true
end

-- A flashlight cone from a point on the horizon, sweeping slowly.
local function beam(cx, cy, angle, length, spread, alpha)
  local x1 = cx + math.cos(angle - spread) * length
  local y1 = cy + math.sin(angle - spread) * length
  local x2 = cx + math.cos(angle + spread) * length
  local y2 = cy + math.sin(angle + spread) * length
  love.graphics.setColor(1, 0.95, 0.8, alpha)
  love.graphics.polygon("fill", cx, cy, x1, y1, x2, y2)
end

function Rescue:draw()
  local view = self.app.view
  local t = self.time
  love.graphics.setColor(0.04, 0.05, 0.09, 1)
  love.graphics.rectangle("fill", 0, 0, view.w, view.h)
  -- Snowy ground
  love.graphics.setColor(0.16, 0.18, 0.24, 1)
  love.graphics.rectangle("fill", 0, view.h * 0.62, view.w, view.h * 0.38)

  -- Lights come over the rise after a moment.
  local lights = math.min(1, math.max(0, (t - 0.8) / 1.5))
  if lights > 0 then
    love.graphics.setBlendMode("add")
    local horizon = view.h * 0.62
    for n, offset in ipairs({ -0.18, 0.05, 0.22 }) do
      local cx = view.w * (0.5 + offset) + math.sin(t * 0.4 + n) * 12
      local angle = math.pi / 2 + math.sin(t * 0.7 + n * 1.7) * 0.5
      beam(cx, horizon, angle, view.h * 0.5, 0.16, 0.10 * lights)
      love.graphics.setColor(1, 0.95, 0.8, 0.9 * lights)
      love.graphics.circle("fill", cx, horizon, 2)
    end
    love.graphics.setBlendMode("alpha")
  end

  -- Falling snow, pixel-snapped.
  for _, f in ipairs(self.flakes) do
    local y = ((f.y + t * f.speed * 0.15) % 1) * view.h
    local x = (f.x * view.w + math.sin(t * f.speed + f.y * 9) * 6) % view.w
    love.graphics.setColor(0.9, 0.92, 1, 0.8)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
  end

  local textAlpha = math.min(1, math.max(0, (t - 1.6) / 1))
  local color = { theme.colors.text[1], theme.colors.text[2], theme.colors.text[3], textAlpha }
  Text.draw("Lights in the snow.", 0, view.h * 0.22, { size = "heading", width = view.w, align = "center", color = color })
  Text.draw('"' .. self.line .. '"', 0, view.h * 0.22 + 26, { size = "body", width = view.w, align = "center", color = color })
  if self.summary then
    local s = self.summary
    local season = s.season:gsub("^%l", string.upper)
    Text.draw(string.format("Day %d · %s, year %d", s.days, season, s.year), 0, view.h * 0.22 + 44, {
      size = "small",
      width = view.w,
      align = "center",
      color = { theme.colors.textDim[1], theme.colors.textDim[2], theme.colors.textDim[3], textAlpha },
    })
  end
  if t >= CONTINUE_DELAY then
    local pulse = 0.55 + 0.45 * math.sin(t * 3)
    Text.draw("Tap to continue", 0, view.h - 30, {
      size = "small",
      width = view.w,
      align = "center",
      color = { theme.colors.textDim[1], theme.colors.textDim[2], theme.colors.textDim[3], pulse },
    })
  end
end

return Rescue
