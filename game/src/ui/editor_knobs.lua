-- Plain tuning numbers the editor can change live (pure data and logic, tested headless; GDD D133). Each knob
-- is one number under tuning.visuals, with the range and step the editor's - and + buttons use. The Wind
-- panel lists the WIND groups; a new panel adds its own groups here.

local M = {}

--- A knob: { path = { "wind", "amplitude" } (under tuning.visuals), label, min, max, step, unit }.
local function knob(path, label, min, max, step, unit)
  return { path = path, label = label, min = min, max = max, step = step, unit = unit or "" }
end

--- The wind groups: everything that moves with the wind, in the order listed.
M.WIND = {
  {
    title = "Sway",
    hint = "Crops, brush and tree canopies (sway.glsl).",
    knobs = {
      knob({ "wind", "amplitude" }, "Lean", 0, 8, 0.2, " px"),
      knob({ "wind", "speed" }, "Speed", 0, 3, 0.05, " rad/s"),
      knob({ "wind", "lean" }, "Steady lean", 0, 1, 0.05),
      knob({ "wind", "gust" }, "Gust swell", 0, 1, 0.05),
      knob({ "wind", "spread" }, "Gust spread", 0, 0.5, 0.01, " rad/tile"),
      knob({ "wind", "jitter" }, "Plant jitter", 0, 1, 0.05),
    },
  },
  {
    title = "Drift",
    hint = "What the wind pushes along.",
    knobs = {
      knob({ "weather", "clouds", "speed" }, "Cloud shadows", 0, 20, 1, " px/s"),
      knob({ "mist", "drift" }, "Mist", 0, 10, 0.5, " px/s"),
      knob({ "dust", "speed" }, "Dust motes", 0, 40, 1, " px/s"),
      knob({ "weather", "rain", "slant" }, "Rain lean", 0, 2, 0.05),
    },
  },
}

--- Every knob of `groups`, flat.
function M.all(groups)
  local list = {}
  for _, group in ipairs(groups) do
    for _, k in ipairs(group.knobs) do
      list[#list + 1] = k
    end
  end
  return list
end

--- The table a knob lives in and its key: ( visuals.wind, "amplitude" ).
local function owner(tuning, k)
  local t = tuning.visuals
  for i = 1, #k.path - 1 do
    t = t[k.path[i]]
  end
  return t, k.path[#k.path]
end

function M.get(tuning, k)
  local t, key = owner(tuning, k)
  return t[key]
end

local function set(tuning, k, value)
  local t, key = owner(tuning, k)
  t[key] = value
end

--- Step knob `k` by `dir` (+1 or -1), stopping at its limits. Returns the new value, or nil if unchanged.
function M.change(tuning, k, dir)
  local old = M.get(tuning, k)
  local new = math.max(k.min, math.min(k.max, old + dir * k.step))
  new = math.floor(new / k.step + 0.5) * k.step -- no 0.1 + 0.2 drift
  if new == old then
    return nil
  end
  set(tuning, k, new)
  return new
end

--- { [joined path] = value } for every knob of `groups`.
function M.snapshot(tuning, groups)
  local snap = {}
  for _, k in ipairs(M.all(groups)) do
    snap[table.concat(k.path, ".")] = M.get(tuning, k)
  end
  return snap
end

function M.apply(tuning, groups, snap)
  for _, k in ipairs(M.all(groups)) do
    set(tuning, k, snap[table.concat(k.path, ".")])
  end
end

function M.changed(tuning, groups, snap)
  for _, k in ipairs(M.all(groups)) do
    if M.get(tuning, k) ~= snap[table.concat(k.path, ".")] then
      return true
    end
  end
  return false
end

--- Lines `visuals.wind.amplitude = 2.4` for the knobs that differ from `snap` (all of them when nil), to
--- find and edit in data/tuning/visuals.lua.
function M.export(tuning, groups, snap)
  local lines = {}
  for _, k in ipairs(M.all(groups)) do
    local path = table.concat(k.path, ".")
    local value = M.get(tuning, k)
    if not snap or snap[path] ~= value then
      lines[#lines + 1] = string.format("visuals.%s = %.4g -- %s", path, value, k.label)
    end
  end
  return table.concat(lines, "\n")
end

--- The text of a knob's value.
function M.format(k, value)
  local decimals = k.step < 0.1 and 2 or (k.step < 1 and 1 or 0)
  return string.format("%." .. decimals .. "f", value) .. k.unit
end

return M
