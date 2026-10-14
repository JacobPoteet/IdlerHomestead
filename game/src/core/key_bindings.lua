-- Key bindings: the player's overrides merged over the defaults in tuning.input.keyActions (D121, #237).
-- Pure logic (no love.*), so the merge, conflicts and reserved keys are unit-tested. The defaults stay the
-- single table in data/tuning/input.lua; the overrides are a small table { action = key } kept in the
-- settings file (src/core/settings.lua), never in a save slot.
--
-- Rules, all enforced here so a hand-edited or stale settings file can never break input:
--   * only the actions in tuning.input.rebindable can be rebound; each has exactly one key;
--   * a reserved key (tuning.input.reservedKeys, the pan and zoom keys, and the keys of the fixed
--     actions such as cancel) cannot be bound to anything;
--   * no key ever belongs to two actions, and no action is ever left without a key.

local strict = require("src.core.strict")

local M = {}

local function setOf(list)
  local out = {}
  for _, v in ipairs(list) do
    out[v] = true
  end
  return out
end

--- The rebindable action names, in display order.
function M.actions(inputCfg)
  return inputCfg.rebindable
end

--- The default key of `action` (the key that maps to it in tuning.input.keyActions), or nil.
function M.defaultKey(inputCfg, action)
  for key, name in pairs(inputCfg.keyActions) do
    if name == action then
      return key
    end
  end
  return nil
end

--- True if `key` may not be bound to a rebindable action.
function M.isReserved(inputCfg, key)
  if setOf(inputCfg.reservedKeys)[key] then
    return true
  end
  if strict.get(inputCfg.panKeys, key) ~= nil or strict.get(inputCfg.zoomKeys, key) ~= nil then
    return true
  end
  local rebindable = setOf(inputCfg.rebindable)
  local name = strict.get(inputCfg.keyActions, key)
  return name ~= nil and not rebindable[name] -- a fixed action's key (cancel on Esc)
end

local function validKey(key)
  return type(key) == "string" and key ~= "" and #key <= 24
end

--- Overrides cleaned up: unknown actions, bad or reserved keys, entries equal to the default and
--- clashes are dropped (the action then falls back to its default). Returns a new table.
function M.sanitize(inputCfg, raw)
  local rebindable = setOf(inputCfg.rebindable)
  local kept = {}
  if type(raw) == "table" then
    for action, key in pairs(raw) do
      if rebindable[action] and validKey(key) and not M.isReserved(inputCfg, key) and key ~= M.defaultKey(inputCfg, action) then
        kept[action] = key
      end
    end
  end
  -- Drop clashes until none is left: two overrides on one key (the first action in display order wins),
  -- or an override on the default key of an action that is not itself rebound.
  local changed = true
  while changed do
    changed = false
    local owner = {}
    for _, action in ipairs(inputCfg.rebindable) do
      local key = kept[action]
      if key then
        if owner[key] then
          kept[action] = nil
          changed = true
        else
          owner[key] = action
        end
      end
    end
    for _, action in ipairs(inputCfg.rebindable) do
      if not kept[action] then
        local holder = owner[M.defaultKey(inputCfg, action)]
        if holder then
          kept[holder] = nil
          changed = true
          break
        end
      end
    end
  end
  return kept
end

--- Key of every rebindable action after the overrides: { action = key }.
function M.effective(inputCfg, overrides)
  local clean = M.sanitize(inputCfg, overrides)
  local out = {}
  for _, action in ipairs(inputCfg.rebindable) do
    out[action] = clean[action] or M.defaultKey(inputCfg, action)
  end
  return out
end

--- The map Input reads: key -> action name. Fixed actions keep their default keys.
function M.keyMap(inputCfg, overrides)
  local rebindable = setOf(inputCfg.rebindable)
  local map = {}
  for key, action in pairs(inputCfg.keyActions) do
    if not rebindable[action] then
      map[key] = action
    end
  end
  for action, key in pairs(M.effective(inputCfg, overrides)) do
    map[key] = action
  end
  return map
end

--- The action that currently owns `key`, or nil.
function M.holder(inputCfg, overrides, key)
  for action, k in pairs(M.effective(inputCfg, overrides)) do
    if k == key then
      return action
    end
  end
  return nil
end

local function fromEffective(inputCfg, eff)
  local out = {}
  for action, key in pairs(eff) do
    if key ~= M.defaultKey(inputCfg, action) then
      out[action] = key
    end
  end
  return M.sanitize(inputCfg, out)
end

--- Try to bind `key` to `action`. Returns status, overrides, other:
---   "ok"       bound; `overrides` is the new table
---   "same"     the action already has this key; nothing changed
---   "conflict" another action (`other`) owns the key; nothing changed (call M.swap to trade keys)
---   "reserved" the key cannot be used; "unknown" the action cannot be rebound
function M.bind(inputCfg, overrides, action, key)
  if not setOf(inputCfg.rebindable)[action] then
    return "unknown", overrides
  end
  if not validKey(key) or M.isReserved(inputCfg, key) then
    return "reserved", overrides
  end
  local eff = M.effective(inputCfg, overrides)
  if eff[action] == key then
    return "same", overrides
  end
  local other = M.holder(inputCfg, overrides, key)
  if other then
    return "conflict", overrides, other
  end
  eff[action] = key
  return "ok", fromEffective(inputCfg, eff)
end

--- Give `action` the key and hand its old key to the action that owned it. Returns status, overrides, other
--- (status "swapped", or what M.bind says when the key is free or unusable).
function M.swap(inputCfg, overrides, action, key)
  local status, result, other = M.bind(inputCfg, overrides, action, key)
  if status ~= "conflict" then
    return status, result, other
  end
  local eff = M.effective(inputCfg, overrides)
  eff[other], eff[action] = eff[action], key
  return "swapped", fromEffective(inputCfg, eff), other
end

--- Back to the default for one action (or all, when `action` is nil). Returns a new overrides table.
function M.reset(inputCfg, overrides, action)
  local clean = M.sanitize(inputCfg, overrides)
  if action == nil then
    return {}
  end
  clean[action] = nil
  return M.sanitize(inputCfg, clean)
end

return M
