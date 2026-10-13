-- Player settings (D96, #50): defaults, corruption, round trip, option registry, UI scale steps and
-- clamping, and that every layout fits at every allowed scale. Pure logic, runs headless.
local T = require("harness")
local tuningLoader = require("src.core.tuning")
local Save = require("src.core.save")
local Settings = require("src.core.settings")
local Options = require("src.core.settings_options")
local UiScale = require("src.core.ui_scale")
local Layout = require("src.ui.settings_layout")

local tun = tuningLoader.load()
local cfg, display = tun.settings, tun.display
local minTouch = tun.input.minTouchTarget

local function new(files)
  local backend = Save.memoryBackend()
  for k, v in pairs(files or {}) do
    backend.files[k] = v
  end
  return Settings.new(backend, tun), backend
end

local desktopPlatform = { has = function() return true end }
local phonePlatform = {
  has = function(name)
    return name == "touchPrimary"
  end,
}

T.test("settings: a fresh store holds the tuning defaults", function()
  local s = new()
  for id, v in pairs(cfg.defaults) do
    T.eq(s:get(id), v, id)
  end
  T.eq(#s.options, 9)
end)

T.test("settings: every option has a default, a valid kind and a valid default value", function()
  local s = new()
  for _, opt in ipairs(s.options) do
    T.truthy(opt.kind == "toggle" or opt.kind == "choice" or opt.kind == "slider", opt.id .. " kind")
    T.truthy(cfg.defaults[opt.id] ~= nil, opt.id .. " has no default")
    T.eq(s:validate(opt, cfg.defaults[opt.id]), cfg.defaults[opt.id], opt.id .. " default is not valid")
  end
  for id in pairs(cfg.defaults) do
    T.truthy(s.byId[id], "default for undeclared option " .. id)
  end
end)

T.test("settings: values round trip through the file", function()
  local s, backend = new()
  s:set("uiScale", 1)
  s:set("filmGrain", false)
  s:set("gradeStrength", 0.5)
  s:set("idleDelay", 2)
  s:setWindow(1000, 700, 40, 50)
  T.truthy(s:save())
  local again = Settings.new(backend, tun)
  T.truthy(again:load())
  T.eq(again:get("uiScale"), 1)
  T.eq(again:get("filmGrain"), false)
  T.eq(again:get("gradeStrength"), 0.5)
  T.eq(again:get("idleDelay"), 2)
  T.eq(again.window.w, 1000)
  T.eq(again.window.x, 40)
end)

T.test("settings: a missing or corrupt file gives defaults and never errors", function()
  local s = new()
  T.falsy(s:load())
  for _, junk in ipairs({ "", "not lua {{{", "return os.exit()", "{ values = 5 }", "nil", "{ values = { uiScale = 'huge', filmGrain = 3, nope = 1 } }", "\27Lua" }) do
    local c = new({ [cfg.file] = junk })
    c:load()
    T.eq(c:get("uiScale"), cfg.defaults.uiScale, junk)
    T.eq(c:get("filmGrain"), cfg.defaults.filmGrain, junk)
  end
end)

T.test("settings: bad values in a good file fall back one by one", function()
  local s = new({ [cfg.file] = "{ version = 1, values = { uiScale = 2, filmGrain = \"yes\", gradeStrength = 7, idleDelay = 3 } }" })
  T.truthy(s:load())
  T.eq(s:get("uiScale"), 2)
  T.eq(s:get("filmGrain"), cfg.defaults.filmGrain)
  T.eq(s:get("gradeStrength"), 1, "sliders clamp into range")
  T.eq(s:get("idleDelay"), cfg.defaults.idleDelay, "a choice not offered is rejected")
end)

T.test("settings: sliders snap to their step, set() rejects invalid values and tells listeners", function()
  local s = new()
  local seen = {}
  s:onChange(function(id, v)
    seen[#seen + 1] = id .. "=" .. tostring(v)
  end)
  s:set("gradeStrength", 0.4)
  T.eq(s:get("gradeStrength"), 0.5)
  T.falsy(s:set("uiScale", 99))
  T.falsy(s:set("fullscreen", "yes"))
  s:set("fullscreen", true)
  s:set("fullscreen", true)
  T.eq(#seen, 2, "only real changes notify")
  s:reset()
  T.eq(s:get("fullscreen"), false)
end)

T.test("settings: the save backend is never the real one in tests (writes land in memory)", function()
  local s, backend = new()
  s:save()
  T.truthy(backend.files[cfg.file])
end)

T.test("settings: desktop-only options need the capability", function()
  local s = new()
  local function ids(platform)
    local out = {}
    for _, opt in ipairs(s:visible(platform)) do
      out[opt.id] = true
    end
    return out
  end
  T.truthy(ids(desktopPlatform).fullscreen)
  T.falsy(ids(phonePlatform).fullscreen)
  T.falsy(ids(phonePlatform).vsync)
  T.truthy(ids(phonePlatform).uiScale)
end)

T.test("settings: Settings.read answers from the active store and falls back otherwise", function()
  local s = new()
  s:activate()
  s:set("filmGrain", false)
  T.eq(Settings.read("filmGrain", true), false)
  s:set("filmGrain", true)
  T.eq(Settings.read("filmGrain", false), true)
  T.eq(Settings.read("noSuchThing", 7), 7)
end)

-- UI scale ---------------------------------------------------------------------------------------

local SIZES = {
  { name = "desktop", w = 1280, h = 720 },
  { name = "hd", w = 1920, h = 1080 },
  { name = "4k", w = 3840, h = 2160 },
  { name = "phone", w = 390, h = 844 },
  { name = "landscape", w = 844, h = 390 },
  { name = "widget", w = 640, h = 360 },
  { name = "narrow", w = 340, h = 600 },
}

T.test("ui scale: auto matches the original rule", function()
  T.eq(UiScale.auto(1280, 720, display), 2)
  T.eq(UiScale.auto(1920, 1080, display), 3)
  T.eq(UiScale.auto(390, 844, display), 1)
  T.eq(UiScale.auto(100, 100, display), 1)
end)

T.test("ui scale: steps run from 1 up to what the window fits, capped", function()
  T.eq(#UiScale.steps(1280, 720, display, cfg), 2)
  T.eq(#UiScale.steps(1920, 1080, display, cfg), 3)
  T.eq(#UiScale.steps(3840, 2160, display, cfg), cfg.uiScaleMax)
  T.eq(#UiScale.steps(390, 844, display, cfg), 1)
end)

T.test("ui scale: a setting too big for the window is clamped down", function()
  local scale, clamped = UiScale.effective(4, 1280, 720, display, cfg)
  T.eq(scale, 2)
  T.truthy(clamped)
  scale, clamped = UiScale.effective(1, 1280, 720, display, cfg)
  T.eq(scale, 1)
  T.falsy(clamped)
  T.eq((UiScale.effective("auto", 1280, 720, display, cfg)), 2)
  T.eq((UiScale.effective(3, 390, 844, display, cfg)), 1)
end)

T.test("ui scale: every allowed scale keeps at least the minimum virtual view (or the whole small window)", function()
  for _, size in ipairs(SIZES) do
    for _, s in ipairs(UiScale.steps(size.w, size.h, display, cfg)) do
      local vw, vh = size.w / s, size.h / s
      T.truthy(vw >= math.min(size.w, display.minVirtualWidth) and vh >= math.min(size.h, display.minVirtualHeight), size.name .. " at " .. s .. "x")
      T.truthy(UiScale.touchPixels(s, minTouch) >= minTouch, "physical touch size")
    end
  end
end)

T.test("ui scale: the touch warning shows only for a fixed scale below Auto on a touch device", function()
  local s = new()
  local opt = s.byId.uiScale
  local env = { pixelW = 2560, pixelH = 1600, touchPrimary = true, minTouchTarget = minTouch }
  T.falsy(opt.note(s, env):find("small for fingers"))
  s:set("uiScale", 1)
  T.truthy(opt.note(s, env):find("small for fingers"))
  env.touchPrimary = false
  T.falsy(opt.note(s, env):find("small for fingers"))
end)

T.test("ui scale: the choices disable sizes the window cannot show", function()
  local s = new()
  local entries = Options.choicesOf(s.byId.uiScale, s, { pixelW = 1280, pixelH = 720 })
  local enabled = {}
  for _, e in ipairs(entries) do
    enabled[tostring(e.value)] = e.enabled ~= false
  end
  T.truthy(enabled.auto and enabled["1"] and enabled["2"])
  T.falsy(enabled["3"] or enabled["4"])
end)

-- Layout -----------------------------------------------------------------------------------------

T.test("settings screen: panel, list and buttons fit at every window size and allowed scale", function()
  for _, size in ipairs(SIZES) do
    for _, s in ipairs(UiScale.steps(size.w, size.h, display, cfg)) do
      local view = { w = size.w / s, h = size.h / s }
      local P = Layout.panel(view, cfg, minTouch)
      local where = size.name .. " at " .. s .. "x"
      local b = P.box
      T.truthy(b.x >= 0 and b.y >= 0 and b.x + b.w <= view.w and b.y + b.h <= view.h, where .. ": panel off screen")
      T.truthy(P.list.h >= minTouch * 2, where .. ": list window too short (" .. P.list.h .. ")")
      for _, r in ipairs({ P.done, P.defaults }) do
        T.truthy(r.w >= minTouch and r.h >= minTouch, where .. ": button too small")
        T.truthy(r.x >= b.x and r.x + r.w <= b.x + b.w and r.y >= b.y and r.y + r.h <= b.y + b.h, where .. ": button outside the panel")
      end
      T.truthy(P.done.x >= P.defaults.x + P.defaults.w, where .. ": buttons overlap")
      -- A choice row with 5 entries wraps instead of squeezing below the touch size.
      local inner = b.w - 2 * Layout.PAD - tun.ui.scrollBarWidth - 4
      local rects = Layout.segments(0, 0, inner, 5, Layout.controlH(minTouch), cfg.minSegment)
      for _, r in ipairs(rects) do
        T.truthy(r.w >= minTouch and r.x + r.w <= inner + 0.01, where .. ": segment size")
      end
    end
  end
end)
