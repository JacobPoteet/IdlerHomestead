-- LÖVE config for the screenshot driver: a real window (the game is rendered for real), but a
-- separate save identity so nothing here can touch the player's saves.
function love.conf(t)
  t.identity = "idlerhomestead-driver"
  t.console = false
  t.window.title = "Idler Homestead driver"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.vsync = 0
  t.window.highdpi = false -- pixel sizes in screenshots match the requested window size
  t.modules.physics = false
  t.modules.video = false
  t.modules.joystick = false
end
