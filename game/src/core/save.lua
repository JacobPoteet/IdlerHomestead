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

local Gridpack = require("src.core.gridpack")
local serialize = require("src.core.serialize")

local Save = {}
Save.__index = Save

Save.FORMAT_VERSION = 1

-- Upgrades for old slot-file formats: migrations[n] converts a version-n file to version n+1. Empty
-- by policy before launch: a change to the saved state bumps SAVE_COMPAT instead (D74).
local migrations = {}

--- The saved-state compatibility stamp (D74, #183): the one place it is defined. Every write stamps
--- it into the slot as `compat`; a slot with any other stamp (or none) cannot be loaded, and the slot
--- screen offers to delete it or keep it untouched. No migrations before launch: bump this whenever
--- the shape of the saved run or meta changes in a way older code or data cannot read, and update the
--- fingerprint in tests/test_save_compat.lua (that test fails until both are done).
--- History: 1 = before the stamp existed (unstamped saves), 2 = shelf-life batches (D73), 3 = keep
--- targets and the truck load replace the sell crate (D75), 4 = placement orders and held field tiles (D79), 5 = condition at the last dawns in the alert state (D90), 6 = `skipped` flag in the slot's tip state (meta.ftue, D99), 7 = the run's grid arrays (terrain, soil, waterTable) are written as compact strings (D103, #21), 8 = one wood: firewood and seasoned_firewood leave the ledger and the routine list, the nightly warmth is a seasonal curve (D104, #247), 9 = progress metrics: run summaries carry yearsSurvived, bestYearIncome and newBest, meta.career.best holds the slot's bests, run state gains `income` (D117, #275), 10 = the Great Winter and Established: the slot meta gains `established` = { run, year, seen }, run summaries carry greatWinter and the slot best career.best.greatWinter (D117, #277), 11 = run state gains `log`, the message log's lines (D120, #224).
Save.SAVE_COMPAT = 12

--- How a slot's data relates to this build: "ok", "older" (no stamp or a lower one) or "newer".
function Save.compatibility(data)
  local stamp = type(data) == "table" and data.compat or nil
  if type(stamp) ~= "number" or stamp < Save.SAVE_COMPAT then
    return "older"
  elseif stamp > Save.SAVE_COMPAT then
    return "newer"
  end
  return "ok"
end

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

--- Fresh data for a new slot. `opts.sandbox` makes it a Sandbox slot (D134): `meta.sandbox` is the flag the sim
--- reads; the header repeats it so the slot list can tag the slot without loading the run.
function Save.newSlotData(name, opts)
  local sandbox = opts and opts.sandbox or nil
  return {
    version = Save.FORMAT_VERSION,
    compat = Save.SAVE_COMPAT,
    name = name,
    header = { playtime = 0, sandbox = sandbox },
    meta = { sandbox = sandbox },
    run = nil,
  }
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

-- The slot as it is written: the run's grid arrays in their compact string form (D103). A copy; the
-- live data keeps its plain arrays.
local function forDisk(data)
  local run = data.run
  if type(run) ~= "table" or type(run.grid) ~= "table" then
    return data
  end
  local copy, runCopy = {}, {}
  for k, v in pairs(data) do
    copy[k] = v
  end
  for k, v in pairs(run) do
    runCopy[k] = v
  end
  runCopy.grid = Gridpack.pack(run.grid)
  copy.run = runCopy
  return copy
end

Save.forDisk = forDisk

-- `keepPacked` skips restoring the grid arrays, for a check that only needs to know the file reads.
local function decodeSlot(contents, keepPacked)
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
  if not keepPacked and type(data.run) == "table" and type(data.run.grid) == "table" then
    local ok, unpackErr = pcall(Gridpack.unpack, data.run.grid)
    if not ok then
      return nil, "save has a damaged map: " .. tostring(unpackErr)
    end
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

--- Write a slot, keeping the previous version as a backup. Stamps the current SAVE_COMPAT, so only
--- data this build made or loaded may be written (the slot screen never writes an outdated slot).
function Save:write(index, data)
  self:checkIndex(index)
  assert(data.compat == nil or data.compat == Save.SAVE_COMPAT, "refusing to re-stamp a save from another version")
  data.version = Save.FORMAT_VERSION
  data.compat = Save.SAVE_COMPAT
  local contents = serialize.encode(forDisk(data))
  -- Only rotate a readable file into the backup; a corrupt main must never replace a good .bak.
  local previous = self.backend.read(mainPath(index))
  if previous and decodeSlot(previous, true) then
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
    serialize.encode({ name = data.name, header = data.header or {}, compat = data.compat, size = size })
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

--- Summaries for the slot screen: { index, state = "empty"|"ok"|"outdated"|"corrupt", name?, header?,
--- compat? ("older"|"newer" for an outdated slot), error? }. An outdated slot is readable but must not
--- be played (D74); the file is left as it is until the player deletes it.
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
    local found = cached or data
    if found then
      local compat = Save.compatibility(found)
      slots[i] = {
        index = i,
        state = compat == "ok" and "ok" or "outdated",
        compat = compat ~= "ok" and compat or nil,
        name = found.name,
        header = found.header or {},
      }
    elseif err == "empty" then
      slots[i] = { index = i, state = "empty" }
    else
      slots[i] = { index = i, state = "corrupt", error = err }
    end
  end
  return slots
end

return Save
