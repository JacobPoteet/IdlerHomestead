-- The shader editor's data (pure, no drawing, tested headless): which effects the editor lists, how a
-- control steps a value, and the snapshot / compare / export of tuning.visuals.dither (GDD D133).
-- The editor changes the live tuning tables, so the next frame draws with the new value; F6 (reload
-- tuning) puts the files' values back.

local M = {}

--- The effects listed, in order. Every key of tuning.visuals.dither (but `algorithms` and `blueSize`) must be
--- here (test_editor_shaders checks it), so a new dithered shader cannot be left out of the editor.
M.ENTRIES = {
  { id = "light", title = "Night light pools", shader = "light.glsl", hint = "Campfire, lamps and windows at night." },
  { id = "heat", title = "Heat shimmer column", shader = "grade.glsl", hint = "Above a burning campfire or stove." },
  {
    id = "shadows",
    title = "Sun shadows",
    shader = "shadow_composite.glsl",
    hint = "Daytime, anything standing in the sun.",
  },
  {
    id = "clouds",
    title = "Cloud shadows",
    shader = "clouds.glsl",
    hint = "Drifting over the land; set cloudy weather.",
  },
  { id = "mist", title = "Morning mist", shader = "mist.glsl", hint = "Early on a calm morning, by the creek." },
  { id = "sunbeams", title = "Sunbeams", shader = "sunbeams.glsl", hint = "Slanted shafts at low sun on a clear day." },
  { id = "vignette", title = "Vignette", shader = "grade.glsl", hint = "The dark rim of the view; steps 0 is smooth." },
  {
    id = "lens",
    title = "Lenses (Power, Water)",
    shader = "lens.glsl",
    hint = "Pools, bands and coverage; turn a lens on with the buttons above.",
  },
  {
    id = "plate",
    title = "Frosted plates",
    shader = "ui_plate.glsl",
    hint = "The world seen through HUD and panel plates.",
  },
}

--- The fields a control can change, in the order they are listed, with their limits.
M.FIELDS = {
  algorithm = { label = "Pattern" },
  alpha = { label = "Pixel alpha", min = 0.1, max = 1, step = 0.05 },
  steps = { label = "Steps", min = 0, max = 16, step = 1, zero = "smooth" },
  amount = { label = "Amount", min = 0, max = 1, step = 0.05 },
  scale = { label = "Cell size", min = 1, max = 4, step = 1 },
}
M.FIELD_ORDER = { "algorithm", "steps", "alpha", "amount", "scale" }

--- The fields of the effect table `cfg` that the editor can change (the ones it has), in order.
function M.fields(cfg)
  local list = {}
  for _, name in ipairs(M.FIELD_ORDER) do
    if rawget(cfg, name) ~= nil then
      list[#list + 1] = name
    end
  end
  return list
end

local function dither(tuning)
  return tuning.visuals.dither
end

--- Step one field of effect `id` by `dir` (+1 or -1): an algorithm cycles through the list, a number
--- moves by its step and stops at its limits. Returns the new value, or nil when nothing changed.
function M.change(tuning, id, field, dir)
  local d = dither(tuning)
  local cfg = d[id]
  local old = cfg[field]
  local new
  if field == "algorithm" then
    local list = d.algorithms
    for i, name in ipairs(list) do
      if name == old then
        new = list[(i - 1 + dir) % #list + 1]
        break
      end
    end
  else
    local f = M.FIELDS[field]
    new = math.max(f.min, math.min(f.max, old + dir * f.step))
    new = math.floor(new / f.step + 0.5) * f.step -- no 0.1 + 0.2 drift
  end
  if new == nil or new == old then
    return nil
  end
  cfg[field] = new
  return new
end

--- A copy of every effect's values: { [id] = { field = value } }.
function M.snapshot(tuning)
  local snap = {}
  for _, entry in ipairs(M.ENTRIES) do
    local copy = {}
    for _, field in ipairs(M.fields(dither(tuning)[entry.id])) do
      copy[field] = dither(tuning)[entry.id][field]
    end
    snap[entry.id] = copy
  end
  return snap
end

--- Write a snapshot's values back into the live tuning.
function M.apply(tuning, snap)
  for id, values in pairs(snap) do
    for field, value in pairs(values) do
      dither(tuning)[id][field] = value
    end
  end
end

--- Has effect `id` changed from the snapshot?
function M.changed(tuning, snap, id)
  for field, value in pairs(snap[id]) do
    if dither(tuning)[id][field] ~= value then
      return true
    end
  end
  return false
end

--- Ids of the effects that differ from the snapshot.
function M.changedIds(tuning, snap)
  local ids = {}
  for _, entry in ipairs(M.ENTRIES) do
    if M.changed(tuning, snap, entry.id) then
      ids[#ids + 1] = entry.id
    end
  end
  return ids
end

local function literal(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return (string.format("%.4g", value))
end

--- The effect tables as Lua text to paste into data/tuning/visuals.lua (inside `dither = { ... }`).
--- With `onlyChanged` (a snapshot), just the effects that differ from it.
function M.export(tuning, onlyChanged)
  local lines = {}
  for _, entry in ipairs(M.ENTRIES) do
    if not onlyChanged or M.changed(tuning, onlyChanged, entry.id) then
      local cfg = dither(tuning)[entry.id]
      local parts = {}
      for _, field in ipairs(M.fields(cfg)) do
        parts[#parts + 1] = string.format("%s = %s", field, literal(cfg[field]))
      end
      lines[#lines + 1] = string.format("%s = { %s }, -- %s", entry.id, table.concat(parts, ", "), entry.title)
    end
  end
  return table.concat(lines, "\n")
end

return M
