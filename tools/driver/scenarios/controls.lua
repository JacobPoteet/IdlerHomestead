-- Settings > Controls (D121, #237): open the screen from Settings, start a rebind, finish it, hit a
-- reserved key, a conflict (swap and keep), per-row and global reset.
return function(d)
  local ctx = d.game.app.ctx
  local settings = ctx.settings

  d:press("Settings")
  d:frames(3)
  d:key("end") -- scroll the list to its end so the Controls button is on screen
  d:frames(3)
  d:shot("settings_end")
  d:press("Keyboard controls")
  d:frames(3)
  d:shot("screen")

  -- Rebind Game speed: tap its key, see "Press a key...", press X.
  d:press("Space")
  d:frames(2)
  assert(d:scene().waiting == "speed", "waiting for a key")
  d:shot("waiting")
  d:key("return") -- reserved: still waiting, with a message
  assert(d:scene().waiting == "speed", "a reserved key keeps waiting")
  d:shot("reserved")
  d:key("x")
  assert(settings:keyOverrides().speed == "x", "speed is on X")
  d:shot("bound")

  -- The new key works in the game's input and the old one does nothing.
  local seen = {}
  local app = d.game.app
  local emit = ctx.input.emit
  ctx.input.emit = function(inp, name, data)
    seen[#seen + 1] = name
    return emit(inp, name, data)
  end
  ctx.input:keypressed("space")
  ctx.input:keypressed("x")
  ctx.input.emit = emit
  assert(#seen == 1 and seen[1] == "speed", "only X is game speed now")

  -- A conflict: give Start routine the key X.
  d:press("R")
  d:key("x")
  assert(d:scene().pending, "a conflict asks first")
  d:shot("conflict")
  d:press("Keep")
  assert(settings:keyOverrides().routine == nil, "Keep changed nothing")
  d:press("R")
  d:key("x")
  d:press("Swap")
  assert(settings:keyOverrides().routine == "x" and settings:keyOverrides().speed == "r", "swapped")
  d:shot("swapped")

  -- Escape cancels a rebind; Reset puts one row back; Reset all clears the rest.
  d:press("Home")
  d:frames(2)
  d:key("escape")
  assert(d:scene().waiting == nil and app:top().name == "controls", "Esc only cancels the rebind")
  d:press("Reset")
  d:frames(2)
  d:shot("reset_row")
  d:press("Reset all")
  d:frames(2)
  assert(next(settings:keyOverrides()) == nil, "all back to default")
  d:shot("reset_all")

  -- Keep one rebind, leave, and see it saved in the settings file (not a save slot).
  d:press("Space")
  d:key("x")
  d:press("Done")
  d:frames(2)
  assert(settings:encode():find('"x"', 1, true), "the override is in the settings file text")
end
