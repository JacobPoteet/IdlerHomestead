-- Settings screen (D96): from the title and from the in-game Menu, scrolled, and the homestead at every
-- UI scale this window allows (steps 1x .. Auto).
return function(d)
  local UiScale = require("src.core.ui_scale")
  local ctx = d.game.app.ctx
  local tuning = ctx.tuning

  d:shot("title")
  d:press("Settings")
  d:frames(3)
  d:shot("screen_top")
  d:key("pagedown")
  d:frames(3)
  d:shot("screen_scrolled")
  d:key("escape")
  d:frames(2)

  d:newGame()
  d:frames(5)
  d:pick("Menu")
  d:frames(3)
  d:shot("menu")
  d:press("Settings")
  d:frames(3)
  d:shot("from_menu")
  d:key("escape")
  d:key("escape")
  d:frames(2)

  local app = d.game.app
  local steps = UiScale.steps(app.pixelW, app.pixelH, tuning.display, tuning.settings)
  for _, s in ipairs(steps) do
    ctx.settings:set("uiScale", s)
    d:frames(4)
    d:shot("homestead_" .. s .. "x")
  end
  -- Settings screen at the smallest scale: the note says what is shown.
  ctx.settings:set("uiScale", 1)
  d:pick("Menu")
  d:frames(3)
  d:press("Settings")
  d:frames(3)
  d:shot("screen_1x")
  d:key("escape")
  d:key("escape")
  ctx.settings:set("uiScale", "auto")
  d:frames(3)
  -- Visual options: no grain, no grade, no ambient effects.
  ctx.settings:set("gradeStrength", 0)
  ctx.settings:set("filmGrain", false)
  ctx.settings:set("ambientFx", false)
  d:frames(4)
  d:shot("homestead_plain")
end
