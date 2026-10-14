-- Developer overlay (F1): scene stack, view, input, session and scene-provided details.
-- F2 cycles the sim time scale through tuning.time.debugTimeScales while a session is running.
-- (F3 is the template's performance overlay.)

local Debug = {}
Debug.__index = Debug

function Debug.new(app, input)
  return setmetatable({ app = app, input = input, visible = false, font = nil }, Debug)
end

--- Returns true if the key was a debug key.
function Debug:keypressed(key)
  if key == "f1" then
    self.visible = not self.visible
    return true
  elseif key == "f2" then
    local session = self.app.ctx.session
    if session then
      session:cycleSpeed(self.app.ctx.tuning.time.debugTimeScales)
    end
    return true
  end
  return false
end

function Debug:lines()
  local app = self.app
  local names = {}
  for _, scene in ipairs(app.stack) do
    names[#names + 1] = scene.name or "?"
  end
  local lines = {
    "F1 debug  F2 sim speed  F3 perf  F6 reload tuning+shaders",
    "scenes: " .. table.concat(names, " > "),
    string.format("view: %dx%d @%dx", app.view.w, app.view.h, app.view.scale),
    string.format("input: last=%s idle=%.1fs", tostring(self.input.lastAction), self.input:idleSeconds()),
  }
  local session = app.ctx.session
  if session then
    lines[#lines + 1] = string.format(
      "sim: tick=%d speed=%gx seed=%d",
      session.world.state.tick,
      session.clock.timeScale,
      session.world.state.seed
    )
  end
  if session and require("src.sim.systems.market").cheatOn(session.world) then
    lines[#lines + 1] = "CHEAT MODE ON (Catalog > Debug): every item free and instant"
  end
  for name, err in pairs(require("src.render.shaders").errors()) do
    lines[#lines + 1] = "SHADER " .. name .. ": " .. (err:gsub("\n.*", ""))
  end
  local top = app:top()
  if top and top.debugLines then
    for _, line in ipairs(top:debugLines()) do
      lines[#lines + 1] = line
    end
  end
  return lines
end

--- Drawn in real screen pixels, independent of the virtual scale.
function Debug:draw()
  if not self.visible then
    return
  end
  self.font = self.font or love.graphics.newFont(13)
  local lines = self:lines()
  local lineH = self.font:getHeight()
  local w = 0
  for _, line in ipairs(lines) do
    w = math.max(w, self.font:getWidth(line))
  end
  local x, y = 8, love.graphics.getHeight() - (#lines * lineH) - 16
  love.graphics.push("all")
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", x, y, w + 16, #lines * lineH + 8)
  love.graphics.setFont(self.font)
  love.graphics.setColor(0.6, 1, 0.6, 1)
  for i, line in ipairs(lines) do
    love.graphics.print(line, x + 8, y + 4 + (i - 1) * lineH)
  end
  love.graphics.pop()
end

return Debug
