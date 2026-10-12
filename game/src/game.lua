-- Game bootstrap: builds shared services and the app, then routes LÖVE callbacks into it.

local App = require("src.core.app")
local Input = require("src.core.input")
local Registry = require("src.core.registry")
local Save = require("src.core.save")
local platform = require("src.core.platform")
local tuningLoader = require("src.core.tuning")
local Debug = require("src.ui.debug_overlay")
local Assets = require("src.render.assets")
local Shaders = require("src.render.shaders")
local Text = require("src.ui.text")
local theme = require("src.ui.theme")
local TitleScene = require("src.scenes.title")

local Game = {}
Game.__index = Game

function Game.new()
  local tuning = tuningLoader.load()
  local ctx = {
    tuning = tuning,
    registry = Registry.new():loadAll(),
    store = Save.new(Save.loveBackend(), { slotCount = tuning.save.slotCount }),
    platform = platform,
    session = nil, -- set by the homestead scene while a slot is being played
  }
  local app = App.new(ctx)
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
  self:resize(love.graphics.getDimensions())
  app:switch(TitleScene.new())
  return self
end

function Game:resize(w, h)
  self.app:resize(w, h)
  Text.setScale(self.app.view.scale)
end

function Game:update(dt)
  self.input:update(dt)
  self.app:update(dt)
end

function Game:draw()
  love.graphics.clear(theme.colors.background)
  self.app:draw()
  self.debug:draw()
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
  self.input:keypressed(key)
  self.app:keypressed(key)
end

function Game:textinput(text)
  self.input:activity()
  self.app:textinput(text)
end

function Game:focus(hasFocus)
  self.app:broadcast("focus", hasFocus)
end

function Game:quit()
  self.app:broadcast("quit")
end

return Game
