-- Screenshot driver helper API (see README.md). A scenario script receives one `d` object per
-- window size and plays the real game through it: input goes through the game's own input
-- abstraction (mouse events -> actions), time advances by running the real update loop, and
-- screenshots are rendered offscreen from the real draw code.

local Save = require("src.core.save")
local Game = require("src.game")
local Buttons = require("src.ui.buttons")
local Grid = require("src.sim.grid")
local Actors = require("src.sim.systems.actors")
local Rng = require("src.core.rng")
local Assets = require("src.render.assets")

local Driver = {}
Driver.__index = Driver

Driver.SIZES = {
  desktop = { w = 1280, h = 720 },
  phone = { w = 390, h = 844 },
  landscape = { w = 844, h = 390 },
}

local FRAME = 1 / 20 -- real seconds per scripted frame (one sim tick at 1x)

--- opts: { size = "desktop"|"phone", outDir = absolute dir, prefix = file name prefix }
function Driver.new(opts)
  local size = assert(Driver.SIZES[opts.size], "unknown size " .. tostring(opts.size))
  love.window.setMode(size.w, size.h, { resizable = true, minwidth = 1, minheight = 1, vsync = 0 })
  local self = setmetatable({
    sizeName = opts.size,
    seed = opts.seed or 1,
    outDir = opts.outDir,
    prefix = opts.prefix,
    shots = {},
    backend = Save.memoryBackend(), -- never the real save directory
  }, Driver)
  self.game = Game.new({ backend = self.backend, tips = false })
  self:frames(2)
  return self
end

-- Time --------------------------------------------------------------------------------------

--- Run n real frames of `dt` seconds each (default one sim tick at 1x speed).
function Driver:frames(n, dt)
  for _ = 1, n do
    self.game:update(dt or FRAME)
  end
end

--- Advance game time by `hours` in-game hours at the session's current speed (a paused game does
--- not advance). Idle takeover is wall-clock based, so use `routine()` to hand over explicitly.
function Driver:advance(hours)
  local ctx = self.game.app.ctx
  local seconds = hours * ctx.tuning.time.dayLength / 24
  local session = ctx.session
  local speed = session and session:effectiveSpeed() or 1 -- includes the automatic sleep speed (D56)
  if speed <= 0 then
    error("advance(): the game is paused; unpause first", 2)
  end
  self:frames(math.ceil(seconds / speed / FRAME), FRAME)
end

--- Set the game speed multiplier directly (0 = paused).
function Driver:setSpeed(scale)
  self.game.app.ctx.session:setSpeed(scale)
  self:frames(1, 0)
end

-- Window ------------------------------------------------------------------------------------

--- Resize the window and tell the game, like a real resize event.
function Driver:resize(w, h)
  love.window.updateMode(w, h, { resizable = true, minwidth = 1, minheight = 1, vsync = 0 })
  -- A mode change can leave the placeholder atlas canvas empty (#222; a real resize event never
  -- does), so rebuild the sprites like the game does at startup.
  Assets.load()
  self.game:resize(love.graphics.getDimensions())
  self:frames(2)
end

-- Input -------------------------------------------------------------------------------------

--- Click/tap at window pixel (px, py) through the game's mouse handler.
function Driver:clickPixel(px, py)
  local input = self.game.input
  input:mousemoved(px, py, 0, 0, false)
  input:mousepressed(px, py, 1, false)
  input:mousereleased(px, py, 1, false)
  self:frames(2)
end

--- Click at a virtual (scene-space) position.
function Driver:click(vx, vy)
  local s = self.game.app.view.scale
  self:clickPixel(vx * s, vy * s)
end

--- Drag from one virtual position to another through the mouse handler, in a few steps (a finger
--- swipe). The release afterwards is a real release, so a drag never counts as a tap.
function Driver:drag(vx1, vy1, vx2, vy2, steps)
  local s = self.game.app.view.scale
  local input = self.game.input
  steps = steps or 6
  input:mousemoved(vx1 * s, vy1 * s, 0, 0, false)
  input:mousepressed(vx1 * s, vy1 * s, 1, false)
  for n = 1, steps do
    local t = n / steps
    input:mousemoved((vx1 + (vx2 - vx1) * t) * s, (vy1 + (vy2 - vy1) * t) * s, 0, 0, false)
  end
  input:mousereleased(vx2 * s, vy2 * s, 1, false)
  self:frames(2)
end

--- Turn the mouse wheel `notches` times (positive = up) with the pointer at a virtual position.
function Driver:wheel(notches, vx, vy)
  local s = self.game.app.view.scale
  love.mouse.setPosition(vx * s, vy * s)
  for _ = 1, math.abs(notches) do
    self.game.input:wheelmoved(0, notches > 0 and 1 or -1)
  end
  self:frames(2)
end

--- Press a key like the keyboard would ("escape", "space", "r", ...).
function Driver:key(name)
  self.game:keypressed(name)
  self:frames(2)
end

--- All Buttons groups on the top scene (any field holding one).
local function buttonGroups(scene)
  local groups = {}
  for _, v in pairs(scene) do
    if type(v) == "table" and getmetatable(v) == Buttons then
      groups[#groups + 1] = v
    end
  end
  return groups
end

--- The button with this label (case-insensitive, exact match) on the top scene, or nil.
function Driver:findButton(label)
  local scene = self.game.app:top()
  local want = label:lower()
  for _, group in ipairs(buttonGroups(scene)) do
    for _, b in ipairs(group.list) do
      if b.label and b.label:lower() == want then
        return b
      end
    end
  end
  return nil
end

--- Labels of every button on the top scene (for debugging a scenario).
function Driver:labels()
  local out = {}
  for _, group in ipairs(buttonGroups(self.game.app:top())) do
    for _, b in ipairs(group.list) do
      out[#out + 1] = b.label or "?"
    end
  end
  return out
end

--- Press a button by its label. Errors (listing what exists) if there is none.
function Driver:press(label)
  local b = self:findButton(label)
  if not b then
    error(string.format("no button '%s' on scene '%s'; have: %s", label, tostring(self.game.app:top().name),
      table.concat(self:labels(), ", ")), 2)
  end
  self:click(b.x + b.w / 2, b.y + b.h / 2)
end

--- Press the button if it exists. Returns whether it did.
function Driver:tryPress(label)
  if self:findButton(label) then
    self:press(label)
    return true
  end
  return false
end

--- Press a toolbar button wherever it lives: on the bar, or (narrow views, D72) inside the Tools or
--- More palette, which it opens first. Errors like press when the button is nowhere.
function Driver:pick(label)
  if self:tryPress(label) then
    return
  end
  for _, opener in ipairs({ "Tools", "More" }) do
    if self:tryPress(opener) then
      if self:tryPress(label) then
        return
      end
      self:tryPress(opener) -- not here: close it again
    end
  end
  self:press(label) -- raises the usual error listing what exists
end

-- Homestead helpers -------------------------------------------------------------------------

function Driver:scene()
  return self.game.app:top()
end

function Driver:world()
  return self.game.app.ctx.session.world
end

--- Click a tile (1-based coordinates) of the homestead, centring the camera on it if needed.
function Driver:clickTile(tx, ty)
  local scene = self:scene()
  local view = self.game.app.view
  local wx, wy = scene.camera:tileToWorld(tx, ty)
  local half = scene.camera.tileSize / 2
  local vx, vy = scene.camera:worldToView(wx + half, wy + half, view)
  if vx < 0 or vy < 0 or vx > view.w or vy > view.h then
    scene.camera:centerOn(wx + half, wy + half, view)
    vx, vy = scene.camera:worldToView(wx + half, wy + half, view)
  end
  self:click(vx, vy)
end

--- Where the homesteader stands: tile x, y.
function Driver:homesteaderTile()
  local hs = Actors.homesteader(self:world())
  return math.floor(hs.x + 0.5), math.floor(hs.y + 0.5)
end

--- Tile (x, y) of the nearest object whose definition id is in `ids` (a set or a single id), or nil.
function Driver:nearestObject(ids)
  if type(ids) == "string" then
    ids = { [ids] = true }
  end
  local world = self:world()
  local grid = world.state.grid
  local hx, hy = self:homesteaderTile()
  local best, bestD
  for anchor, obj in pairs(grid.objects) do
    if ids[obj.id] then
      local x, y = Grid.coords(grid, anchor)
      local dist = (x - hx) ^ 2 + (y - hy) ^ 2
      if not bestD or dist < bestD or (dist == bestD and anchor < best.anchor) then
        best, bestD = { x = x, y = y, anchor = anchor }, dist
      end
    end
  end
  return best and best.x, best and best.y
end

--- The free tile (walkable, no object on it) closest to the homesteader's tile offset by (dx, dy),
--- searched outwards in rings; returns x, y. Use it instead of fixed offsets, which can land on a
--- building or crop (#188).
function Driver:freeTileNear(dx, dy)
  local world = self:world()
  local grid = world.state.grid
  local hx, hy = self:homesteaderTile()
  local cx, cy = hx + (dx or 0), hy + (dy or 0)
  for r = 0, math.max(grid.w, grid.h) do
    for y = cy - r, cy + r do
      for x = cx - r, cx + r do
        if (math.abs(x - cx) == r or math.abs(y - cy) == r) and Grid.inBounds(grid, x, y) then
          local i = Grid.index(grid, x, y)
          if Grid.walkable(world, i) and not world.occupancy[i] and not (x == hx and y == hy) then
            return x, y
          end
        end
      end
    end
  end
  error("freeTileNear: no free tile", 2)
end

--- Title -> slot list -> new homestead -> playing. Leaves the homestead scene on top.
--- opts.tips = true starts the slot with the first-time tip cards on (off by default so they never
--- cover another scenario's screenshots).
function Driver:newGame(opts)
  self.game.app.ctx.tips = opts ~= nil and opts.tips == true
  -- Pin the run seed (#188): opts.seed, else the driver's (seed= on the command line, else a hash of
  -- the scenario name), so every run of a scenario sees the same world.
  local seed = opts and opts.seed or self.seed
  local freshSeed = Rng.freshSeed
  Rng.freshSeed = function()
    return seed
  end
  local ok, err = pcall(function()
    self:press("Play")
    self:press("New")
    self:press("Start")
  end)
  Rng.freshSeed = freshSeed
  if not ok then
    error(err, 0)
  end
  self:frames(10)
end

-- Screenshots -------------------------------------------------------------------------------

--- Render the current frame offscreen and write <outDir>/<prefix>_<NN>_<name>.png. Returns the path.
function Driver:shot(name)
  local n = #self.shots + 1
  local path = string.format("%s/%s_%02d_%s.png", self.outDir, self.prefix, n, name)
  -- Draw to the real backbuffer (the homestead scene draws to the screen itself, so an offscreen
  -- canvas target would be reset), then capture it at present time.
  love.graphics.origin()
  self.game:draw()
  local captured
  love.graphics.captureScreenshot(function(imageData)
    captured = imageData:encode("png")
  end)
  love.graphics.present()
  assert(captured, "screenshot capture did not run")
  local f = assert(io.open(path, "wb"), "cannot write " .. path .. " (does the directory exist?)")
  f:write(captured:getString())
  f:close()
  self.shots[n] = path
  print("shot " .. path)
  return path
end

return Driver
