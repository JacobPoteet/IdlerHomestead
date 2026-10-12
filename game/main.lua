https = nil
local overlayStats = require("lib.overlayStats")
local runtimeLoader = require("runtime.loader")
local Game = require("src.game")

local game

function love.load()
  https = runtimeLoader.loadHTTPS()
  love.graphics.setDefaultFilter("nearest", "nearest")
  game = Game.new()
  overlayStats.load() -- Should always be called last
end

function love.update(dt)
  game:update(dt)
  overlayStats.update(dt) -- Should always be called last
end

function love.draw()
  game:draw()
  overlayStats.draw() -- Should always be called last
end

function love.resize(w, h)
  game:resize(w, h)
end

function love.keypressed(key)
  game:keypressed(key)
  overlayStats.handleKeyboard(key) -- Should always be called last
end

function love.textinput(text)
  game:textinput(text)
end

function love.mousepressed(x, y, button, istouch)
  game.input:mousepressed(x, y, button, istouch)
end

function love.mousemoved(x, y, dx, dy, istouch)
  game.input:mousemoved(x, y, dx, dy, istouch)
end

function love.mousereleased(x, y, button, istouch)
  game.input:mousereleased(x, y, button, istouch)
end

function love.wheelmoved(x, y)
  game.input:wheelmoved(x, y)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  game.input:touchpressed(id, x, y)
  overlayStats.handleTouch(id, x, y, dx, dy, pressure) -- Should always be called last
end

function love.touchmoved(id, x, y)
  game.input:touchmoved(id, x, y)
end

function love.touchreleased(id, x, y)
  game.input:touchreleased(id, x, y)
end

function love.focus(hasFocus)
  game:focus(hasFocus)
end

function love.quit()
  game:quit()
  return false
end
