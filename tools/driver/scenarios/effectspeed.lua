-- Effects at 4x look like 2x (#265, D97): over the same real second the effect clock moves 1 s at 1x,
-- 2 s at 2x and 2 s at 4x. Shots of the same night scene at each speed for a visual read.
return function(d)
  d:newGame()
  local scene = d:scene()
  local session = d.game.app.ctx.session
  d:advance(4)
  for _ = 1, 3 do
    local top = d.game.app:top()
    if top.select and top.take then
      top:select(1)
      top:take()
    end
    d:frames(2, 0.05)
  end

  local function worldStep(speed)
    session:setSpeed(speed)
    d:frames(2, 0.05)
    local before = scene.renderer.time
    d:frames(20, 0.05) -- one real second
    return (scene.renderer.time - before) % 3600
  end
  local s1, s2, s4 = worldStep(1), worldStep(2), worldStep(4)
  print(string.format("effect clock per real second: 1x %.2f, 2x %.2f, 4x %.2f", s1, s2, s4))
  assert(math.abs(s2 - 2 * s1) < 0.05, "2x runs effects twice as fast as 1x")
  assert(math.abs(s4 - s2) < 0.05, "4x runs effects at the 2x rate")
  for _, speed in ipairs({ 1, 2, 4 }) do
    session:setSpeed(speed)
    d:frames(10, 0.05)
    d:shot("speed_" .. speed .. "x")
  end
end
