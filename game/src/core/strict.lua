-- Makes tables error on reads of missing keys and on creation of new keys.
-- Used for tuning data and content definitions so typos fail loudly instead of becoming nil.
--
-- The metatable is attached to the real table (not a proxy), so pairs/ipairs/# keep working.
-- Existing keys can still be reassigned, which allows live tweaking of tuning values.
-- Arrays are left alone so length checks and ipairs never trip the guard.

local M = {}

local function isArray(t)
  return #t > 0 and next(t, #t) == nil
end

function M.wrap(t, path)
  path = path or "?"
  for k, v in pairs(t) do
    if type(v) == "table" and getmetatable(v) == nil then
      M.wrap(v, path .. "." .. tostring(k))
    end
  end
  if isArray(t) then
    return t
  end
  return setmetatable(t, {
    __index = function(_, key)
      error(string.format("Unknown key '%s' in %s", tostring(key), path), 2)
    end,
    __newindex = function(_, key)
      error(string.format("Cannot add new key '%s' to %s", tostring(key), path), 2)
    end,
  })
end

--- Read a key that may legitimately be absent, bypassing the guard.
function M.get(t, key)
  return rawget(t, key)
end

return M
