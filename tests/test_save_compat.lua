-- SAVE_COMPAT (D74, #183): every save is stamped, an out-of-date stamp is never loaded or deleted by
-- itself, and a change to the saved-state shape fails here until the stamp is bumped.
local T = require("harness")
local Save = require("src.core.save")
local serialize = require("src.core.serialize")
local tuning = require("src.core.tuning")
local Registry = require("src.core.registry")
local World = require("src.sim.world")
local Slots = require("src.scenes.slots")

local tun = tuning.load()
local reg = Registry.new():loadAll()

-- Compatibility ---------------------------------------------------------------------------------

T.test("compat: the current stamp loads; older, missing and newer stamps do not", function()
  T.eq(Save.compatibility({ compat = Save.SAVE_COMPAT }), "ok")
  T.eq(Save.compatibility({ compat = Save.SAVE_COMPAT - 1 }), "older")
  T.eq(Save.compatibility({}), "older", "a save from before the stamp existed")
  T.eq(Save.compatibility({ compat = "2" }), "older", "a stamp that is not a number")
  T.eq(Save.compatibility({ compat = Save.SAVE_COMPAT + 1 }), "newer")
  T.eq(Save.compatibility(Save.newSlotData("New")), "ok", "a new slot carries the stamp")
end)

T.test("compat: every write stamps the slot and its sidecar", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  local data = Save.newSlotData("Stamped")
  data.compat = nil -- whatever made the table, the write stamps it
  store:write(1, data)
  T.eq(serialize.decode(backend.files["slot1.sav"]).compat, Save.SAVE_COMPAT)
  T.eq(serialize.decode(backend.files["slot1.hdr"]).compat, Save.SAVE_COMPAT)
  T.eq(store:list()[1].state, "ok")
end)

T.test("compat: an older slot is listed as outdated and its file is never touched", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 2 })
  local old = Save.newSlotData("Old farm")
  old.compat = Save.SAVE_COMPAT - 1
  local contents = serialize.encode(old)
  backend.files["slot1.sav"] = contents
  local unstamped = Save.newSlotData("Ancient")
  unstamped.compat = nil
  backend.files["slot2.sav"] = serialize.encode(unstamped)
  for _ = 1, 2 do -- the second list reads the sidecar the first one wrote
    local list = store:list()
    T.eq(list[1].state, "outdated")
    T.eq(list[1].compat, "older")
    T.eq(list[1].name, "Old farm")
    T.eq(list[2].state, "outdated", "no stamp is older")
  end
  T.eq(backend.files["slot1.sav"], contents, "listing never rewrites or deletes an outdated save")
  T.errors(function()
    store:write(1, store:read(1))
  end, "re-stamp")
  T.eq(backend.files["slot1.sav"], contents, "nor can a read-and-write upgrade it by accident")
  store:delete(1) -- only the player's confirmed Delete does this
  T.eq(store:list()[1].state, "empty")
end)

T.test("compat: a newer slot is outdated too, with its own words", function()
  local backend = Save.memoryBackend()
  local store = Save.new(backend, { slotCount = 1 })
  local future = Save.newSlotData("Future")
  future.compat = Save.SAVE_COMPAT + 1
  backend.files["slot1.sav"] = serialize.encode(future)
  T.eq(store:list()[1].compat, "newer")
  local title, message = Slots.outdatedText("Future", "newer")
  T.truthy(title:find("Future", 1, true))
  T.truthy(message:find("newer", 1, true))
  local _, older = Slots.outdatedText("Old", "older")
  T.truthy(older:find("from an older version and can't be loaded", 1, true))
end)

-- The reminder: saved-state shape fingerprint -------------------------------------------------------

-- Key paths and value types of a table, sorted. Arrays collapse to "[]" (their first element stands
-- for all). Depth-limited so ids used as keys (resources, cells) do not make the shape noisy.
local MAX_DEPTH = 3
local function paths(t, prefix, depth, out)
  local keys = {}
  for k in pairs(t) do
    if type(k) == "string" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v, path = t[k], prefix .. "." .. k
    out[#out + 1] = path .. ":" .. type(v)
    if type(v) == "table" and depth < MAX_DEPTH then
      paths(v, path, depth + 1, out)
    end
  end
  if t[1] ~= nil then
    out[#out + 1] = prefix .. "[]:" .. type(t[1])
    if type(t[1]) == "table" and depth < MAX_DEPTH then
      paths(t[1], prefix .. "[]", depth + 1, out)
    end
  end
  return out
end

local function fingerprint(list)
  local h = 5381
  local s = table.concat(list, "\n")
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

-- The shape of a default new game as a slot would save it.
local function newGameShape()
  local data = Save.newSlotData("Shape")
  local world = World.new({ registry = reg, tuning = tun, meta = data.meta }, World.newState(1))
  data.run = world.state
  return paths(serialize.decode(serialize.encode(data)), "slot", 1, {})
end

-- When this fails: the saved state changed shape. If old saves can no longer be read correctly,
-- bump Save.SAVE_COMPAT in game/src/core/save.lua (no migrations before launch, D74), then update
-- EXPECTED below to the new stamp and fingerprint the failure prints.
local EXPECTED = { compat = 4, fingerprint = "d7ba1f7e" }

T.test("compat: the saved-state shape matches the SAVE_COMPAT it was stamped with", function()
  local list = newGameShape()
  local now = fingerprint(list)
  if now ~= EXPECTED.fingerprint or Save.SAVE_COMPAT ~= EXPECTED.compat then
    print("Saved-state shape (" .. #list .. " paths):\n  " .. table.concat(list, "\n  "))
  end
  T.eq(
    now,
    EXPECTED.fingerprint,
    "the new-game saved-state shape changed: bump Save.SAVE_COMPAT in game/src/core/save.lua and set "
      .. "EXPECTED in tests/test_save_compat.lua to { compat = <new stamp>, fingerprint = \""
      .. now
      .. "\" }"
  )
  T.eq(Save.SAVE_COMPAT, EXPECTED.compat, "SAVE_COMPAT changed: update EXPECTED.compat with the fingerprint")
end)

T.test("compat: the fingerprint is stable for the same build", function()
  T.eq(fingerprint(newGameShape()), fingerprint(newGameShape()))
end)
