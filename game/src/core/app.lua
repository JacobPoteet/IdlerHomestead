-- Application shell: scene stack, virtual resolution, and routing of input/lifecycle events.
--
-- Virtual resolution: the window is divided by an integer scale so that at least
-- minVirtualWidth x minVirtualHeight virtual pixels are visible. Other aspect ratios simply
-- show more virtual space (no letterboxing). Scenes draw in virtual units; the app applies
-- the scale before calling scene:draw().
--
-- A scene is a table with any of:
--   enter(...), exit(), pause(), resume()        lifecycle
--   update(dt), draw()                           every frame (all scenes update; see `opaque`)
--   action(name, data) -> handled?               input actions (top scene only)
--   textinput(text), keypressed(key)             raw text entry for text fields (top scene only)
--   resize(view), focus(hasFocus), quit()
--   opaque = true                                scenes below it are not drawn
--   name = "..."                                 for the debug overlay

local App = {}
App.__index = App

--- ctx: shared services ({ tuning, registry, store, platform, ... }) available to scenes as app.ctx.
function App.new(ctx)
  local self = setmetatable({ ctx = ctx, stack = {}, view = { w = 0, h = 0, scale = 1 } }, App)
  return self
end

function App:resize(pixelW, pixelH)
  local display = self.ctx.tuning.display
  local scale = math.max(1, math.floor(math.min(pixelW / display.minVirtualWidth, pixelH / display.minVirtualHeight)))
  self.view = { w = pixelW / scale, h = pixelH / scale, scale = scale }
  for _, scene in ipairs(self.stack) do
    if scene.resize then
      scene:resize(self.view)
    end
  end
end

--- Convert window pixels to virtual coordinates.
function App:toVirtual(px, py)
  local s = self.view.scale
  return px / s, py / s
end

function App:top()
  return self.stack[#self.stack]
end

function App:push(scene, ...)
  local current = self:top()
  if current and current.pause then
    current:pause()
  end
  scene.app = self
  self.stack[#self.stack + 1] = scene
  if scene.enter then
    scene:enter(...)
  end
  if scene.resize then
    scene:resize(self.view)
  end
end

function App:pop()
  local scene = table.remove(self.stack)
  if scene and scene.exit then
    scene:exit()
  end
  local current = self:top()
  if current and current.resume then
    current:resume()
  end
  return scene
end

--- Replace the whole stack with one scene.
function App:switch(scene, ...)
  while #self.stack > 0 do
    local s = table.remove(self.stack)
    if s.exit then
      s:exit()
    end
  end
  self:push(scene, ...)
end

function App:update(dt)
  -- Copy: scenes may push/pop during update.
  local stack = { unpack(self.stack) }
  for _, scene in ipairs(stack) do
    if scene.update then
      scene:update(dt)
    end
  end
end

function App:draw()
  local first = 1
  for i = #self.stack, 1, -1 do
    if self.stack[i].opaque then
      first = i
      break
    end
  end
  for i = first, #self.stack do
    local scene = self.stack[i]
    if scene.draw then
      love.graphics.push("all")
      love.graphics.scale(self.view.scale)
      scene:draw()
      love.graphics.pop()
    end
  end
end

--- Deliver an input action to the top scene.
function App:action(name, data)
  local scene = self:top()
  if scene and scene.action then
    return scene:action(name, data)
  end
  return false
end

function App:textinput(text)
  local scene = self:top()
  if scene and scene.textinput then
    scene:textinput(text)
  end
end

function App:keypressed(key)
  local scene = self:top()
  if scene and scene.keypressed then
    scene:keypressed(key)
  end
end

--- Broadcast a lifecycle call (focus, quit) to every scene.
function App:broadcast(method, ...)
  for _, scene in ipairs(self.stack) do
    if scene[method] then
      scene[method](scene, ...)
    end
  end
end

return App
