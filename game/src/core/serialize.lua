-- Plain-data serializer for save files.
-- Supports nil, booleans, finite numbers, strings, and tables with string/number keys.
-- Output is deterministic (sorted keys) and human-readable, which helps when debugging saves.

local M = {}

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function goto if in
  local nil not or repeat return then true until while]]):gmatch("%a+") do
  KEYWORDS[word] = true
end

local function isIdentifier(s)
  return s:match("^[%a_][%w_]*$") ~= nil and not KEYWORDS[s]
end

local function isArray(t)
  local n = #t
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count == n
end

local function encodeNumber(v)
  if v ~= v or v == math.huge or v == -math.huge then
    error("serialize: cannot encode non-finite number", 0)
  end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    return string.format("%d", v)
  end
  return string.format("%.17g", v)
end

local function keyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    return ta == "number"
  end
  return a < b
end

local encode

local function encodeTable(t, indent, seen, out)
  if seen[t] then
    error("serialize: cycle detected", 0)
  end
  seen[t] = true
  local pad = string.rep("  ", indent + 1)
  if next(t) == nil then
    out[#out + 1] = "{}"
  elseif isArray(t) then
    out[#out + 1] = "{\n"
    for i = 1, #t do
      out[#out + 1] = pad
      encode(t[i], indent + 1, seen, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = string.rep("  ", indent) .. "}"
  else
    local keys = {}
    for k in pairs(t) do
      local kt = type(k)
      if kt ~= "string" and kt ~= "number" then
        error("serialize: unsupported key type " .. kt, 0)
      end
      keys[#keys + 1] = k
    end
    table.sort(keys, keyOrder)
    out[#out + 1] = "{\n"
    for _, k in ipairs(keys) do
      out[#out + 1] = pad
      if type(k) == "string" and isIdentifier(k) then
        out[#out + 1] = k
      elseif type(k) == "string" then
        out[#out + 1] = string.format("[%q]", k)
      else
        out[#out + 1] = "[" .. encodeNumber(k) .. "]"
      end
      out[#out + 1] = " = "
      encode(t[k], indent + 1, seen, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = string.rep("  ", indent) .. "}"
  end
  seen[t] = nil
end

encode = function(v, indent, seen, out)
  local tv = type(v)
  if tv == "nil" then
    out[#out + 1] = "nil"
  elseif tv == "boolean" then
    out[#out + 1] = tostring(v)
  elseif tv == "number" then
    out[#out + 1] = encodeNumber(v)
  elseif tv == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif tv == "table" then
    encodeTable(v, indent, seen, out)
  else
    error("serialize: unsupported value type " .. tv, 0)
  end
end

--- Encode a value to a Lua source string.
function M.encode(value)
  local out = {}
  encode(value, 0, {}, out)
  return table.concat(out)
end

--- Decode a string produced by encode(). Returns value, or nil + error message.
--- Runs in an empty environment and rejects precompiled bytecode.
function M.decode(str)
  if type(str) ~= "string" then
    return nil, "decode: expected string"
  end
  if str:byte(1) == 27 then
    return nil, "decode: bytecode not allowed"
  end
  local fn, err = loadstring("return " .. str, "=save")
  if not fn then
    return nil, err
  end
  setfenv(fn, {})
  local ok, result = pcall(fn)
  if not ok then
    return nil, result
  end
  return result
end

return M
