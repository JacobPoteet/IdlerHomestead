-- Game bootstrap: builds shared services and the app, then routes LÖVE callbacks into it.

local App = require("src.core.app")
local Input = require("src.core.input")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local Settings = require("src.core.settings")
local platform = require("src.core.platform")
local tuningLoader = require("src.core.tuning")
local Perf = require("src.core.perf")
local Debug = require("src.ui.debug_overlay")
local Assets = require("src.render.assets")
local Audio = require("src.audio.service")
local AudioBackend = require("src.audio.backend")
local Buttons = require("src.ui.buttons")
local Shaders = require("src.render.shaders")
local ScrollList = require("src.ui.scroll_list")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")
local TitleScene = require("src.scenes.title")

local Game = {}
Game.__index = Game

--- opts.backend: save backend to use instead of the player's save directory (tools/driver passes an
--- in-memory one so scripted runs never touch real saves). opts.tips = false starts new slots with
--- the first-time tip cards off.
function Game.new(opts)
  local tuning = tuningLoader.load()
  local ctx = {
    tuning = tuning,
    registry = Registry.new():loadAll(),
    store = Save.new((opts and opts.backend) or Save.loveBackend(), { slotCount = tuning.save.slotCount }),
    platform = platform,
    tips = not (opts and opts.tips == false), -- first-time tip cards for new slots (tools/driver turns them off)
    session = nil, -- set by the homestead scene while a slot is being played
  }
  -- Player settings (D96): a file apart from the save slots. Tests and the driver pass a memory backend
  -- (`opts.settingsBackend`) and then never touch the real settings file or the real window.
  local live = not (opts and opts.settingsBackend)
  ctx.settings = Settings.new((opts and opts.settingsBackend) or Save.loveBackend(), tuning):activate()
  ctx.settings:load()
  -- Audio (D100): outside the sim. Tests and the driver (settingsBackend) get the silent backend unless
  -- they pass `audioBackend`, so no audio device is ever needed.
  ctx.audio = Audio.new({
    tuning = tuning,
    settings = ctx.settings,
    backend = (opts and opts.audioBackend) or (not live and AudioBackend.null()) or nil,
    fs = opts and opts.audioFs,
  })
  Buttons.onActivate = function()
    ctx.audio:play("ui_tap")
  end
  local app = App.new(ctx)
  ctx.liveWindow = live
  ctx.settingsEnv = function()
    return ctx.game:settingsEnv()
  end
  local input = Input.new(app, tuning)
  ctx.input = input

  -- Record the last action name for the debug overlay.
  local emit = input.emit
  input.emit = function(inp, name, data)
    inp.lastAction = name
    return emit(inp, name, data)
  end

  Assets.load()
  local self = setmetatable({ app = app, input = input, debug = Debug.new(app, input) }, Game)
  ctx.game = self
  if live then
    self:restoreWindow()
  end
  self:resize(love.graphics.getDimensions())
  ctx.settings:applyAll(platform, self:settingsEnv())
  ctx.settings:onChange(function(id)
    ctx.settings:apply(id, self:settingsEnv())
    ctx.settings:save()
  end)
  app:switch(TitleScene.new())
  return self
end

--- What option apply hooks get (src/core/settings_options.lua).
function Game:settingsEnv()
  local app = self.app
  return {
    app = app,
    live = app.ctx.liveWindow,
    audio = app.ctx.audio,
    pixelW = app.pixelW,
    pixelH = app.pixelH,
    touchPrimary = platform.has("touchPrimary"),
    minTouchTarget = app.ctx.tuning.input.minTouchTarget,
    relayout = function()
      self:resize(app.pixelW, app.pixelH)
    end,
  }
end

--- Reopen at the remembered window size and position (settings override conf.lua's first-boot window).
function Game:restoreWindow()
  local s = self.app.ctx.settings
  local win = s.window
  if not (platform.has("resizableWindow") and s:get("rememberWindow") and win) or s:get("fullscreen") then
    return
  end
  local flags = {}
  local dw, dh = love.window.getDesktopDimensions()
  if win.x >= 0 and win.y >= 0 and win.x + 64 <= dw and win.y + 64 <= dh then
    flags.x, flags.y = win.x, win.y
  end
  pcall(love.window.updateMode, math.min(win.w, dw), math.min(win.h, dh), flags)
end

--- Remember the window rectangle for the next launch (windowed desktop only).
function Game:rememberWindow()
  local s = self.app.ctx.settings
  if self.app.ctx.liveWindow and platform.has("resizableWindow") and s:get("rememberWindow") and not love.window.getFullscreen() then
    local w, h = love.window.getMode()
    local x, y = love.window.getPosition()
    s:setWindow(w, h, x, y)
  end
  s:save()
end

function Game:resize(w, h)
  self.app:resize(w, h)
  Text.setScale(self.app.view.scale)
end

function Game:update(dt)
  local started = Perf.enabled and Perf.now()
  self.input:update(dt)
  self.app:update(dt)
  self.app.ctx.audio:update(dt)
  ScrollList.tick(dt, self.app.ctx.tuning.ui) -- panel lists coast after a drag (D94)
  if started then
    Perf.add("update", Perf.now() - started)
  end
end

function Game:draw()
  local started = Perf.enabled and Perf.now()
  love.graphics.clear(theme.colors.background)
  self.app:draw()
  self.debug:draw()
  if started then
    Perf.add("draw", Perf.now() - started) -- CPU time to submit the frame; the GPU runs on after this
  end
end

function Game:keypressed(key)
  if self.debug:keypressed(key) then
    return
  end
  if key == "f6" then
    -- Live reload while iterating on look & balance (GDD §12.3).
    tuningLoader.reload(self.app.ctx.tuning)
    Shaders.reloadAll()
    print("Reloaded tuning and shaders")
    return
  end
  if key == "f7" then
    -- Sound test: audition every cue (D100).
    if self.app:top().name ~= "soundtest" then
      self.app:push(require("src.scenes.sound_test").new())
    end
    return
  end
  self.input:keypressed(key)
  self.app:keypressed(key)
end

function Game:textinput(text)
  self.input:activity()
  self.app:textinput(text)
end

function Game:focus(hasFocus)
  self.app.ctx.audio:setFocus(hasFocus)
  self.app:broadcast("focus", hasFocus)
end

function Game:quit()
  self:rememberWindow()
  self.app:broadcast("quit")
end

return Game
