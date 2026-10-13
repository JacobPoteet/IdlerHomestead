-- Sound library (GDD D100): turns a cue id into playable sources. Real files win over placeholders:
--   1. files listed in the cue's `files` field,
--   2. drop-in files  <dir>/<bus>/<cue>.<ext>  and  <dir>/<bus>/<cue>_1.<ext> .. _N,
--   3. otherwise the synthesized placeholder (src/audio/synth.lua).
-- A file that is missing or will not decode is skipped, and a cue with nothing playable is silent:
-- nothing here ever raises. See docs/AUDIO.md.

local Synth = require("src.audio.synth")

local Library = {}
Library.__index = Library

--- opts: backend (src/audio/backend.lua), fs ({ getInfo(path) }, love.filesystem), sounds (the sounds
--- data), cfg (tuning.audio).
function Library.new(opts)
  return setmetatable({
    backend = opts.backend,
    fs = opts.fs,
    sounds = opts.sounds,
    cfg = opts.cfg,
    cache = {},
  }, Library)
end

--- Forget loaded sources, so files dropped in while the game runs are found (debug reload).
function Library:invalidate()
  self.cache = {}
end

function Library:cue(id)
  return self.sounds.cues[id]
end

--- Every cue id, sorted by bus then id.
function Library:ids()
  local order = {}
  for i, bus in ipairs(self.sounds.buses) do
    order[bus] = i
  end
  local ids = {}
  for id in pairs(self.sounds.cues) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    local ba, bb = order[self.sounds.cues[a].bus] or 99, order[self.sounds.cues[b].bus] or 99
    if ba ~= bb then
      return ba < bb
    end
    return a < b
  end)
  return ids
end

--- Candidate file paths for a cue, in the order they are tried.
function Library:candidates(id)
  local def = self.sounds.cues[id]
  local cfg = self.cfg
  local list, seen = {}, {}
  local function add(path)
    if not seen[path] then
      seen[path] = true
      list[#list + 1] = path
    end
  end
  for _, path in ipairs(def.files or {}) do
    add(path)
  end
  local base = cfg.dir .. "/" .. def.bus .. "/" .. id
  for _, ext in ipairs(cfg.extensions) do
    add(base .. "." .. ext)
  end
  for n = 1, cfg.maxVariants do
    for _, ext in ipairs(cfg.extensions) do
      add(base .. "_" .. n .. "." .. ext)
    end
  end
  return list
end

local function exists(fs, path)
  local ok, info = pcall(fs.getInfo, path)
  return ok and info ~= nil and (info.type == nil or info.type == "file"), ok and info or nil
end

local function load(self, id)
  local def = self.sounds.cues[id]
  local entry = { id = id, sources = {}, files = {}, synth = false }
  for _, path in ipairs(self:candidates(id)) do
    local found, info = exists(self.fs, path)
    if found then
      local stream = info and info.size and info.size >= self.cfg.streamBytes
      local ok, source = pcall(self.backend.newSource, path, stream and "stream" or "static")
      if ok and source then
        source:setLooping(def.loop == true)
        entry.sources[#entry.sources + 1] = source
        entry.files[#entry.files + 1] = path
        entry.stream = entry.stream or stream
      end
    end
  end
  if #entry.sources == 0 and def.gen then
    local ok, source = pcall(function()
      local out = Synth.render(def.gen, def.args, { rate = self.cfg.rate, seed = Synth.seedOf(id) })
      if not out then
        return nil
      end
      local data = self.backend.newSoundData(out.samples, out.rate)
      local s = self.backend.newSource(data, "static")
      s:setLooping(def.loop == true)
      return s
    end)
    if ok and source then
      entry.sources[1] = source
      entry.synth = true
    end
  end
  return entry
end

--- The loaded entry of a cue: { sources = {...}, files = {paths}, synth = bool }. Unknown cues give nil.
function Library:entry(id)
  if not self.sounds.cues[id] then
    return nil
  end
  local entry = self.cache[id]
  if not entry then
    entry = load(self, id)
    self.cache[id] = entry
  end
  return entry
end

--- One source for a cue, chosen with `roll` in 0..1 when there are several files; nil if it has none.
function Library:pick(id, roll)
  local entry = self:entry(id)
  if not entry or #entry.sources == 0 then
    return nil
  end
  local i = math.min(#entry.sources, math.floor(roll * #entry.sources) + 1)
  return entry.sources[i], entry
end

--- "synth", "file", "files x3" or "silent": what a cue currently sounds like.
function Library:describe(id)
  local entry = self:entry(id)
  if not entry or #entry.sources == 0 then
    return "silent"
  end
  if entry.synth then
    return "synth"
  end
  return #entry.files == 1 and "file" or ("files x" .. #entry.files)
end

return Library
