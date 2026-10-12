-- Save slots (GDD §7.11).
--
-- A slot file holds plain data:
--   { version, name, header = { year?, season?, playtime }, meta = {...}, run = {...} | nil }
-- `meta` is the persistent career (knowledge); `run` is the current run and is discarded on failure.
-- `header` is a small summary written by the session so the slot list doesn't need the sim.
--
-- Each write also stores the header in a small slotN.hdr sidecar, which `list` reads instead of
-- decoding the whole slot (see headerPath).
--
-- Storage goes through a backend so tests can run in memory. Each write first copies the
-- previous file to a .bak, and reads fall back to the backup if the main file is unreadable.

local serialize = require("src.core.serialize")

local Save = {}
Save.__index = Save

Save.FORMAT_VERSION = 1

-- Upgrades for old save formats: migrations[n] converts a version-n save to version n+1.
local migrations = {}

--- Backend using love.filesystem (the game's save directory).
function Save.loveBackend()
  return {
    read = function(path)
      if not love.filesystem.getInfo(path, "file") then
        return nil
      end
      return love.filesystem.read(path)
    end,
    write = function(path, contents)
      return love.filesystem.write(path, contents)
    end,
    remove = function(path)
      return love.filesystem.remove(path)
    end,
    size = function(path)
      local info = love.filesystem.getInfo(path, "file")
      return info and info.size or nil
    end,
  }
end

--- In-memory backend for tests. `files` is exposed so tests can corrupt them.
function Save.memoryBackend()
  local files = {}
  return {
    files = files,
    read = function(path)
      return files[path]
    end,
    write = function(path, contents)
      files[path] = contents
      return true
    end,
    remove = function(path)
      files[path] = nil
      return true
    end,
    size = function(path)
      return files[path] and #files[path] or nil
    end,
  }
end

--- opts.slotCount: number of slots.
function Save.new(backend, opts)
  assert(opts and opts.slotCount, "Save.new requires opts.slotCount")
  return setmetatable({ backend = backend, slotCount = opts.slotCount }, Save)
end

--- Fresh data for a new slot.
function Save.newSlotData(name)
  return { version = Save.FORMAT_VERSION, name = name, header = { playtime = 0 }, meta = {}, run = nil }
end

function Save:checkIndex(index)
  assert(type(index) == "number" and index >= 1 and index <= self.slotCount, "Invalid save slot " .. tostring(index))
end

local function mainPath(index)
  return "slot" .. index .. ".sav"
end

local function backupPath(index)
  return "slot" .. index .. ".bak"
end

-- Sidecar with just the slot header, so the slot list never decodes a whole run. It records the
-- byte size of the slot file it was written for; a mismatch (file replaced, truncated or edited
-- outside the game) makes `list` ignore the sidecar and fall back to a full read.
local function headerPath(index)
  return "slot" .. index .. ".hdr"
end

local function decodeSlot(contents)
  if not contents then
    return nil, "missing"
  end
  local data, err = serialize.decode(contents)
  if type(data) ~= "table" then
    return nil, err or "not a table"
  end
  local version = data.version or 0
  if type(version) ~= "number" then
    return nil, "save has an invalid version"
  end
  if version > Save.FORMAT_VERSION then
    return nil, "save is from a newer version of the game"
  end
  while version < Save.FORMAT_VERSION do
    local migrate = migrations[version]
    if not migrate then
      return nil, "no migration from save version " .. version
    end
    local ok, migrated = pcall(migrate, data)
    if not ok or type(migrated) ~= "table" then
      return nil, "migration from save version " .. version .. " failed"
    end
    data = migrated
    version = version + 1
    data.version = version
  end
  return data
end

--- Read a slot. Returns data, or nil + reason ("empty", or why it couldn't be read).
--- The second return is true when the data came from the backup file.
function Save:read(index)
  self:checkIndex(index)
  local mainContents = self.backend.read(mainPath(index))
  local data, err = decodeSlot(mainContents)
  if data then
    return data, false
  end
  local backup = decodeSlot(self.backend.read(backupPath(index)))
  if backup then
    return backup, true
  end
  if not mainContents then
    return nil, "empty"
  end
  return nil, err
end

--- Write a slot, keeping the previous version as a backup.
function Save:write(index, data)
  self:checkIndex(index)
  data.version = Save.FORMAT_VERSION
  local contents = serialize.encode(data)
  -- Only rotate a readable file into the backup; a corrupt main must never replace a good .bak.
  local previous = self.backend.read(mainPath(index))
  if previous and decodeSlot(previous) then
    self.backend.write(backupPath(index), previous)
  end
  local ok, err = self.backend.write(mainPath(index), contents)
  if not ok then
    return false, err
  end
  self:writeHeader(index, data, #contents)
  return true
end

--- Write the header sidecar for a slot whose main file is `size` bytes. Best effort: the sidecar
--- is only a cache, so a failed write just means `list` falls back to a full read.
function Save:writeHeader(index, data, size)
  self.backend.write(
    headerPath(index),
    serialize.encode({ name = data.name, header = data.header or {}, size = size })
  )
end

--- The cached header for a slot, or nil when it is missing, unreadable or stale.
function Save:readHeader(index)
  local contents = self.backend.read(headerPath(index))
  if not contents then
    return nil
  end
  local cached = serialize.decode(contents)
  if type(cached) ~= "table" or type(cached.header) ~= "table" or cached.size ~= self.backend.size(mainPath(index)) then
    return nil
  end
  return cached
end

function Save:delete(index)
  self:checkIndex(index)
  self.backend.remove(mainPath(index))
  self.backend.remove(backupPath(index))
  self.backend.remove(headerPath(index))
end

--- Summaries for the slot screen: { index, state = "empty"|"ok"|"corrupt", name?, header?, error? }.
function Save:list()
  local slots = {}
  for i = 1, self.slotCount do
    local cached = self:readHeader(i)
    local data, err
    if not cached then
      local fromBackup
      data, err = self:read(i)
      if data then
        fromBackup = err
        err = nil
      end
      if data and not fromBackup then
        -- Saves from before the sidecar existed: build it now so the next list is cheap.
        local size = self.backend.size(mainPath(i))
        if size then
          self:writeHeader(i, data, size)
        end
      end
    end
    if cached then
      slots[i] = { index = i, state = "ok", name = cached.name, header = cached.header }
    elseif data then
      slots[i] = { index = i, state = "ok", name = data.name, header = data.header or {} }
    elseif err == "empty" then
      slots[i] = { index = i, state = "empty" }
    else
      slots[i] = { index = i, state = "corrupt", error = err }
    end
  end
  return slots
end

return Save
