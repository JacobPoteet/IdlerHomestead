-- Headless LÖVE config for the performance probe: no window, graphics or audio.
function love.conf(t)
  t.identity = "idlerhomestead-perf"
  t.console = false
  t.window = false
  t.modules.audio = false
  t.modules.graphics = false
  t.modules.image = false
  t.modules.font = false
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.sound = false
  t.modules.video = false
  t.modules.window = false
end
