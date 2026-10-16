-- Key rebinding (D121, #237): the merge of defaults and overrides, conflicts and swaps, reserved keys,
-- reset, the settings-file round trip and the capture mode of Input. Pure logic, runs headless.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local KeyBindings = require("src.core.key_bindings")
local Strings = require("src.ui.controls_text")
local Input = require("src.core.input")
local Save = require("src.core.save")
local Settings = require("src.core.settings")

local tun = tuningLoader.load()
local cfg = tun.input

T.test("keys: every rebindable action has one default key and a name", function()
  T.eq(#cfg.rebindable, 13)
  local seen = {}
  for _, action in ipairs(cfg.rebindable) do
    local key = KeyBindings.defaultKey(cfg, action)
    T.truthy(key, action)
    T.falsy(seen[key], "default key used twice: " .. tostring(key))
    seen[key] = true
    T.truthy(Strings.actions[action], "no name for " .. action)
    T.falsy(KeyBindings.isReserved(cfg, key), "a default key is reserved: " .. key)
  end
end)

T.test("keys: no overrides gives the tuning defaults", function()
  local map = KeyBindings.keyMap(cfg, nil)
  for key, action in pairs(cfg.keyActions) do
    T.eq(map[key], action, key)
  end
  local n = 0
  for _ in pairs(map) do
    n = n + 1
  end
  local d = 0
  for _ in pairs(cfg.keyActions) do
    d = d + 1
  end
  T.eq(n, d)
end)

T.test("keys: an override moves the action and frees the old key", function()
  local map = KeyBindings.keyMap(cfg, { speed = "x" })
  T.eq(map.x, "speed")
  T.eq(map.space, nil)
  T.eq(map.r, "routine")
  T.eq(map.escape, "cancel", "cancel is fixed")
end)

T.test("keys: bad overrides fall back to the default", function()
  local bad = {
    speed = "escape", -- reserved
    routine = "f1", -- reserved debug key
    pageUp = "w", -- a pan key
    pageDown = 42, -- not a key name
    listHome = "", -- empty
    cancel = "q", -- not rebindable
    nonsense = "z", -- unknown action
  }
  local eff = KeyBindings.effective(cfg, bad)
  for _, action in ipairs(cfg.rebindable) do
    T.eq(eff[action], KeyBindings.defaultKey(cfg, action), action)
  end
  T.same(KeyBindings.sanitize(cfg, bad), {})
  T.same(KeyBindings.sanitize(cfg, "garbage"), {})
  T.same(KeyBindings.sanitize(cfg, nil), {})
end)

T.test("keys: clashing overrides never give one key to two actions", function()
  -- Two actions on one key: the first in display order keeps it, the other reverts.
  local eff = KeyBindings.effective(cfg, { speed = "x", routine = "x" })
  T.eq(eff.speed, "x")
  T.eq(eff.routine, "r")
  -- An override on another action's default key, that action not rebound: the override is dropped.
  local eff2 = KeyBindings.effective(cfg, { speed = "r" })
  T.eq(eff2.speed, "space")
  T.eq(eff2.routine, "r")
  -- A real swap in the file is kept.
  local eff3 = KeyBindings.effective(cfg, { speed = "r", routine = "space" })
  T.eq(eff3.speed, "r")
  T.eq(eff3.routine, "space")
  for _, o in ipairs({ { speed = "x", routine = "x" }, { speed = "r" }, { speed = "r", routine = "space" } }) do
    local used = {}
    for _, key in pairs(KeyBindings.effective(cfg, o)) do
      T.falsy(used[key], "key bound twice: " .. key)
      used[key] = true
    end
  end
end)

T.test("keys: reserved keys are refused", function()
  for _, key in ipairs({ "escape", "f1", "f2", "f3", "f6", "f7", "lshift", "return", "left", "a", "=", "kp-" }) do
    T.truthy(KeyBindings.isReserved(cfg, key), key)
    local status, result = KeyBindings.bind(cfg, {}, "speed", key)
    T.eq(status, "reserved", key)
    T.same(result, {})
  end
  T.falsy(KeyBindings.isReserved(cfg, "x"))
  T.falsy(KeyBindings.isReserved(cfg, "f4"))
end)

T.test("keys: bind a free key, bind the same key, bind an unknown action", function()
  local status, o = KeyBindings.bind(cfg, {}, "speed", "x")
  T.eq(status, "ok")
  T.same(o, { speed = "x" })
  T.eq(KeyBindings.bind(cfg, o, "speed", "x"), "same")
  T.eq(KeyBindings.bind(cfg, o, "cancel", "q"), "unknown")
  -- Binding an action back to its own default stores nothing.
  local back, o2 = KeyBindings.bind(cfg, o, "speed", "space")
  T.eq(back, "ok")
  T.same(o2, {})
end)

T.test("keys: a taken key is a conflict and changes nothing until swapped", function()
  local status, o, other = KeyBindings.bind(cfg, {}, "speed", "r")
  T.eq(status, "conflict")
  T.eq(other, "routine")
  T.same(o, {})
  local s2, swapped, who = KeyBindings.swap(cfg, {}, "speed", "r")
  T.eq(s2, "swapped")
  T.eq(who, "routine")
  local eff = KeyBindings.effective(cfg, swapped)
  T.eq(eff.speed, "r")
  T.eq(eff.routine, "space", "the other action took the old key; nothing is left unbound")
  for _, action in ipairs(cfg.rebindable) do
    T.truthy(eff[action], action)
  end
  -- A swap on a free key is just a bind; on a reserved key it is refused.
  T.eq((KeyBindings.swap(cfg, {}, "speed", "x")), "ok")
  T.eq((KeyBindings.swap(cfg, {}, "speed", "escape")), "reserved")
  -- Conflict with an override, not a default.
  local _, moved = KeyBindings.bind(cfg, {}, "speed", "x")
  local st, _, holder = KeyBindings.bind(cfg, moved, "routine", "x")
  T.eq(st, "conflict")
  T.eq(holder, "speed")
  local _, sw2 = KeyBindings.swap(cfg, moved, "routine", "x")
  local e2 = KeyBindings.effective(cfg, sw2)
  T.eq(e2.routine, "x")
  T.eq(e2.speed, "r")
end)

T.test("keys: reset one action or all", function()
  local o = { speed = "x", routine = "y" }
  T.same(KeyBindings.reset(cfg, o, "speed"), { routine = "y" })
  T.same(KeyBindings.reset(cfg, o), {})
  -- Resetting the swapped pair's one half restores both (the default key it wants is in use otherwise).
  local _, swapped = KeyBindings.swap(cfg, {}, "speed", "r")
  T.same(KeyBindings.reset(cfg, swapped, "speed"), {})
  T.eq(o.speed, "x", "the input table is not changed")
end)

T.test("keys: overrides survive the settings file round trip, and a bad file is harmless", function()
  local backend = Save.memoryBackend()
  local s = Settings.new(backend, tun)
  T.same(s:keyOverrides(), {})
  local heard
  s:onChange(function(id, value)
    heard = { id = id, value = value }
  end)
  s:setKeyOverrides({ speed = "x", routine = "bogus-reserved-not", escape = "q" })
  T.eq(heard.id, "keyBindings")
  T.truthy(s:save())
  local again = Settings.new(backend, tun)
  T.truthy(again:load())
  T.same(again:keyOverrides(), { speed = "x", routine = "bogus-reserved-not" })
  -- A file with nonsense under keys gives the defaults and does not error.
  local junk = Save.memoryBackend()
  junk.files[tun.settings.file] = require("src.core.serialize").encode({
    version = 1,
    values = {},
    keys = { speed = "escape", routine = 5, pageUp = "w" },
  })
  local s3 = Settings.new(junk, tun)
  T.truthy(s3:load())
  T.same(s3:keyOverrides(), {})
  -- Settings with no overrides write no keys entry.
  local plain = Settings.new(Save.memoryBackend(), tun)
  T.falsy(plain:encode():find("keys", 1, true))
  -- Defaults for the other options are not touched by key changes.
  T.eq(s:get("fullscreen"), tun.settings.defaults.fullscreen)
end)

local function fakeInput()
  local actions = {}
  local app = {
    view = { w = 640, h = 360, scale = 2 },
    toVirtual = function(_, x, y)
      return x, y
    end,
    action = function(_, name)
      actions[#actions + 1] = name
    end,
  }
  return Input.new(app, tun), actions
end

T.test("keys: Input follows the overrides and capture mode swallows one key", function()
  local input, actions = fakeInput()
  input:keypressed("space")
  T.eq(actions[#actions], "speed")
  input:setKeyOverrides({ speed = "x" })
  input:keypressed("space")
  T.eq(#actions, 1, "the old key does nothing now")
  input:keypressed("x")
  T.eq(actions[#actions], "speed")
  input:keypressed("escape")
  T.eq(actions[#actions], "cancel", "cancel stays on Esc")

  local got
  input:beginCapture(function(key)
    got = key
  end)
  input:keypressed("x")
  T.eq(got, "x")
  T.eq(#actions, 3, "a captured key fires no action")
  input:keypressed("x")
  T.eq(#actions, 4, "capture ends after one key")
  input:beginCapture(function() end)
  input:endCapture()
  input:keypressed("r")
  T.eq(actions[#actions], "routine")
end)

T.test("keys: text helpers name keys and every action", function()
  T.eq(Strings.keyName("space"), "Space")
  T.eq(Strings.keyName("pagedown"), "Page Down")
  T.eq(Strings.keyName("kp5"), "Num 5")
  T.eq(Strings.keyName("r"), "R")
  T.truthy(Strings.conflict("r", "routine"):find("Start routine", 1, true))
end)
