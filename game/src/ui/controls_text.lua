-- Text for the Settings > Controls screen (D121, #237): action names, what each does, how keys are named
-- and the messages. Pure, so tests can check that every rebindable action has a name.

local M = {}

M.title = "Controls"
M.open = "Keyboard controls"
M.hint = "Tap a key, then press the new one. Esc cancels."
M.waiting = "Press a key..."
M.resetRow = "Reset"
M.resetAll = "Reset all"
M.swap = "Swap"
M.keep = "Keep"
M.fixedNote = "Esc (back), the arrow keys and WASD (pan), + and - (zoom) are fixed."

M.actions = { -- action name (tuning.input.rebindable) -> { name, what it does }
  speed = { "Game speed", "Cycle the game speed" },
  routine = { "Start routine", "Start the idle routine now" },
  pageUp = { "Page up", "Scroll an open list up a page" },
  pageDown = { "Page down", "Scroll an open list down a page" },
  listHome = { "List top", "Jump to the top of an open list" },
  listEnd = { "List bottom", "Jump to the bottom of an open list" },
}

local KEY_NAMES = { -- LÖVE key name -> shown name, where capitalising it is not enough
  pageup = "Page Up",
  pagedown = "Page Down",
  capslock = "Caps Lock",
  ["kp+"] = "Num +",
  ["kp-"] = "Num -",
}

--- Shown name of a LÖVE key name: "space" -> "Space", "r" -> "R", "kp5" -> "Num 5".
function M.keyName(key)
  if KEY_NAMES[key] then
    return KEY_NAMES[key]
  end
  local kp = key:match("^kp(.+)$")
  if kp then
    return "Num " .. kp:upper()
  end
  return key:sub(1, 1):upper() .. key:sub(2)
end

function M.reserved(key)
  return string.format("%s is reserved. Press another key, or Esc to cancel.", M.keyName(key))
end

function M.conflict(key, otherAction)
  return string.format("%s is already used for %s. Swap the two keys?", M.keyName(key), M.actions[otherAction][1])
end

function M.bound(action, key)
  return string.format("%s is now %s.", M.actions[action][1], M.keyName(key))
end

function M.swapped(action, key, other, otherKey)
  return string.format(
    "%s is now %s; %s moved to %s.",
    M.actions[action][1],
    M.keyName(key),
    M.actions[other][1],
    M.keyName(otherKey)
  )
end

return M
