-- Setting declarations (GDD D96, #50). Each option is data: adding one (an audio volume once #48
-- lands, say) is one entry here plus a default in data/tuning/settings.lua.
--
-- Option fields:
--   id          key in the settings file and in tuning.settings.defaults
--   label       shown on the Settings screen
--   kind        "toggle" | "choice" | "slider"
--   group       heading the option is listed under
--   requires    optional platform capability (src/core/platform.lua) the option needs
--   values      choice: the allowed values;  min/max/step: slider range
--   choices(env) choice: entries { value, label, enabled = true } to show (defaults to `values`)
--   format(v)   text for the current value (toggle shows On/Off; slider shows the value)
--   note(settings, env) optional line of help drawn under the control
--   apply(value, env)   optional hook run after a change and once at boot; env = { app, live, relayout, ... }
--                       `live` is false in tests and the screenshot driver, which must not touch the real window.

local UiScale = require("src.core.ui_scale")

local M = {}

local function percent(v)
  return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local function multiplier(v)
  if v == 1 then
    return "Normal"
  end
  return string.format("x%g", v)
end

-- A volume slider moved: play a short sound at the new level so it can be judged (live only; the
-- audio service reads the slider values itself every frame).
local function preview(_, env)
  if env.live and env.audio then
    env.audio:preview()
  end
end

--- Build the option list for a loaded tuning root.
function M.build(tuning)
  local cfg = tuning.settings
  local display = tuning.display

  local scaleValues = { "auto" }
  for s = 1, cfg.uiScaleMax do
    scaleValues[#scaleValues + 1] = s
  end

  local list = {
    {
      id = "uiScale",
      label = "UI size",
      kind = "choice",
      group = "Display",
      values = scaleValues,
      choices = function(_, env)
        local out = {}
        local auto = UiScale.auto(env.pixelW, env.pixelH, display)
        for _, v in ipairs(scaleValues) do
          if v == "auto" then
            out[#out + 1] = { value = v, label = "Auto" }
          else
            out[#out + 1] = { value = v, label = v .. "x", enabled = v <= math.min(auto, cfg.uiScaleMax) }
          end
        end
        return out
      end,
      note = function(settings, env)
        local scale, clamped = UiScale.effective(settings:get("uiScale"), env.pixelW, env.pixelH, display, cfg)
        local auto = UiScale.auto(env.pixelW, env.pixelH, display)
        local text = string.format("Showing %dx%d units at %dx.", math.floor(env.pixelW / scale), math.floor(env.pixelH / scale), scale)
        if clamped then
          text = text .. " The chosen size does not fit this window."
        elseif auto < cfg.uiScaleMax then
          text = text .. " Larger sizes need a bigger window."
        end
        if env.touchPrimary and settings:get("uiScale") ~= "auto" and scale < auto and UiScale.touchPixels(scale, env.minTouchTarget) < cfg.comfortTouchPixels then
          text = text .. " Buttons get small for fingers."
        end
        return text
      end,
      apply = function(_, env)
        if env.relayout then
          env.relayout()
        end
      end,
    },
    {
      id = "fullscreen",
      label = "Fullscreen",
      kind = "toggle",
      group = "Display",
      requires = "resizableWindow",
      apply = function(v, env)
        if env.live then
          love.window.setFullscreen(v, "desktop")
        end
      end,
    },
    {
      id = "vsync",
      label = "Vertical sync",
      kind = "toggle",
      group = "Display",
      requires = "resizableWindow",
      apply = function(v, env)
        if env.live then
          love.window.setVSync(v and 1 or 0)
        end
      end,
    },
    {
      id = "rememberWindow",
      label = "Remember window",
      kind = "toggle",
      group = "Display",
      requires = "resizableWindow",
      note = function()
        return "Reopen at the last window size and position."
      end,
    },
    {
      id = "reduceMotion",
      label = "Reduce motion",
      kind = "toggle",
      group = "Visuals",
      note = function()
        return "Stills heat shimmer and wind sway."
      end,
    },
    { id = "filmGrain", label = "Film grain", kind = "toggle", group = "Visuals" },
    {
      id = "gradeStrength",
      label = "Colour grade",
      kind = "slider",
      group = "Visuals",
      min = cfg.gradeStrength.min,
      max = cfg.gradeStrength.max,
      step = cfg.gradeStrength.step,
      format = percent,
    },
    {
      id = "ambientFx",
      label = "Ambient and weather effects",
      kind = "toggle",
      group = "Visuals",
      note = function()
        return "Fireflies, dust, mist, cloud shadows and rain streaks."
      end,
    },
    {
      id = "volumeMaster",
      label = "Master volume",
      kind = "slider",
      group = "Sound",
      min = cfg.volume.min,
      max = cfg.volume.max,
      step = cfg.volume.step,
      format = percent,
      apply = preview,
    },
    {
      id = "volumeEffects",
      label = "Effects",
      kind = "slider",
      group = "Sound",
      min = cfg.volume.min,
      max = cfg.volume.max,
      step = cfg.volume.step,
      format = percent,
      apply = preview,
    },
    {
      id = "volumeAmbience",
      label = "Ambience",
      kind = "slider",
      group = "Sound",
      min = cfg.volume.min,
      max = cfg.volume.max,
      step = cfg.volume.step,
      format = percent,
      note = function()
        return "Birds, creek, wind, rain and fire."
      end,
    },
    {
      id = "volumeMusic",
      label = "Music",
      kind = "slider",
      group = "Sound",
      min = cfg.volume.min,
      max = cfg.volume.max,
      step = cfg.volume.step,
      format = percent,
    },
    {
      id = "muteUnfocused",
      label = "Mute when unfocused",
      kind = "toggle",
      group = "Sound",
      requires = "resizableWindow",
    },
    {
      id = "idleDelay",
      label = "Idle takeover delay",
      kind = "choice",
      group = "Play",
      values = cfg.idleDelayChoices,
      format = multiplier,
      note = function(settings, env)
        local idle = tuning.idle
        local secs = math.max(idle.minTakeoverDelay, math.floor(idle.takeoverDelay * settings:get("idleDelay") + 0.5))
        return string.format("The homesteader follows the Routine after about %d s without input.", secs)
      end,
    },
  }
  return list
end

--- Entries { value, label, enabled } of a choice option for the Settings screen.
function M.choicesOf(opt, settings, env)
  if opt.choices then
    return opt.choices(settings, env)
  end
  local out = {}
  for _, v in ipairs(opt.values) do
    out[#out + 1] = { value = v, label = opt.format and opt.format(v) or tostring(v) }
  end
  return out
end

--- Text for an option's current value.
function M.valueText(opt, value)
  if opt.kind == "toggle" then
    return value and "On" or "Off"
  elseif opt.format then
    return opt.format(value)
  end
  return tostring(value)
end

return M
