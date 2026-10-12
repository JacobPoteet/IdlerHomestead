-- The homestead HUD at the current window size: the day, the toolbar with a tool in hand,
-- and bedtime (the status badge must say the routine is resting).
return function(d)
  d:newGame()
  d:frames(10)
  d:shot("start")
  d:press("Plan")
  d:shot("plan_mode")
  d:key("escape")
  -- Run up to the first moment the routine can't start (bedtime), before she's asleep.
  while d:scene().session:canStartRoutine() do
    d:advance(0.05)
  end
  d:frames(2)
  d:shot("bedtime")
end
